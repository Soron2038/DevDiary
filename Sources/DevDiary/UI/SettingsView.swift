import SwiftUI
import ServiceManagement
import AppKit

/// Settings view with app configuration
struct SettingsView: View {
    // General settings
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    // Tracking settings
    @AppStorage("pollingInterval") private var pollingInterval = 60.0
    @AppStorage("sessionTimeout") private var sessionTimeout = 15.0
    
    // Privacy settings
    @AppStorage("dataRetentionDays") private var dataRetentionDays = 90

    // Accounts / GitHub
    @State private var isGitHubConnected = GitHubService.shared.isConnected
    @State private var githubLogin: String?
    @State private var showingGitHubAuth = false
    @State private var deviceCode: GitHubService.DeviceCode?
    @State private var authErrorMessage: String?
    @State private var pollingTask: Task<Void, Never>?

    // Token deletion confirmations
    @State private var showingDeleteTokenAlert = false
    @State private var showingDeleteAllTokensAlert = false

    // Accounts environment
    @State private var environment = GitHubService.shared.selectedEnvironment

    // Setup sheet
    @State private var showingGitHubSetup = false
    @State private var clientIdInput: String = (UserDefaults.standard.string(forKey: "GitHubClientID.dev") ?? "")

    // Status banner
    @State private var bannerText: String?
    @State private var bannerKind: BannerKind = .info

    // Activity log
    @State private var showLog = false
    @State private var logs: [LogEntry] = []
    @AppStorage("activityLogRetentionDays") private var activityLogRetentionDays = 30
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // General section
                SettingsSection(title: String(localized: "settings.general.title")) {
                    Toggle(isOn: $launchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings.general.launchAtLogin")
                            Text("settings.general.launchAtLogin.description")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
                }
                
                Divider()
                
                // Tracking section
                SettingsSection(title: String(localized: "settings.tracking.title")) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Polling interval
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings.tracking.pollingInterval")
                            
                            Picker("", selection: $pollingInterval) {
                                Text("30s").tag(30.0)
                                Text("60s").tag(60.0)
                                Text("2min").tag(120.0)
                                Text("5min").tag(300.0)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: pollingInterval) { newValue in
                                CommitPoller.shared.pollingInterval = newValue
                            }
                            
                            Text("settings.tracking.pollingInterval.description")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Session timeout
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings.tracking.sessionTimeout")
                            
                            Picker("", selection: $sessionTimeout) {
                                Text("5min").tag(5.0)
                                Text("15min").tag(15.0)
                                Text("30min").tag(30.0)
                                Text("1h").tag(60.0)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: sessionTimeout) { newValue in
                                ActivityTracker.shared.sessionTimeoutInterval = newValue * 60
                            }
                            
                            Text("settings.tracking.sessionTimeout.description")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Divider()
                
                // Privacy section
                SettingsSection(title: String(localized: "settings.privacy.title")) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Data retention
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings.privacy.dataRetention")
                            
                            Picker("", selection: $dataRetentionDays) {
                                Text("30 \(String(localized: "settings.privacy.days"))").tag(30)
                                Text("90 \(String(localized: "settings.privacy.days"))").tag(90)
                                Text("180 \(String(localized: "settings.privacy.days"))").tag(180)
                                Text("365 \(String(localized: "settings.privacy.days"))").tag(365)
                            }
                            .pickerStyle(.segmented)
                            
                            Text("settings.privacy.dataRetention.description")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Privacy info
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.title2)
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.privacy.localOnly")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("settings.privacy.localOnly.description")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Divider()
                
