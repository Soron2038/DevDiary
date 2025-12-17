import Foundation

/// Service for generating Markdown reports from tracked data
final class ReportService {
    static let shared = ReportService()
    
    private init() {}
    
    // MARK: - Report Types
    
    enum ReportType: String, CaseIterable, Identifiable {
        case today = "today"
        case yesterday = "yesterday"
        case thisWeek = "thisWeek"
        case lastWeek = "lastWeek"
        case thisMonth = "thisMonth"
        case custom = "custom"
        
        var id: String { rawValue }
        
        var localizationKey: String {
            "report.type.\(rawValue)"
        }
    }
    
    // MARK: - Report Generation
    
    /// Generate a report for a specific type
    func generateReport(type: ReportType, customStart: Date? = nil, customEnd: Date? = nil) throws -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let (startDate, endDate): (Date, Date)
        
        switch type {
        case .today:
            startDate = today
            endDate = today
            
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            startDate = yesterday
            endDate = yesterday
            
        case .thisWeek:
            var weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
            if calendar.firstWeekday == 1 { // Sunday
                weekStart = calendar.date(byAdding: .day, value: 1, to: weekStart)!
            }
            startDate = weekStart
            endDate = today
            
        case .lastWeek:
            var thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
            if calendar.firstWeekday == 1 {
                thisWeekStart = calendar.date(byAdding: .day, value: 1, to: thisWeekStart)!
            }
            let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart)!
            let lastWeekEnd = calendar.date(byAdding: .day, value: -1, to: thisWeekStart)!
            startDate = lastWeekStart
            endDate = lastWeekEnd
            
        case .thisMonth:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            startDate = monthStart
            endDate = today
            
