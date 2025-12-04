import Foundation

/// Represents a work session for a project
struct Session: Identifiable, Equatable, Codable {
    let id: UUID
    let projectId: UUID
    let startTime: Date
    var endTime: Date?
    var isActive: Bool
    
    init(
        id: UUID = UUID(),
        projectId: UUID,
        startTime: Date = Date(),
        endTime: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.projectId = projectId
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
    }
    
    /// Duration of the session in seconds
    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
    
    /// Formatted duration string (e.g., "2h 30min")
    var formattedDuration: String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}
