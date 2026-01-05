import Foundation
import os.log

/// Notification names for activity events
extension Notification.Name {
    static let sessionStarted = Notification.Name("com.devdiary.sessionStarted")
    static let sessionEnded = Notification.Name("com.devdiary.sessionEnded")
    static let activeProjectChanged = Notification.Name("com.devdiary.activeProjectChanged")
}

/// Tracks work sessions and manages session lifecycle
final class ActivityTracker {
    static let shared = ActivityTracker()
    
    private let logger = Logger(subsystem: "com.devdiary", category: "Activity")
    
    /// Session timeout in seconds (default: 15 minutes)
    var sessionTimeoutInterval: TimeInterval = 15 * 60
    
    /// Check interval for session timeout (default: 60 seconds)
    private let checkInterval: TimeInterval = 60
    
    /// Currently active session
    private(set) var activeSession: Session?
    
    /// Currently active project
    private(set) var activeProject: Project?
    
    /// Timestamp of last recorded activity
    private var lastActivityTime: Date?
    
    /// Timer for checking session timeout
    private var timeoutCheckTask: Task<Void, Never>?
    
    /// Whether tracking is active
    private(set) var isTracking = false
    
    private init() {}
    
    // MARK: - Lifecycle
    
    /// Start activity tracking
    func start() {
        guard !isTracking else { return }
        
        isTracking = true
        logger.info("Activity tracking started")
        
        // Restore active session from database
        restoreActiveSession()
        
        // Start timeout checker
        startTimeoutChecker()
    }
    
    /// Stop activity tracking
    func stop() {
        guard isTracking else { return }
        
        isTracking = false
        timeoutCheckTask?.cancel()
        timeoutCheckTask = nil
        
        logger.info("Activity tracking stopped")
    }
    
    // MARK: - Session Management
    
    /// Record activity for a project (called when commits are detected)
    /// - Parameter project: The project with activity
    /// - Returns: The active session for the project
    @discardableResult
    func recordActivity(for project: Project) throws -> Session {
        lastActivityTime = Date()
        
        // Check if we need to switch projects
        if let currentSession = activeSession {
            if currentSession.projectId == project.id {
                // Same project, keep session active
                logger.debug("Activity recorded for current session")
                return currentSession
            } else {
                // Different project, end current session and start new one
                try endCurrentSession()
            }
        }
        
        // Start new session
        return try startSession(for: project)
    }
    
    /// Manually end the current session
    func endCurrentSession() throws {
        guard let session = activeSession else { return }
        
        try DatabaseManager.shared.endSession(session)
        
        let previousProject = activeProject
        activeSession = nil
        activeProject = nil
        lastActivityTime = nil
        
        logger.info("Session ended for project: \(previousProject?.name ?? "unknown")")
        
        // Notify observers
        NotificationCenter.default.post(
            name: .sessionEnded,
            object: nil,
            userInfo: ["session": session]
        )
    }
    
    /// Get the current session duration
    var currentSessionDuration: TimeInterval {
        guard let session = activeSession else { return 0 }
        return session.duration
    }
    
    /// Check if a session is currently active
    var hasActiveSession: Bool {
        activeSession != nil
    }
    
    // MARK: - Private
    
    private func startSession(for project: Project) throws -> Session {
        let session = try DatabaseManager.shared.createSession(projectId: project.id)
        
        activeSession = session
        activeProject = project
        lastActivityTime = Date()
        
        logger.info("Session started for project: \(project.name)")
        
        // Notify observers
        NotificationCenter.default.post(
            name: .sessionStarted,
            object: nil,
            userInfo: ["session": session, "project": project]
        )
        
        NotificationCenter.default.post(
            name: .activeProjectChanged,
            object: nil,
            userInfo: ["project": project]
        )
        
        return session
    }
    
    private func restoreActiveSession() {
        do {
            if let session = try DatabaseManager.shared.getActiveSession() {
                // Check if session is still valid (not timed out)
                let timeSinceStart = Date().timeIntervalSince(session.startTime)
                
                // Get the last commit time for this session
                let commits = try DatabaseManager.shared.getCommitsForSession(session.id)
                let lastCommitTime = commits.map { $0.timestamp }.max() ?? session.startTime
                let timeSinceLastCommit = Date().timeIntervalSince(lastCommitTime)
                
                if timeSinceLastCommit < sessionTimeoutInterval {
                    // Session is still valid
                    activeSession = session
                    lastActivityTime = lastCommitTime
                    
                    // Load project
                    let projects = try DatabaseManager.shared.getAllProjects()
                    activeProject = projects.first { $0.id == session.projectId }
                    
                    logger.info("Restored active session for \(self.activeProject?.name ?? "unknown") (duration: \(Int(timeSinceStart / 60))min)")
                } else {
                    // Session timed out, end it
                    try DatabaseManager.shared.endSession(session)
                    logger.info("Ended stale session from previous run")
                }
            }
        } catch {
            logger.error("Failed to restore active session: \(error.localizedDescription)")
        }
    }
    
    private func startTimeoutChecker() {
        timeoutCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkSessionTimeout()
                try? await Task.sleep(nanoseconds: UInt64((self?.checkInterval ?? 60) * 1_000_000_000))
            }
        }
    }
    
    private func checkSessionTimeout() async {
        guard let lastActivity = lastActivityTime,
              activeSession != nil else {
            return
        }
        
        let timeSinceActivity = Date().timeIntervalSince(lastActivity)
        
        if timeSinceActivity >= sessionTimeoutInterval {
            logger.info("Session timeout reached (\(Int(timeSinceActivity / 60))min since last activity)")
            
            do {
                try endCurrentSession()
            } catch {
                logger.error("Failed to end timed-out session: \(error.localizedDescription)")
            }
        }
    }
}