        case .custom:
            guard let start = customStart, let end = customEnd else {
                throw ReportError.invalidDateRange
            }
            startDate = calendar.startOfDay(for: start)
            endDate = calendar.startOfDay(for: end)
        }
        
        return try generateReport(from: startDate, to: endDate)
    }
    
    /// Generate a Markdown report for a date range
    func generateReport(from startDate: Date, to endDate: Date) throws -> String {
        var markdown = ""
        let calendar = Calendar.current
        
        // Gather all data
        var allCommits: [Commit] = []
        var allSessions: [Session] = []
        var dayStatsList: [StatisticsService.DayStatistics] = []
        
        var currentDate = startDate
        while currentDate <= endDate {
            let dayStats = try StatisticsService.shared.getStatisticsForDate(currentDate)
            dayStatsList.append(dayStats)
            
            let dayCommits = try DatabaseManager.shared.getCommitsForDate(currentDate)
            allCommits.append(contentsOf: dayCommits)
            
            let daySessions = try DatabaseManager.shared.getSessionsForDate(currentDate)
            allSessions.append(contentsOf: daySessions)
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        // Calculate totals
        let totalDuration = dayStatsList.reduce(0) { $0 + $1.totalDuration }
        let totalCommits = allCommits.count
        let totalAdditions = allCommits.reduce(0) { $0 + $1.additions }
        let totalDeletions = allCommits.reduce(0) { $0 + $1.deletions }
        
        // Get projects
        let projectIds = Set(allSessions.map { $0.projectId })
        let allProjects = try DatabaseManager.shared.getAllProjects()
        let activeProjects = allProjects.filter { projectIds.contains($0.id) }
        
        // Title
        let titleFormatter = DateFormatter()
        titleFormatter.dateStyle = .medium
        titleFormatter.timeStyle = .none
        
        let isSingleDay = calendar.isDate(startDate, inSameDayAs: endDate)
        
        if isSingleDay {
            markdown += "# \(String(localized: "report.title.day")) - \(titleFormatter.string(from: startDate))\n\n"
        } else {
            markdown += "# \(String(localized: "report.title.range"))\n"
            markdown += "\(titleFormatter.string(from: startDate)) – \(titleFormatter.string(from: endDate))\n\n"
        }
        
        // Summary section
        markdown += "## \(String(localized: "report.section.summary"))\n\n"
        markdown += "- **\(String(localized: "report.stat.workTime")):** \(formatDuration(totalDuration))\n"
        markdown += "- **\(String(localized: "report.stat.commits")):** \(totalCommits)\n"
        markdown += "- **\(String(localized: "report.stat.linesAdded")):** +\(totalAdditions)\n"
        markdown += "- **\(String(localized: "report.stat.linesRemoved")):** -\(totalDeletions)\n"
        markdown += "- **\(String(localized: "report.stat.projects")):** \(activeProjects.count)\n\n"
        
        // Projects section
        if !activeProjects.isEmpty {
            markdown += "## \(String(localized: "report.section.projects"))\n\n"
            
            for project in activeProjects {
                let projectSessions = allSessions.filter { $0.projectId == project.id }
                let projectDuration = projectSessions.reduce(0) { $0 + $1.duration }
                
                // Get commits for this project's sessions
                let sessionIds = Set(projectSessions.map { $0.id })
                let projectCommits = allCommits.filter { sessionIds.contains($0.sessionId) }
                
                markdown += "### \(project.name)\n\n"
                markdown += "- \(String(localized: "report.stat.time")): \(formatDuration(projectDuration))\n"
                markdown += "- \(String(localized: "report.stat.commits")): \(projectCommits.count)\n"
                
                if !projectCommits.isEmpty {
                    let additions = projectCommits.reduce(0) { $0 + $1.additions }
                    let deletions = projectCommits.reduce(0) { $0 + $1.deletions }
                    markdown += "- \(String(localized: "report.stat.changes")): +\(additions) / -\(deletions)\n"
                }
                markdown += "\n"
            }
        }
        
        // Commits section (grouped by day if multiple days)
        if !allCommits.isEmpty {
            markdown += "## \(String(localized: "report.section.commits"))\n\n"
            
            if isSingleDay {
                // Single day: just list commits
                let sortedCommits = allCommits.sorted { $0.timestamp > $1.timestamp }
                for commit in sortedCommits {
                    markdown += formatCommit(commit, includeDate: false)
                }
            } else {
                // Multiple days: group by date
                let commitsByDate = Dictionary(grouping: allCommits) { commit in
                    calendar.startOfDay(for: commit.timestamp)
                }
                
                let sortedDates = commitsByDate.keys.sorted(by: >)
                for date in sortedDates {
                    guard let dayCommits = commitsByDate[date], !dayCommits.isEmpty else { continue }
                    
                    let dateStr = titleFormatter.string(from: date)
                    markdown += "### \(dateStr)\n\n"
                    
                    let sortedDayCommits = dayCommits.sorted { $0.timestamp > $1.timestamp }
                    for commit in sortedDayCommits {
                        markdown += formatCommit(commit, includeDate: false)
                    }
                    markdown += "\n"
                }
            }
        }
        
        // Footer
        markdown += "---\n"
        markdown += "*\(String(localized: "report.footer")) DevDiary*\n"
        
        return markdown
    }
    
    // MARK: - Helpers
    
    private func formatCommit(_ commit: Commit, includeDate: Bool) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = includeDate ? .short : .none
        
        var line = "- "
        if includeDate {
            line += "[\(timeFormatter.string(from: commit.timestamp))] "
        } else {
            let time = timeFormatter.string(from: commit.timestamp)
            line += "**\(time)** "
        }
        line += "`\(commit.shortHash)` \(commit.shortMessage)"
        
        if commit.additions > 0 || commit.deletions > 0 {
            line += " *(+\(commit.additions)/-\(commit.deletions))*"
        }
        
        line += "\n"
        return line
    }
    
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
    
    // MARK: - Errors
    
    enum ReportError: LocalizedError {
        case invalidDateRange
        case noData
        
        var errorDescription: String? {
            switch self {
            case .invalidDateRange:
                return String(localized: "report.error.invalidRange")
            case .noData:
                return String(localized: "report.error.noData")
            }
        }
    }
}
