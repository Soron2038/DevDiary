import SwiftUI

/// Today's activity view showing sessions, commits and statistics
struct TodayView: View {
    @State private var statistics: StatisticsService.DayStatistics?
    @State private var commits: [Commit] = []
    @State private var sessions: [Session] = []
    @State private var projects: [UUID: Project] = [:]
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
                    CommitRow(commit: commit)
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cup.and.saucer")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("today.empty")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
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
    }
}

private struct SessionRow: View {
    let session: Session
    let project: Project?
    
    var body: some View {
        HStack {
            // Active indicator
            Circle()
                .fill(session.isActive ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(project?.name ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text(session.startTime, style: .time)
                    if let endTime = session.endTime {
                        Text("-")
                        Text(endTime, style: .time)
                    } else {
                        Text("- now")
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
        }
        .padding(.vertical, 4)
    }
}

private struct CommitRow: View {
    let commit: Commit
    @State private var isExpanded = false
    
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
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}
