import SwiftUI
import AppKit

/// Multi-step modal flow to add a GitLab instance:
/// 1. Enter base URL, probe reachability
/// 2. Show PAT setup hint + enter PAT, verify
/// 3. Connect (persist account + token)
struct AddGitLabInstanceSheet: View {
    enum Step {
        case instanceURL
        case enterToken
        case verifying
        case verified
    }

    @State private var step: Step = .instanceURL
    @State private var instanceURLText: String = "https://gitlab.com"
    @State private var patText: String = ""
    @State private var errorMessage: String?
    @State private var baseURL: URL?
    @State private var username: String?
    @State private var displayName: String?
    @State private var isBusy: Bool = false

    var onCancel: () -> Void
    var onConnected: (ForgeAccount) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(stepTitle)
                .font(.headline)
            if let sub = stepSubtitle {
                Text(sub).font(.caption).foregroundColor(.secondary)
            }

            switch step {
            case .instanceURL: instanceURLStep
            case .enterToken, .verifying: tokenStep
            case .verified: verifiedStep
            }

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()
            HStack {
                Button(String(localized: "button.cancel")) { onCancel() }
                Spacer()
                primaryButton
            }
        }
        .padding(20)
        .frame(width: 520, height: 340)
    }

    // MARK: - Step views

    private var instanceURLStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "gitlab.add.url.label")).font(.subheadline)
            TextField("https://gitlab.example.com", text: $instanceURLText)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { Task { await probeInstance() } }
            Text(String(localized: "gitlab.add.url.hint"))
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var tokenStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let baseURL {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(baseURL.absoluteString).font(.caption).foregroundColor(.secondary)
                }
            }
            Text(String(localized: "gitlab.add.pat.label")).font(.subheadline)
            SecureField("glpat-XXXXXXXX", text: $patText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await verifyToken() } }

            HStack(spacing: 8) {
                Button(String(localized: "gitlab.add.pat.openSettings")) { openTokenSettings() }
                    .buttonStyle(.link)
                Spacer()
                Text(String(localized: "gitlab.add.pat.scopes"))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var verifiedStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text(String(format: String(localized: "gitlab.add.verified"), username ?? ""))
                    .font(.subheadline).fontWeight(.medium)
            }
            if let displayName, displayName != username {
                Text(displayName).font(.caption).foregroundColor(.secondary)
            }
            if let baseURL {
                Text(baseURL.absoluteString).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Dynamic labels

    private var stepTitle: String {
        switch step {
        case .instanceURL: return String(localized: "gitlab.add.title.url")
        case .enterToken, .verifying: return String(localized: "gitlab.add.title.token")
        case .verified: return String(localized: "gitlab.add.title.ready")
        }
    }

    private var stepSubtitle: String? {
        switch step {
        case .instanceURL: return String(localized: "gitlab.add.subtitle.url")
        case .enterToken, .verifying: return String(localized: "gitlab.add.subtitle.token")
        case .verified: return String(localized: "gitlab.add.subtitle.ready")
        }
    }

    // MARK: - Primary button

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .instanceURL:
            Button {
                Task { await probeInstance() }
            } label: {
                HStack {
                    if isBusy { ProgressView().scaleEffect(0.6) }
                    Text(String(localized: "gitlab.add.button.continue"))
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isBusy || instanceURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        case .enterToken, .verifying:
            Button {
                Task { await verifyToken() }
            } label: {
                HStack {
                    if step == .verifying { ProgressView().scaleEffect(0.6) }
                    Text(String(localized: "gitlab.add.button.verify"))
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(step == .verifying || patText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        case .verified:
            Button(String(localized: "gitlab.add.button.connect")) {
                persistAndFinish()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func openTokenSettings() {
        guard let baseURL else { return }
        let url = baseURL.appendingPathComponent("-/user_settings/personal_access_tokens")
        NSWorkspace.shared.open(url)
    }

    private func probeInstance() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        let trimmed = instanceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http" else {
            errorMessage = String(localized: "gitlab.add.error.invalidURL")
            return
        }
        do {
            try await GitLabService.probeInstance(at: url)
            baseURL = url
            step = .enterToken
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyToken() async {
        errorMessage = nil
        guard let baseURL else { return }
        let token = patText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        step = .verifying
        do {
            let (username, displayName) = try await GitLabService.verify(baseURL: baseURL, token: token)
            self.username = username
            self.displayName = displayName
            step = .verified
        } catch {
            errorMessage = error.localizedDescription
            step = .enterToken
        }
    }

    private func persistAndFinish() {
        guard let baseURL, let username else { return }
        let host = baseURL.host ?? baseURL.absoluteString
        let account = ForgeRegistry.shared.addGitLabAccount(
            baseURL: baseURL,
            displayName: host,
            username: username
        )
        do {
            let provider = GitLabService(account: account)
            try provider.storeToken(patText)
            onConnected(account)
        } catch {
            errorMessage = error.localizedDescription
            // Rollback: remove the account we just created
            ForgeRegistry.shared.removeAccount(id: account.id)
        }
    }
}
