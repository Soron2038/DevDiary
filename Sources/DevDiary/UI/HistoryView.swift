import SwiftUI
import AppKit

/// History view with date navigation and daily statistics
struct HistoryView: View {
    @State private var selectedDate = Date()
    @State private var statistics: [StatisticsService.DayStatistics] = []
    @State private var selectedDayStats: StatisticsService.DayStatistics?
    @State private var dayCommits: [Commit] = []
    @State private var daySessions: [Session] = []
    @State private var projects: [UUID: Project] = [:]
    @State private var sessionToProject: [UUID: Project] = [:]
    @State private var isLoading = true
    
    private let calendar = Calendar.current
    
    var body: some View {
        HSplitView {
            // Left: Date list
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("history.title")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Navigation buttons
                    HStack(spacing: 4) {
                        Button(action: goToPreviousWeek) {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: goToToday) {
                            Text("history.today")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: goToNextWeek) {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.plain)
                        .disabled(calendar.isDateInToday(selectedDate))
                    }
                }
                .padding()
                
                Divider()
                
                // Days list
                List(statistics, id: \.date) { dayStats in
                    DayRow(
                        stats: dayStats,
                        isSelected: calendar.isDate(dayStats.date, inSameDayAs: selectedDate)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectDate(dayStats.date)
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 250, maxWidth: 320)
            
            // Right: Selected day details
            VStack(alignment: .leading, spacing: 0) {
                if let stats = selectedDayStats {
                    // Date header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stats.date, format: .dateTime.weekday(.wide))
                                .font(.headline)
                            Text(stats.date, format: .dateTime.day().month().year())
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Quick stats
                        HStack(spacing: 16) {
                            Label(stats.formattedDuration, systemImage: "clock")
                            Label("\(stats.commitCount)", systemImage: "arrow.triangle.branch")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    
                    Divider()
                    
                    // Commits for selected day
                    if dayCommits.isEmpty {
                        VStack {
                            Spacer()
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("history.noActivity")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        List(dayCommits, id: \.id) { commit in
                            HistoryCommitRow(commit: commit, project: sessionToProject[commit.sessionId])
                        }
                        .listStyle(.plain)
                    }
                } else {
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            loadHistory()
        }
    }
    
    // MARK: - Navigation
    
    private func goToPreviousWeek() {
        if let newDate = calendar.date(byAdding: .day, value: -7, to: selectedDate) {
            selectedDate = newDate
            loadHistory()
        }
    }
    
    private func goToNextWeek() {
        if let newDate = calendar.date(byAdding: .day, value: 7, to: selectedDate),
           newDate <= Date() {
            selectedDate = newDate
            loadHistory()
        }
    }
    
    private func goToToday() {
        selectedDate = Date()
        loadHistory()
    }
    
    private func selectDate(_ date: Date) {
        selectedDate = date
        loadSelectedDayData()
    }
    
    // MARK: - Data Loading
    
    private func loadHistory() {
        isLoading = true
        
        do {
            // Load last 14 days
            statistics = try StatisticsService.shared.getStatisticsForLastDays(14)
            loadSelectedDayData()
            isLoading = false
        } catch {
            isLoading = false
        }
    }
    
    private func loadSelectedDayData() {
        do {
            selectedDayStats = try StatisticsService.shared.getStatisticsForDate(selectedDate)
            dayCommits = try DatabaseManager.shared.getCommitsForDate(selectedDate)
                .sorted { $0.timestamp > $1.timestamp }
            daySessions = try DatabaseManager.shared.getSessionsForDate(selectedDate)
            
            // Load projects
            let allProjects = try DatabaseManager.shared.getAllProjects()
            projects = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.id, $0) })
            
            // Build sessionId -> Project mapping
            sessionToProject = [:]
            for session in daySessions {
                if let project = projects[session.projectId] {
                    sessionToProject[session.id] = project
                }
            }
        } catch {
            selectedDayStats = nil
            dayCommits = []
            daySessions = []
        }
    }
}

// MARK: - Supporting Views

private struct DayRow: View {
    let stats: StatisticsService.DayStatistics
    let isSelected: Bool
    
    private let calendar = Calendar.current
    
    var body: some View {
        HStack {
            // Day indicator
            VStack(spacing: 2) {
                Text(stats.date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(stats.date, format: .dateTime.day())
                    .font(.title3)
                    .fontWeight(isSelected ? .bold : .regular)
            }
            .frame(width: 40)
            
            // Activity indicator
            if stats.commitCount > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.formattedDuration)
                        .font(.subheadline)
                    Text("\(stats.commitCount) commits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Activity bar
                activityBar
            } else {
                Spacer()
                Text("history.noActivity")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
    
    private var activityBar: some View {
        // Simple bar showing relative activity
        let maxCommits = 20.0
        let width = min(CGFloat(stats.commitCount) / maxCommits * 50, 50)
        
        return RoundedRectangle(cornerRadius: 2)
            .fill(Color.accentColor.opacity(0.6))
            .frame(width: max(width, 4), height: 8)
    }
}

private struct HistoryCommitRow: View {
    let commit: Commit
    let project: Project?
    
    @State private var isHovered = false
    
    private var gitHubURL: URL? {
        guard let project = project else { return nil }
        return GitService.shared.getGitHubCommitURL(hash: commit.hash, at: project.path)
    }
    
    var body: some View {
        HStack(alignment: .top) {
            // Time
            Text(commit.timestamp, format: .dateTime.hour().minute())
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            
            // Commit info
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.shortMessage)
                    .font(.subheadline)
                
                HStack(spacing: 8) {
                    Text(commit.shortHash)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(.secondary)
                    
                    if commit.additions > 0 || commit.deletions > 0 {
                        Text("+\(commit.additions)/-\(commit.deletions)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // GitHub link button (visible on hover)
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
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
