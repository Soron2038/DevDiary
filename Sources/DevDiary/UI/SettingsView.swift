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

    // Setup sheet
    @State private var showingGitHubSetup = false
    @State private var clientIdInput: String = UserDefaults.standard.string(forKey: "GitHubClientID") ?? ""
    
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
                                isGitHubConnected = false
                            }
                        } else {
                            HStack(spacing: 8) {
                                Button(String(localized: "settings.accounts.connect")) {
                                    Task { await startGitHubDeviceFlow() }
                                }
                                Button(String(localized: "settings.accounts.configure")) {
                                    showingGitHubSetup = true
                                }
                                .help(String(localized: "settings.accounts.configure.help"))
                            }
                        }
                    }
                }
.sheet(isPresented: $showingGitHubSetup) {
                    GitHubSetupSheet(clientIdInput: $clientIdInput, onSave: {
                        GitHubService.shared.saveClientId(clientIdInput)
                        showingGitHubSetup = false
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
    }
    
    private func startGitHubDeviceFlow() async {
        authErrorMessage = nil
        // Ensure client id is configured
        guard GitHubService.shared.clientId != nil else {
            showingGitHubSetup = true
            return
        }
        do {
            let device = try await GitHubService.shared.beginDeviceFlow()
            self.deviceCode = device
            showingGitHubAuth = true

            // Open browser immediately for best UX
            let url = device.verification_uri_complete ?? device.verification_uri
            GitHubService.shared.openInBrowser(url)

            // Start polling
            pollingTask = Task { [device] in
                do {
                    try await GitHubService.shared.pollForToken(deviceCode: device.device_code, interval: device.interval)
                    // Small delay to ensure GitHub has the token ready for API calls
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if let login = try? await GitHubService.shared.fetchCurrentUserLogin() {
                        await MainActor.run { self.githubLogin = login }
                    }
                    await MainActor.run {
                        self.isGitHubConnected = true
                        self.showingGitHubAuth = false
                    }
                } catch is CancellationError {
                    // ignored
                } catch {
                    await MainActor.run {
                        self.authErrorMessage = error.localizedDescription
                        self.showingGitHubAuth = false
                    }
                }
            }
        } catch {
            authErrorMessage = error.localizedDescription
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
