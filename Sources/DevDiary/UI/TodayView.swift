import SwiftUI
import AppKit

/// Today's activity view showing sessions, commits and statistics
struct TodayView: View {
    @State private var statistics: StatisticsService.DayStatistics?
    @State private var commits: [Commit] = []
    @State private var sessions: [Session] = []
    @State private var projects: [UUID: Project] = [:]
    @State private var sessionToProject: [UUID: Project] = [:] // sessionId -> Project
    @State private var isLoading = true
    
    var body: some View {
        HSplitView {
            // Left: Statistics and Sessions
            VStack(alignment: .leading, spacing: 0) {
                // Statistics header
                statisticsHeader
                    .padding()
                
                Divider()
                
                // Sessions list
                sessionsList
            }
            .frame(minWidth: 280, maxWidth: 350)
            
            // Right: Commits timeline
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("today.commits.title")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("\(commits.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                Divider()
                
                commitsList
            }
        }
        .onAppear {
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newCommitsDetected)) { _ in
            loadData()
        }
    }
    
    // MARK: - Statistics Header
    
    private var statisticsHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("today.statistics.title")
                .font(.headline)
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let stats = statistics {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    StatCard(
                        title: String(localized: "today.stat.workTime"),
                        value: stats.formattedDuration,
                        icon: "clock",
                        color: .blue
                    )
                    
                    StatCard(
                        title: String(localized: "today.stat.commits"),
                        value: "\(stats.commitCount)",
                        icon: "arrow.triangle.branch",
                        color: .green
                    )
                    
                    StatCard(
                        title: String(localized: "today.stat.additions"),
                        value: "+\(stats.additions)",
                        icon: "plus.circle",
                        color: .green
                    )
                    
                    StatCard(
                        title: String(localized: "today.stat.deletions"),
                        value: "-\(stats.deletions)",
                        icon: "minus.circle",
                        color: .red
                    )
                }
            } else {
                emptyState
            }
        }
    }
    
    // MARK: - Sessions List
    
    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("today.sessions.title")
                    .font(.headline)
                
                Spacer()
                
                Text("\(sessions.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            if sessions.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "moon.zzz")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("today.sessions.empty")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(sessions, id: \.id) { session in
                    SessionRow(session: session, project: projects[session.projectId])
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Commits List
    
    private var commitsList: some View {
        Group {
            if commits.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("today.commits.empty")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(commits, id: \.id) { commit in
                    CommitRow(commit: commit, project: sessionToProject[commit.sessionId])
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                Text("today.empty")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("today.empty.hint")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    // MARK: - Data Loading
    
    private func loadData() {
        do {
            statistics = try StatisticsService.shared.getTodayStatistics()
            commits = try DatabaseManager.shared.getCommitsForDate(Date())
                .sorted { $0.timestamp > $1.timestamp }
            sessions = try DatabaseManager.shared.getSessionsForDate(Date())
                .sorted { $0.startTime > $1.startTime }
            
            // Load projects for sessions
            let allProjects = try DatabaseManager.shared.getAllProjects()
            projects = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.id, $0) })
            
            // Build sessionId -> Project mapping for commits
            for session in sessions {
                if let project = projects[session.projectId] {
                    sessionToProject[session.id] = project
                }
            }
            
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}

// MARK: - Supporting Views

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(title)
    }
}

private struct SessionRow: View {
    let session: Session
    let project: Project?
    
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            // Active indicator with pulse animation
            Circle()
                .fill(session.isActive ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
                .overlay {
                    if session.isActive {
                        Circle()
                            .stroke(Color.green.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0)
                            .animation(
                                .easeOut(duration: 1.0)
                                .repeatForever(autoreverses: false),
                                value: session.isActive
                            )
                    }
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(project?.name ?? String(localized: "session.unknownProject"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text(session.startTime, style: .time)
                    if let endTime = session.endTime {
                        Text("-")
                        Text(endTime, style: .time)
                    } else {
                        Text("- " + String(localized: "session.now"))
                            .foregroundColor(.green)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(session.formattedDuration)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct CommitRow: View {
    let commit: Commit
    let project: Project?
    @State private var isExpanded = false
    @State private var isHovered = false
    
    private var gitHubURL: URL? {
        guard let project = project else { return nil }
        return GitService.shared.getGitHubCommitURL(hash: commit.hash, at: project.path)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.shortMessage)
                        .font(.subheadline)
                        .lineLimit(isExpanded ? nil : 1)
                    
                    HStack(spacing: 8) {
                        Text(commit.shortHash)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(.secondary)
                        
                        Text(commit.timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Stats
                HStack(spacing: 8) {
                    if commit.additions > 0 {
                        Text("+\(commit.additions)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    if commit.deletions > 0 {
                        Text("-\(commit.deletions)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    // GitHub link button (only visible on hover if available)
                    if let url = gitHubURL {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered ? 1.0 : 0.0)
                        .help(String(localized: "commit.openOnGitHub"))
                    }
                }
            }
            
            // Full message if expanded and different from short
            if isExpanded && commit.message != commit.shortMessage {
                Text(commit.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}
