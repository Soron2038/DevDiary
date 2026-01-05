import Foundation

/// Aggregates and calculates statistics from tracked data
final class StatisticsService {
    static let shared = StatisticsService()
    
    private init() {}
    
    // MARK: - Data Structures
    
    /// Statistics for a single day
    struct DayStatistics {
        let date: Date
        var totalDuration: TimeInterval = 0
        var commitCount: Int = 0
        var sessionCount: Int = 0
        var additions: Int = 0
        var deletions: Int = 0
        var filesChanged: Int = 0
        var activeProjects: [Project] = []
        
        var formattedDuration: String {
            formatDuration(totalDuration)
        }
    }
    
    /// Statistics for a week
    struct WeekStatistics {
        let startDate: Date
        let endDate: Date
        var days: [DayStatistics] = []
        
        var totalDuration: TimeInterval {
            days.reduce(0) { $0 + $1.totalDuration }
        }
        
        var totalCommits: Int {
            days.reduce(0) { $0 + $1.commitCount }
        }
        
        var totalSessions: Int {
            days.reduce(0) { $0 + $1.sessionCount }
        }
        
        var averageDailyDuration: TimeInterval {
            guard !days.isEmpty else { return 0 }
            return totalDuration / Double(days.count)
        }
        
        var mostProductiveDay: DayStatistics? {
            days.max(by: { $0.totalDuration < $1.totalDuration })
        }
        
        var formattedTotalDuration: String {
            formatDuration(totalDuration)
        }
    }
    
    /// Statistics for a project
    struct ProjectStatistics {
        let project: Project
        var totalDuration: TimeInterval = 0
        var commitCount: Int = 0
        var sessionCount: Int = 0
        var additions: Int = 0
        var deletions: Int = 0
        var lastActivity: Date?
        
        var formattedDuration: String {
            formatDuration(totalDuration)
        }
    }
    
    // MARK: - Today Statistics
    
    /// Get statistics for today
    func getTodayStatistics() throws -> DayStatistics {
        return try getStatisticsForDate(Date())
    }
    
    /// Get statistics for a specific date
    func getStatisticsForDate(_ date: Date) throws -> DayStatistics {
        var stats = DayStatistics(date: date)
        
        // Get sessions for the day
        let sessions = try DatabaseManager.shared.getSessionsForDate(date)
        stats.sessionCount = sessions.count
        stats.totalDuration = sessions.reduce(0) { $0 + $1.duration }
        
        // Get commits for the day
        let commits = try DatabaseManager.shared.getCommitsForDate(date)
        stats.commitCount = commits.count
        stats.additions = commits.reduce(0) { $0 + $1.additions }
        stats.deletions = commits.reduce(0) { $0 + $1.deletions }
        stats.filesChanged = commits.reduce(0) { $0 + $1.filesChanged }
        
        // Get active projects
        let projectIds = Set(sessions.map { $0.projectId })
        let allProjects = try DatabaseManager.shared.getAllProjects()
        stats.activeProjects = allProjects.filter { projectIds.contains($0.id) }
        
        return stats
    }
    
    // MARK: - Week Statistics
    
    /// Get statistics for the current week (Monday to Sunday)
    func getCurrentWeekStatistics() throws -> WeekStatistics {
        let calendar = Calendar.current
        let today = Date()
        
        // Find start of week (Monday)
        var startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        
        // Adjust for locales where week starts on Sunday
        if calendar.firstWeekday == 1 { // Sunday
            startOfWeek = calendar.date(byAdding: .day, value: 1, to: startOfWeek)!
        }
        
        let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek)!
        
        return try getWeekStatistics(from: startOfWeek, to: endOfWeek)
    }
    
    /// Get statistics for a specific week
    func getWeekStatistics(from startDate: Date, to endDate: Date) throws -> WeekStatistics {
        var stats = WeekStatistics(startDate: startDate, endDate: endDate)
        
        let calendar = Calendar.current
        var currentDate = startDate
        
        while currentDate <= endDate {
            let dayStats = try getStatisticsForDate(currentDate)
            stats.days.append(dayStats)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return stats
    }
    
    /// Get statistics for the last N days
    func getStatisticsForLastDays(_ count: Int) throws -> [DayStatistics] {
        let calendar = Calendar.current
        var stats: [DayStatistics] = []
        
        for i in 0..<count {
            guard let date = calendar.date(byAdding: .day, value: -i, to: Date()) else { continue }
            stats.append(try getStatisticsForDate(date))
        }
        
        return stats
    }
    
    // MARK: - Project Statistics
    
    /// Get statistics for a specific project
    func getProjectStatistics(projectId: UUID) throws -> ProjectStatistics? {
        let allProjects = try DatabaseManager.shared.getAllProjects()
        guard let project = allProjects.first(where: { $0.id == projectId }) else {
            return nil
        }
        
        var stats = ProjectStatistics(project: project)
        
        // Get all sessions for this project
        let sessions = try DatabaseManager.shared.getSessionsForProject(projectId)
        stats.sessionCount = sessions.count
        stats.totalDuration = sessions.reduce(0) { $0 + $1.duration }
        
        // Get commits for all sessions
        var allCommits: [Commit] = []
        for session in sessions {
            let commits = try DatabaseManager.shared.getCommitsForSession(session.id)
            allCommits.append(contentsOf: commits)
        }
        
        stats.commitCount = allCommits.count
        stats.additions = allCommits.reduce(0) { $0 + $1.additions }
        stats.deletions = allCommits.reduce(0) { $0 + $1.deletions }
        stats.lastActivity = allCommits.map { $0.timestamp }.max()
        
        return stats
    }
    
    /// Get statistics for all tracked projects
    func getAllProjectStatistics() throws -> [ProjectStatistics] {
        let projects = try DatabaseManager.shared.getTrackedProjects()
        return try projects.compactMap { try getProjectStatistics(projectId: $0.id) }
    }
    
    // MARK: - Summary Statistics
    
    /// Quick summary for the menubar
    struct QuickSummary {
        var todayDuration: TimeInterval = 0
        var todayCommits: Int = 0
        var activeProject: Project?
        var latestCommit: Commit?
        
        var formattedDuration: String {
            formatDuration(todayDuration)
        }
    }
    
    /// Get a quick summary for display in the menubar
    func getQuickSummary() throws -> QuickSummary {
        var summary = QuickSummary()
        
        // Today's data
        let todayStats = try getTodayStatistics()
        summary.todayDuration = todayStats.totalDuration
        summary.todayCommits = todayStats.commitCount
        
        // Active project from ActivityTracker
        summary.activeProject = ActivityTracker.shared.activeProject
        
        // Latest commit
        summary.latestCommit = try DatabaseManager.shared.getLatestCommit()
        
        return summary
    }
}

// MARK: - Helper Functions

private func formatDuration(_ duration: TimeInterval) -> String {
    let totalMinutes = Int(duration / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else if minutes > 0 {
        return "\(minutes)m"
    } else {
        return "0m"
    }
}