                // Accounts section
                SettingsSection(title: String(localized: "settings.accounts.title")) {
                    if let text = bannerText {
                        StatusBanner(text: text, kind: bannerKind)
                    }

                    // Unobtrusive log area (collapsed by default)
                    DisclosureGroup(isExpanded: $showLog) {
                        VStack(alignment: .leading, spacing: 8) {
                            if logs.isEmpty {
                                Text(String(localized: "settings.accounts.log.empty"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(6)
                            } else {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 6) {
                                        ForEach(logs) { entry in
                                            HStack(alignment: .top, spacing: 6) {
                                                Image(systemName: iconName(for: entry.kind))
                                                    .foregroundColor(iconColor(for: entry.kind))
                                                Text("\(entry.date.formatted(date: .omitted, time: .standard)) · \(entry.text)")
                                                    .font(.caption)
                                            }
                                        }
                                    }
                                    .padding(8)
                                }
                                .frame(maxHeight: 160)

                                HStack(spacing: 12) {
                                    Button(String(localized: "settings.accounts.log.clear")) {
                                        ActivityLogService.shared.clear()
                                        logs.removeAll()
                                        showBanner(String(localized: "status.logCleared"), kind: .info)
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    // Retention picker
                                    HStack(spacing: 6) {
                                        Text(String(localized: "settings.accounts.log.retention"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Picker("", selection: $activityLogRetentionDays) {
                                            Text(String(localized: "settings.retention.1d")).tag(1)
                                            Text(String(localized: "settings.retention.7d")).tag(7)
                                            Text(String(localized: "settings.retention.30d")).tag(30)
                                            Text(String(localized: "settings.retention.90d")).tag(90)
                                            Text(String(localized: "settings.retention.180d")).tag(180)
                                            Text(String(localized: "settings.retention.365d")).tag(365)
                                        }
                                        .onChange(of: activityLogRetentionDays) { newValue in
                                            ActivityLogService.shared.setRetentionDays(newValue)
                                            loadLogs()
                                        }
                                        .frame(width: 260)
                                    }
                                }
                            }
                        }
                        .transition(.opacity)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "note.text")
                                .foregroundColor(.secondary)
                            Text(String(localized: "settings.accounts.log.title"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 2)
                    // Environment picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "settings.accounts.environment.title")).font(.subheadline)
                        Picker("", selection: $environment) {
                            Text(String(localized: "settings.accounts.environment.dev")).tag(GitHubService.GitEnvironment.dev)
                            Text(String(localized: "settings.accounts.environment.prod")).tag(GitHubService.GitEnvironment.prod)
                        }
                        .pickerStyle(.segmented)
                        Text(String(localized: "settings.accounts.environment.note"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GitHub")
                            if isGitHubConnected {
                                Text((githubLogin != nil) ? String(format: String(localized: "settings.accounts.connectedAs"), githubLogin!) : String(localized: "settings.accounts.connected"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(String(localized: "settings.accounts.notConnected"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if isGitHubConnected {
                            Button(String(localized: "settings.accounts.disconnect")) {
                                try? GitHubService.shared.disconnect()
                                githubLogin = nil
                                isGitHubConnected = GitHubService.shared.isConnected
                                showBanner(String(localized: "status.disconnected"), kind: .success)
                            }
                            Button(String(localized: "settings.accounts.deleteToken")) {
                                showingDeleteTokenAlert = true
                            }
                            .foregroundColor(.red)
                            .alert(String(localized: "settings.accounts.deleteToken.confirm.title"), isPresented: $showingDeleteTokenAlert) {
                                Button(String(localized: "button.cancel"), role: .cancel) {}
                                Button(String(localized: "settings.accounts.deleteToken.confirm.delete"), role: .destructive) {
                                    try? GitHubService.shared.disconnect()
                                    githubLogin = nil
                                    isGitHubConnected = GitHubService.shared.isConnected
                                    showBanner(String(localized: "status.tokenDeleted"), kind: .success)
                                }
                            } message: {
                                Text(String(localized: "settings.accounts.deleteToken.confirm.message"))
                            }
                        } else {
                            HStack(spacing: 8) {
                                Button(String(localized: "settings.accounts.connect")) {
                                    Task { await startGitHubDeviceFlow() }
                                }
                                Button(String(localized: "settings.accounts.configure")) {
                                    clientIdInput = UserDefaults.standard.string(forKey: "GitHubClientID.\(environment.rawValue)") ?? ""
                                    showingGitHubSetup = true
                                }
                                .help(String(localized: "settings.accounts.configure.help"))
                            }
                        }
                    }
                }
.onChange(of: environment) { env in
                    GitHubService.shared.setEnvironment(env)
                    // Update connection state for selected environment
                    isGitHubConnected = GitHubService.shared.isConnected
                    githubLogin = nil
                }

                // Delete all tokens (advanced)
                HStack {
                    Button(String(localized: "settings.accounts.deleteAllTokens")) {
                        showingDeleteAllTokensAlert = true
                    }
                    .foregroundColor(.red)
                    .alert(String(localized: "settings.accounts.deleteAllTokens.confirm.title"), isPresented: $showingDeleteAllTokensAlert) {
                        Button(String(localized: "button.cancel"), role: .cancel) {}
                        Button(String(localized: "settings.accounts.deleteAllTokens.confirm.delete"), role: .destructive) {
                            GitHubService.shared.disconnectAll()
                            githubLogin = nil
                            isGitHubConnected = GitHubService.shared.isConnected
                            showBanner(String(localized: "status.allTokensDeleted"), kind: .success)
                        }
                    } message: {
                        Text(String(localized: "settings.accounts.deleteAllTokens.confirm.message"))
                    }
                    Spacer()
                }

                if let err = authErrorMessage {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Divider()
                
                // About section
                SettingsSection(title: String(localized: "settings.about.title")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.largeTitle)
                                .foregroundColor(.accentColor)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DevDiary")
                                    .font(.headline)
                                Text("Version \(appVersion)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("settings.about.description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            Button("settings.about.github") {
                                // Would open GitHub page
                            }
                            .buttonStyle(.link)
                            
                            Button("settings.about.license") {
                                // Would show license
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            loadLogs()
        }
        .sheet(isPresented: $showingGitHubSetup) {
            GitHubSetupSheet(clientIdInput: $clientIdInput, onSave: {
                GitHubService.shared.setEnvironment(environment)
                GitHubService.shared.saveClientId(clientIdInput)
                showingGitHubSetup = false
                showBanner(String(localized: "status.clientIdSaved"), kind: .success)
            }, onOpenGitHub: {
                if let url = URL(string: "https://github.com/settings/developers") { NSWorkspace.shared.open(url) }
            }, onOpenDocs: {
                if let url = URL(string: "https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow") { NSWorkspace.shared.open(url) }
            })
            .frame(width: 520, height: 360)
        }
        .sheet(isPresented: $showingGitHubAuth, onDismiss: {
            pollingTask?.cancel()
            pollingTask = nil
        }) {
            if let deviceCode {
                GitHubDeviceAuthSheet(device: deviceCode, onOpen: {
                    let url = deviceCode.verification_uri_complete ?? deviceCode.verification_uri
                    GitHubService.shared.openInBrowser(url)
                }, onCancel: {
                    showingGitHubAuth = false
                })
                .frame(width: 420, height: 240)
            } else {
                ProgressView()
                    .frame(width: 320, height: 160)
            }
        }
    }
    
    private func startGitHubDeviceFlow() async {
        FileLogger.shared.log("startGitHubDeviceFlow called")
        authErrorMessage = nil
        // Ensure client id is configured
        guard GitHubService.shared.clientId != nil else {
            FileLogger.shared.log("No client ID - showing setup sheet")
            showingGitHubSetup = true
            return
        }
        do {
            FileLogger.shared.log("Calling beginDeviceFlow...")
            let device = try await GitHubService.shared.beginDeviceFlow()
            FileLogger.shared.log("Got device code: \(device.user_code)")
            self.deviceCode = device
            FileLogger.shared.log("Setting showingGitHubAuth = true")
            showingGitHubAuth = true

            // Do NOT auto-open browser – let user see the code first and click "Open in Browser"

            // Start polling
            FileLogger.shared.log("Starting polling task")
            pollingTask = Task { [device] in
                do {
                    FileLogger.shared.log("Polling for token...")
                    try await GitHubService.shared.pollForToken(deviceCode: device.device_code, interval: device.interval)
                    FileLogger.shared.log("Token received!")
                    // Small delay to ensure GitHub has the token ready for API calls
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if let login = try? await GitHubService.shared.fetchCurrentUserLogin() {
                        FileLogger.shared.log("Fetched login: \(login)")
                        await MainActor.run { self.githubLogin = login }
                    }
                    await MainActor.run {
                        FileLogger.shared.log("Auth complete, updating UI")
                        self.isGitHubConnected = true
                        self.showingGitHubAuth = false
                        let msg = self.githubLogin != nil ? String(format: String(localized: "status.connectedAs"), self.githubLogin!) : String(localized: "status.connected")
                        self.showBanner(msg, kind: .success)
                    }
                } catch is CancellationError {
                    FileLogger.shared.log("Polling cancelled")
                } catch {
                    FileLogger.shared.log("Polling error: \(error)")
                    await MainActor.run {
                        self.authErrorMessage = error.localizedDescription
                        self.showingGitHubAuth = false
                        self.showBanner(String(localized: "status.error.authFailed"), kind: .error)
                    }
                }
            }
        } catch {
            FileLogger.shared.log("beginDeviceFlow threw: \(error)")
            authErrorMessage = error.localizedDescription
            showBanner(error.localizedDescription, kind: .error)
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let short, let build, !build.isEmpty {
            return "\(short) (\(build))"
        }
        return short ?? "1.0"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // Note: This requires the app to be properly signed and in /Applications
        // For development, this is a no-op
        #if !DEBUG
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Handle error silently for now
        }
        #endif
    }
}

// MARK: - Status Banner
private enum BannerKind { case success, error, info }

private struct StatusBanner: View {
    let text: String
    let kind: BannerKind

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
            Text(text).font(.caption).fontWeight(.medium)
            Spacer()
        }
        .padding(8)
        .background(background)
        .cornerRadius(6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var background: Color {
        switch kind {
        case .success: return Color.green.opacity(0.15)
        case .error: return Color.red.opacity(0.15)
        case .info: return Color.blue.opacity(0.12)
        }
    }
    private var iconName: String {
        switch kind {
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        case .info: return "info.circle"
        }
    }
}

private extension SettingsView {
    struct LogEntry: Identifiable { let id = UUID(); let date: Date; let kind: BannerKind; let text: String }

    func iconName(for kind: BannerKind) -> String {
        switch kind { case .success: return "checkmark.circle"; case .error: return "exclamationmark.triangle"; case .info: return "info.circle" }
    }
    func iconColor(for kind: BannerKind) -> Color {
        switch kind { case .success: return .green; case .error: return .red; case .info: return .blue }
    }

    func loadLogs() {
        let entries = ActivityLogService.shared.load().map { e in
            LogEntry(date: e.date, kind: toBannerKind(e.kind), text: e.text)
        }
        logs = entries
    }

    func toBannerKind(_ kind: ActivityLogService.Kind) -> BannerKind {
        switch kind { case .success: return .success; case .error: return .error; case .info: return .info }
    }

    func appendLog(_ text: String, kind: BannerKind) {
        let serviceKind: ActivityLogService.Kind = (kind == .success ? .success : (kind == .error ? .error : .info))
        let entries = ActivityLogService.shared.append(kind: serviceKind, text: text)
        logs = entries.map { LogEntry(date: $0.date, kind: toBannerKind($0.kind), text: $0.text) }
    }

    func showBanner(_ text: String, kind: BannerKind) {
        appendLog(text, kind: kind)
        withAnimation { self.bannerText = text; self.bannerKind = kind }
        // Auto-hide after 3 seconds
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { self.bannerText = nil }
        }
    }
}

// MARK: - GitHub Device Auth Sheet
private struct GitHubDeviceAuthSheet: View {
    let device: GitHubService.DeviceCode
    let onOpen: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "github.auth.title"))
                .font(.headline)
            Text(String(localized: "github.auth.instructions"))
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text(device.user_code)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
                Spacer()
                Button(String(localized: "github.auth.openInBrowser")) {
                    onOpen()
                }
                .keyboardShortcut(.defaultAction)
            }
            Spacer()
            HStack {
                Spacer()
                Button(String(localized: "button.cancel")) {
                    onCancel()
                }
            }
        }
        .padding()
    }
}

// MARK: - GitHub Setup Sheet
private struct GitHubSetupSheet: View {
    @Binding var clientIdInput: String
    let onSave: () -> Void
    let onOpenGitHub: () -> Void
    let onOpenDocs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "github.setup.title")).font(.headline)
            Text(String(localized: "github.setup.description")).font(.caption).foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "github.setup.step1"), systemImage: "1.circle")
                Label(String(localized: "github.setup.step2"), systemImage: "2.circle")
                Label(String(localized: "github.setup.step3"), systemImage: "3.circle")
            }
            .labelStyle(.titleAndIcon)

            HStack(spacing: 8) {
                TextField(String(localized: "github.setup.clientId.placeholder"), text: $clientIdInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                Button(String(localized: "github.setup.save")) { onSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 12) {
                Button(String(localized: "github.setup.openGitHub")) { onOpenGitHub() }
                Button(String(localized: "github.setup.openDocs")) { onOpenDocs() }
                Spacer()
                Text(String(localized: "github.setup.envvar.hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Supporting Views

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            content
        }
    }
}
