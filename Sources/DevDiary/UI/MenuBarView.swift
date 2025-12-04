import SwiftUI
import Combine

/// Quick view shown in the menubar popover
struct MenuBarView: View {
    @State private var summary: StatisticsService.QuickSummary?
    @State private var isLoading = true
    @State private var sessionDuration: TimeInterval = 0
    
    /// Timer for live session duration updates
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header
            
            Divider()
            
            if isLoading {
                loadingView
            } else {
                // Today's summary
                todaySummary
                    .padding()
                
                Divider()
                
                // Active session info
                if ActivityTracker.shared.hasActiveSession {
                    activeSessionSection
                        .padding()
                    
                    Divider()
                }
                
                // Latest commit
                latestCommitSection
                    .padding()
            }
            
            Spacer()
            
            Divider()
            
            // Footer buttons
            footerButtons
        }
        .frame(width: 320, height: 420)
        .onAppear {
            loadData()
        }
        .onReceive(timer) { _ in
            updateSessionDuration()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newCommitsDetected)) { _ in
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionStarted)) { _ in
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionEnded)) { _ in
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .activeProjectChanged)) { _ in
            loadData()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text("DevDiary")
                .font(.headline)
            
            Spacer()
            
            // Refresh button
            Button(action: loadData) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help(String(localized: "menubar.button.refresh"))
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("menubar.loading")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    // MARK: - Today Summary
    
    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("menubar.todaySummary")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                // Time
                StatView(
                    icon: "clock",
                    value: summary?.formattedDuration ?? "0m",
                    label: String(localized: "menubar.stat.time")
                )
                
                // Commits
                StatView(
                    icon: "arrow.triangle.branch",
                    value: "\(summary?.todayCommits ?? 0)",
                    label: String(localized: "menubar.stat.commits")
                )
            }
            
            // Active project
            if let project = summary?.activeProject {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                    Text(project.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
    }
    
    // MARK: - Active Session
    
    private var activeSessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("menubar.activeSession")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.green)
                Text(formatDuration(sessionDuration))
                    .font(.title3)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
    }
    
    // MARK: - Latest Commit
    
    private var latestCommitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("menubar.lastCommit")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let commit = summary?.latestCommit {
                VStack(alignment: .leading, spacing: 4) {
                    Text(commit.shortMessage)
                        .font(.body)
                        .lineLimit(2)
                    
                    HStack {
                        Text(commit.shortHash)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(commit.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "tray")
                        .foregroundColor(.secondary)
                    Text("menubar.noCommits")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Footer
    
    private var footerButtons: some View {
        HStack {
            Button(action: openDashboard) {
                Label("menubar.button.dashboard", systemImage: "rectangle.3.group")
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button(action: openSettings) {
                Label("menubar.button.settings", systemImage: "gear")
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button(action: quitApp) {
                Label("menubar.button.quit", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func loadData() {
        do {
            summary = try StatisticsService.shared.getQuickSummary()
            updateSessionDuration()
            isLoading = false
            
            // Update status item badge
            StatusItemManager.shared.updateBadge(count: summary?.todayCommits ?? 0)
        } catch {
            isLoading = false
        }
    }
    
    private func updateSessionDuration() {
        sessionDuration = ActivityTracker.shared.currentSessionDuration
    }
    
    private func openDashboard() {
        StatusItemManager.shared.closePopover()
        DashboardWindow.shared.show()
    }
    
    private func openSettings() {
        StatusItemManager.shared.closePopover()
        DashboardWindow.shared.show()
        // Settings tab will be selected via the dashboard
    }
    
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Supporting Views

private struct StatView: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
