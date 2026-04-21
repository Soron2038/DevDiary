import SwiftUI
import AppKit

/// Modal sheet for managing all remote forge accounts (GitHub + GitLab instances).
/// Opened from the Settings tab via a "Manage Accounts…" button.
struct AccountsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var accounts: [ForgeAccount] = []
    @State private var connectionStates: [String: Bool] = [:]
    @State private var usernames: [String: String] = [:]
    @State private var showingAddGitLab = false
    @State private var showingDeleteAllAlert = false
    @State private var statusBanner: String?
    @State private var statusKind: BannerKind = .info

    // GitHub-specific state
    @State private var showingGitHubDeviceFlow = false
    @State private var showingGitHubSetup = false
    @State private var deviceCode: GitHubService.DeviceCode?
    @State private var pollingTask: Task<Void, Never>?
    @State private var clientIdInput: String = ""
    @State private var gitHubEnvironment: GitHubService.GitEnvironment = GitHubService.shared.selectedEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let statusBanner {
                        StatusBannerView(text: statusBanner, kind: statusKind)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }

                    ForEach(accounts) { account in
                        AccountCard(
                            account: account,
                            isConnected: connectionStates[account.id] ?? false,
                            username: usernames[account.id],
                            environment: account.kind == .github ? gitHubEnvironment : nil,
                            clientIdInput: account.kind == .github ? Binding(
                                get: { clientIdInput },
                                set: { clientIdInput = $0 }
                            ) : nil,
                            onConnect: { handleConnect(account) },
                            onDisconnect: { handleDisconnect(account) },
                            onRemove: { handleRemove(account) },
                            onConfigureClientId: { showGitHubSetup() },
                            onEnvironmentChanged: { env in
                                gitHubEnvironment = env
                                GitHubService.shared.setEnvironment(env)
                                refresh()
                            }
                        )
                        .padding(.horizontal, 16)
                    }

                    HStack(spacing: 12) {
                        Button {
                            showingAddGitLab = true
                        } label: {
                            Label(String(localized: "accounts.addGitLab"), systemImage: "plus")
                        }
                        Spacer()
                        Button(role: .destructive) {
                            showingDeleteAllAlert = true
                        } label: {
                            Text(String(localized: "accounts.deleteAllTokens"))
                        }
                        .foregroundColor(.red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .padding(.bottom, 12)
            }
        }
        .frame(width: 560, height: 520)
        .onAppear { refresh() }
        .sheet(isPresented: $showingAddGitLab) {
            AddGitLabInstanceSheet(
                onCancel: { showingAddGitLab = false },
                onConnected: { account in
                    showingAddGitLab = false
                    flash(
                        String(format: String(localized: "accounts.banner.gitlabAdded"), account.displayName),
                        kind: .success
                    )
                    refresh()
                }
            )
        }
        .sheet(isPresented: $showingGitHubSetup) {
            GitHubClientIdSheet(
                clientIdInput: $clientIdInput,
                onSave: {
                    GitHubService.shared.saveClientId(clientIdInput)
                    showingGitHubSetup = false
                    flash(String(localized: "status.clientIdSaved"), kind: .success)
                },
                onCancel: { showingGitHubSetup = false }
            )
        }
        .sheet(isPresented: $showingGitHubDeviceFlow, onDismiss: {
            pollingTask?.cancel()
            pollingTask = nil
        }) {
            if let deviceCode {
                GitHubDeviceAuthSheet(
                    device: deviceCode,
                    onOpen: {
                        let url = deviceCode.verification_uri_complete ?? deviceCode.verification_uri
                        GitHubService.shared.openInBrowser(url)
                    },
                    onCancel: {
                        showingGitHubDeviceFlow = false
                    }
                )
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(String(localized: "github.auth.waiting"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button(String(localized: "button.cancel")) {
                        pollingTask?.cancel()
                        showingGitHubDeviceFlow = false
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 320, height: 180)
            }
        }
        .alert(String(localized: "accounts.deleteAllTokens.confirm.title"),
               isPresented: $showingDeleteAllAlert) {
            Button(String(localized: "button.cancel"), role: .cancel) {}
            Button(String(localized: "accounts.deleteAllTokens.confirm.delete"), role: .destructive) {
                GitHubService.shared.disconnectAll()
                for account in ForgeRegistry.shared.accounts(of: .gitlab) {
                    try? ForgeRegistry.shared.provider(for: account).disconnect()
                }
                flash(String(localized: "status.allTokensDeleted"), kind: .success)
                refresh()
            }
        } message: {
            Text(String(localized: "accounts.deleteAllTokens.confirm.message"))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(String(localized: "accounts.title")).font(.title3).fontWeight(.semibold)
            Spacer()
            Button(String(localized: "button.done")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    // MARK: - Refresh

    private func refresh() {
        accounts = ForgeRegistry.shared.accounts()
        var states: [String: Bool] = [:]
        var names: [String: String] = [:]
        for account in accounts {
            let provider = ForgeRegistry.shared.provider(for: account)
            states[account.id] = provider.isConnected
            if account.kind == .github {
                clientIdInput = UserDefaults.standard.string(forKey: "GitHubClientID.\(gitHubEnvironment.rawValue)") ?? ""
            }
            if let stored = account.username {
                names[account.id] = stored
            }
        }
        connectionStates = states
        usernames = names

        // Kick off parallel username refresh for connected accounts
        Task {
            await withTaskGroup(of: (String, String?).self) { group in
                for account in accounts where connectionStates[account.id] == true {
                    group.addTask {
                        let provider = ForgeRegistry.shared.provider(for: account)
                        let username = try? await provider.verifyCredentials()
                        return (account.id, username)
                    }
                }
                var updates: [String: String] = [:]
                for await (id, username) in group {
                    if let username { updates[id] = username }
                }
                let snapshot = updates
                await MainActor.run {
                    for (id, username) in snapshot {
                        self.usernames[id] = username
                        if var account = ForgeRegistry.shared.account(id: id) {
                            account.username = username
                            ForgeRegistry.shared.updateAccount(account)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func handleConnect(_ account: ForgeAccount) {
        switch account.kind {
        case .github:
            Task { await startGitHubDeviceFlow() }
        case .gitlab:
            // GitLab reconnect = simply remove+re-add via sheet
            showingAddGitLab = true
        }
    }

    private func handleDisconnect(_ account: ForgeAccount) {
        let provider = ForgeRegistry.shared.provider(for: account)
        try? provider.disconnect()
        flash(String(localized: "status.disconnected"), kind: .success)
        refresh()
    }

    private func handleRemove(_ account: ForgeAccount) {
        ForgeRegistry.shared.removeAccount(id: account.id)
        flash(String(format: String(localized: "accounts.banner.removed"), account.displayName), kind: .success)
        refresh()
    }

    private func showGitHubSetup() {
        clientIdInput = UserDefaults.standard.string(forKey: "GitHubClientID.\(gitHubEnvironment.rawValue)") ?? ""
        showingGitHubSetup = true
    }

    private func startGitHubDeviceFlow() async {
        guard GitHubService.shared.clientId != nil else {
            await MainActor.run { showGitHubSetup() }
            return
        }
        await MainActor.run {
            deviceCode = nil
            showingGitHubDeviceFlow = true
        }
        do {
            let device = try await GitHubService.shared.beginDeviceFlow()
            await MainActor.run { self.deviceCode = device }
            pollingTask = Task { [device] in
                do {
                    try await GitHubService.shared.pollForToken(deviceCode: device.device_code, interval: device.interval)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    let username = try? await GitHubService.shared.fetchCurrentUserLogin()
                    await MainActor.run {
                        if let username {
                            self.usernames[ForgeAccount.gitHubAccountID] = username
                            if var account = ForgeRegistry.shared.account(id: ForgeAccount.gitHubAccountID) {
                                account.username = username
                                ForgeRegistry.shared.updateAccount(account)
                            }
                        }
                        self.showingGitHubDeviceFlow = false
                        self.flash(
                            username.map { String(format: String(localized: "status.connectedAs"), $0) } ?? String(localized: "status.connected"),
                            kind: .success
                        )
                        self.refresh()
                    }
                } catch is CancellationError {
                    // user cancelled
                } catch {
                    await MainActor.run {
                        self.showingGitHubDeviceFlow = false
                        self.flash(error.localizedDescription, kind: .error)
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.showingGitHubDeviceFlow = false
                self.flash(error.localizedDescription, kind: .error)
            }
        }
    }

    // MARK: - Banner

    enum BannerKind { case success, error, info }

    private func flash(_ text: String, kind: BannerKind) {
        let logKind: ActivityLogService.Kind = kind == .success ? .success : (kind == .error ? .error : .info)
        _ = ActivityLogService.shared.append(kind: logKind, text: text)
        withAnimation { self.statusBanner = text; self.statusKind = kind }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { self.statusBanner = nil }
        }
    }
}

// MARK: - Account Card

private struct AccountCard: View {
    let account: ForgeAccount
    let isConnected: Bool
    let username: String?
    let environment: GitHubService.GitEnvironment?
    var clientIdInput: Binding<String>?
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onRemove: () -> Void
    let onConfigureClientId: () -> Void
    let onEnvironmentChanged: (GitHubService.GitEnvironment) -> Void

    @State private var showingClientIdDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName).font(.headline)
                    if isConnected {
                        Text(connectedLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(String(localized: "accounts.notConnected"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isConnected {
                    Button(String(localized: "accounts.disconnect")) { onDisconnect() }
                } else {
                    Button(String(localized: "accounts.connect")) { onConnect() }
                        .buttonStyle(.borderedProminent)
                }

                if account.kind == .gitlab {
                    Button(role: .destructive) { onRemove() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .help(String(localized: "accounts.remove.help"))
                }
            }

            if account.kind == .github {
                Divider()
                if let env = environment {
                    HStack {
                        Text(String(localized: "accounts.github.environment")).font(.caption)
                        Picker("", selection: Binding(
                            get: { env },
                            set: { onEnvironmentChanged($0) }
                        )) {
                            Text(String(localized: "accounts.github.environment.dev")).tag(GitHubService.GitEnvironment.dev)
                            Text(String(localized: "accounts.github.environment.prod")).tag(GitHubService.GitEnvironment.prod)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        Spacer()
                        Button(String(localized: "accounts.github.configureClientId")) { onConfigureClientId() }
                            .buttonStyle(.link)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var connectedLabel: String {
        if let username {
            return String(format: String(localized: "accounts.connectedAs"), username)
        }
        return String(localized: "accounts.connected")
    }

    private var iconName: String {
        switch account.kind {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return "triangle.righthalf.filled"
        }
    }

    private var iconColor: Color {
        switch account.kind {
        case .github: return .primary
        case .gitlab: return .orange
        }
    }
}

// MARK: - Status Banner

private struct StatusBannerView: View {
    let text: String
    let kind: AccountsSheet.BannerKind

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text).font(.caption).fontWeight(.medium)
            Spacer()
        }
        .padding(8)
        .background(background)
        .cornerRadius(6)
    }

    private var background: Color {
        switch kind {
        case .success: return .green.opacity(0.15)
        case .error: return .red.opacity(0.15)
        case .info: return .blue.opacity(0.12)
        }
    }

    private var icon: String {
        switch kind {
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        case .info: return "info.circle"
        }
    }
}

// MARK: - Client-ID Sheet

private struct GitHubClientIdSheet: View {
    @Binding var clientIdInput: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "github.setup.title")).font(.headline)
            Text(String(localized: "github.setup.description"))
                .font(.caption).foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "github.setup.step1"), systemImage: "1.circle")
                Label(String(localized: "github.setup.step2"), systemImage: "2.circle")
                Label(String(localized: "github.setup.step3"), systemImage: "3.circle")
            }
            .labelStyle(.titleAndIcon)

            TextField(String(localized: "github.setup.clientId.placeholder"), text: $clientIdInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(String(localized: "github.setup.openGitHub")) {
                    if let url = URL(string: "https://github.com/settings/developers") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                Spacer()
                Button(String(localized: "button.cancel")) { onCancel() }
                Button(String(localized: "github.setup.save")) { onSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 520, height: 320)
    }
}

// MARK: - Device Auth Sheet

private struct GitHubDeviceAuthSheet: View {
    let device: GitHubService.DeviceCode
    let onOpen: () -> Void
    let onCancel: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "github.auth.title")).font(.headline)
            Text(String(localized: "github.auth.instructions"))
                .font(.caption).foregroundColor(.secondary)

            HStack(spacing: 12) {
                Text(device.user_code)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)

                Button(action: copyCode) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copied ? .green : .accentColor)
                }
                .buttonStyle(.plain)
                .help(String(localized: "github.auth.copyCode"))

                Spacer()

                Button(String(localized: "github.auth.openInBrowser")) { onOpen() }
                    .keyboardShortcut(.defaultAction)
            }
            Spacer()
            HStack {
                Spacer()
                Button(String(localized: "button.cancel")) { onCancel() }
            }
        }
        .padding()
        .frame(width: 420, height: 240)
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(device.user_code, forType: .string)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { withAnimation { copied = false } }
        }
    }
}
