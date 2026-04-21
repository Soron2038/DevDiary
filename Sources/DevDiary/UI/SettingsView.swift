import SwiftUI
import ServiceManagement
import AppKit

/// Settings view with app configuration. Account management lives in a separate
/// modal (`AccountsSheet`) to keep this view uncluttered.
struct SettingsView: View {
    // General settings
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    // Tracking settings
    @AppStorage("pollingInterval") private var pollingInterval = 60.0
    @AppStorage("sessionTimeout") private var sessionTimeout = 15.0

    // Privacy settings
    @AppStorage("dataRetentionDays") private var dataRetentionDays = 90

    // Accounts
    @State private var showingAccountsSheet = false
    @State private var connectedCount = 0
    @State private var totalAccounts = 0

    // Activity log
    @State private var showLog = false
    @State private var logs: [LogEntry] = []
    @AppStorage("activityLogRetentionDays") private var activityLogRetentionDays = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(title: String(localized: "settings.general.title")) {
                    Toggle(isOn: $launchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings.general.launchAtLogin")
                            Text("settings.general.launchAtLogin.description")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
                }

                Divider()

                SettingsSection(title: String(localized: "settings.tracking.title")) {
                    VStack(alignment: .leading, spacing: 12) {
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
                                .font(.caption).foregroundColor(.secondary)
                        }

                        Divider()

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
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                SettingsSection(title: String(localized: "settings.privacy.title")) {
                    VStack(alignment: .leading, spacing: 12) {
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
                                .font(.caption).foregroundColor(.secondary)
                        }

                        Divider()

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.title2)
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.privacy.localOnly")
                                    .font(.subheadline).fontWeight(.medium)
                                Text("settings.privacy.localOnly.description")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                Divider()

                SettingsSection(title: String(localized: "settings.accounts.title")) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.2.circle")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "settings.accounts.summary.title"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(accountsSummary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(String(localized: "settings.accounts.manage")) {
                            showingAccountsSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    DisclosureGroup(isExpanded: $showLog) {
                        activityLogSection
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "note.text").foregroundColor(.secondary)
                            Text(String(localized: "settings.accounts.log.title"))
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }

                Divider()

                SettingsSection(title: String(localized: "settings.about.title")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.largeTitle).foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DevDiary").font(.headline)
                                Text("Version \(appVersion)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Text("settings.about.description").font(.caption).foregroundColor(.secondary)
                        HStack(spacing: 16) {
                            Button("settings.about.github") {
                                if let url = URL(string: "https://github.com/Soron2038/DevDiary") {
                                    NSWorkspace.shared.open(url)
                                }
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
            refreshAccounts()
            loadLogs()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccounts()
            loadLogs()
        }
        .sheet(isPresented: $showingAccountsSheet, onDismiss: {
            refreshAccounts()
            loadLogs()
        }) {
            AccountsSheet()
        }
    }

    // MARK: - Subsections

    private var activityLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if logs.isEmpty {
                Text(String(localized: "settings.accounts.log.empty"))
                    .font(.caption).foregroundColor(.secondary)
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
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: 6) {
                        Text(String(localized: "settings.accounts.log.retention"))
                            .font(.caption).foregroundColor(.secondary)
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
                        .frame(width: 200)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var accountsSummary: String {
        if connectedCount == 0 {
            return String(localized: "settings.accounts.summary.none")
        }
        return String(format: String(localized: "settings.accounts.summary.status"), connectedCount, totalAccounts)
    }

    private func refreshAccounts() {
        let accounts = ForgeRegistry.shared.accounts()
        totalAccounts = accounts.count
        connectedCount = accounts.filter {
            ForgeRegistry.shared.provider(for: $0).isConnected
        }.count
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

    // MARK: - Log

    private struct LogEntry: Identifiable {
        let id = UUID()
        let date: Date
        let kind: ActivityLogService.Kind
        let text: String
    }

    private func iconName(for kind: ActivityLogService.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        case .info: return "info.circle"
        }
    }

    private func iconColor(for kind: ActivityLogService.Kind) -> Color {
        switch kind {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }

    private func loadLogs() {
        logs = ActivityLogService.shared.load().map { e in
            LogEntry(date: e.date, kind: e.kind, text: e.text)
        }
    }
}

// MARK: - Shared Section View

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
    }
}
