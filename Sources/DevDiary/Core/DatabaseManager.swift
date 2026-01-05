import Foundation
import SQLite
import os.log

/// Central database manager for all data operations
final class DatabaseManager {
    static let shared = DatabaseManager()
    
    private var db: Connection?
    private let logger = Logger(subsystem: "com.devdiary", category: "Database")
    
    // Table definitions
    private let projects = Table("projects")
    private let sessions = Table("sessions")
    private let commits = Table("commits")
    
    // Project columns
    private let projectId = Expression<String>("id")
    private let projectName = Expression<String>("name")
    private let projectPath = Expression<String>("path")
    private let projectIsTracked = Expression<Bool>("is_tracked")
    private let projectCreatedAt = Expression<Date>("created_at")
    
    // Session columns
    private let sessionId = Expression<String>("id")
    private let sessionProjectId = Expression<String>("project_id")
    private let sessionStartTime = Expression<Date>("start_time")
    private let sessionEndTime = Expression<Date?>("end_time")
    private let sessionIsActive = Expression<Bool>("is_active")
    
    // Commit columns
    private let commitId = Expression<String>("id")
    private let commitSessionId = Expression<String>("session_id")
    private let commitHash = Expression<String>("hash")
    private let commitMessage = Expression<String>("message")
    private let commitAuthor = Expression<String>("author")
    private let commitTimestamp = Expression<Date>("timestamp")
    private let commitFilesChanged = Expression<Int>("files_changed")
    private let commitAdditions = Expression<Int>("additions")
    private let commitDeletions = Expression<Int>("deletions")
    
    private init() {}
    
    // MARK: - Setup
    
    /// Initialize the database connection and run migrations
    func setup() throws {
        let dbPath = try getDatabasePath()
        logger.info("Database path: \(dbPath)")
        
        db = try Connection(dbPath)
        
        // Enable foreign keys
        try db?.execute("PRAGMA foreign_keys = ON")
        
        // Run migrations
        let migrationManager = MigrationManager(db: db!)
        try migrationManager.migrate()
        
        logger.info("Database setup complete")
    }
    
    /// Returns the path to the database file, creating directories if needed
    private func getDatabasePath() throws -> String {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("DevDiary", isDirectory: true)
        
        if !fileManager.fileExists(atPath: appDir.path) {
            try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        
        return appDir.appendingPathComponent("devdiary.db").path
    }
    
    // MARK: - Project Operations
    
    /// Create a new project
    @discardableResult
    func createProject(name: String, path: String) throws -> Project {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let project = Project(name: name, path: path)
        
        try db.run(projects.insert(
            projectId <- project.id.uuidString,
            projectName <- project.name,
            projectPath <- project.path,
            projectIsTracked <- project.isTracked,
            projectCreatedAt <- project.createdAt
        ))
        
        logger.debug("Created project: \(project.name)")
        return project
    }
    
    /// Get all projects
    func getAllProjects() throws -> [Project] {
        guard let db = db else { throw DatabaseError.notConnected }
        
        return try db.prepare(projects).map { row in
            Project(
                id: UUID(uuidString: row[projectId])!,
                name: row[projectName],
                path: row[projectPath],
                isTracked: row[projectIsTracked],
                createdAt: row[projectCreatedAt]
            )
        }
    }
    
    /// Get only tracked projects
    func getTrackedProjects() throws -> [Project] {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let query = projects.filter(projectIsTracked == true)
        return try db.prepare(query).map { row in
            Project(
                id: UUID(uuidString: row[projectId])!,
                name: row[projectName],
                path: row[projectPath],
                isTracked: row[projectIsTracked],
                createdAt: row[projectCreatedAt]
            )
        }
    }
    
    /// Get a project by path
    func getProject(byPath path: String) throws -> Project? {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let query = projects.filter(projectPath == path)
        guard let row = try db.pluck(query) else { return nil }
        
        return Project(
            id: UUID(uuidString: row[projectId])!,
            name: row[projectName],
            path: row[projectPath],
            isTracked: row[projectIsTracked],
            createdAt: row[projectCreatedAt]
        )
    }
    
    /// Update a project
    func updateProject(_ project: Project) throws {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let target = projects.filter(projectId == project.id.uuidString)
        try db.run(target.update(
            projectName <- project.name,
            projectPath <- project.path,
            projectIsTracked <- project.isTracked
        ))
        
        logger.debug("Updated project: \(project.name)")
    }
    
    /// Delete a project
    func deleteProject(_ project: Project) throws {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let target = projects.filter(projectId == project.id.uuidString)
        try db.run(target.delete())
        
        logger.debug("Deleted project: \(project.name)")
    }
    
    // MARK: - Session Operations
    
    /// Create a new session
    @discardableResult
    func createSession(projectId: UUID) throws -> Session {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let session = Session(projectId: projectId)
        
        try db.run(sessions.insert(
            sessionId <- session.id.uuidString,
            sessionProjectId <- session.projectId.uuidString,
            sessionStartTime <- session.startTime,
            sessionEndTime <- session.endTime,
            sessionIsActive <- session.isActive
        ))
        
        logger.debug("Created session for project: \(projectId)")
        return session
    }
    
    /// Get the currently active session (if any)
    func getActiveSession() throws -> Session? {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let query = sessions.filter(sessionIsActive == true).limit(1)
        guard let row = try db.pluck(query) else { return nil }
        
        return Session(
            id: UUID(uuidString: row[sessionId])!,
            projectId: UUID(uuidString: row[sessionProjectId])!,
            startTime: row[sessionStartTime],
            endTime: row[sessionEndTime],
            isActive: row[sessionIsActive]
        )
    }
    
    /// End a session
    func endSession(_ session: Session) throws {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let target = sessions.filter(sessionId == session.id.uuidString)
        try db.run(target.update(
            sessionEndTime <- Date(),
            sessionIsActive <- false
        ))
        
        logger.debug("Ended session: \(session.id)")
    }
    
    /// Get sessions for a specific date
    func getSessionsForDate(_ date: Date) throws -> [Session] {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let query = sessions
            .filter(sessionStartTime >= startOfDay && sessionStartTime < endOfDay)
            .order(sessionStartTime)
        
        return try db.prepare(query).map { row in
            Session(
                id: UUID(uuidString: row[sessionId])!,
                projectId: UUID(uuidString: row[sessionProjectId])!,
                startTime: row[sessionStartTime],
                endTime: row[sessionEndTime],
                isActive: row[sessionIsActive]
            )
        }
    }
    
    /// Get all sessions for a project
    func getSessionsForProject(_ projectId: UUID) throws -> [Session] {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let query = sessions
            .filter(sessionProjectId == projectId.uuidString)
            .order(sessionStartTime.desc)
        
        return try db.prepare(query).map { row in
            Session(
                id: UUID(uuidString: row[sessionId])!,
                projectId: UUID(uuidString: row[sessionProjectId])!,
                startTime: row[sessionStartTime],
                endTime: row[sessionEndTime],
                isActive: row[sessionIsActive]
            )
        }
    }
    
    // MARK: - Commit Operations
    
    /// Create a new commit
    @discardableResult
    func createCommit(
        sessionId: UUID,
        hash: String,
        message: String,
        author: String,
        timestamp: Date,
        filesChanged: Int = 0,
        additions: Int = 0,
        deletions: Int = 0
    ) throws -> Commit {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let commit = Commit(
            sessionId: sessionId,
            hash: hash,
            message: message,
            author: author,
            timestamp: timestamp,
            filesChanged: filesChanged,
            additions: additions,
            deletions: deletions
        )
        
        try db.run(commits.insert(
            commitId <- commit.id.uuidString,
            commitSessionId <- commit.sessionId.uuidString,
            commitHash <- commit.hash,
            commitMessage <- commit.message,
            commitAuthor <- commit.author,
            commitTimestamp <- commit.timestamp,
            commitFilesChanged <- commit.filesChanged,
            commitAdditions <- commit.additions,
            commitDeletions <- commit.deletions
        ))
        
        logger.debug("Created commit: \(commit.shortHash)")
        return commit
    }
    
    /// Check if a commit with the given hash already exists
    func commitExists(hash: String) throws -> Bool {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let query = commits.filter(commitHash == hash)
        return try db.pluck(query) != nil
    }
    
    /// Get commits for a session
    func getCommitsForSession(_ sessionId: UUID) throws -> [Commit] {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let query = commits
            .filter(commitSessionId == sessionId.uuidString)
            .order(commitTimestamp)
        
        return try db.prepare(query).map { row in
            Commit(
                id: UUID(uuidString: row[commitId])!,
                sessionId: UUID(uuidString: row[self.commitSessionId])!,
                hash: row[commitHash],
                message: row[commitMessage],
                author: row[commitAuthor],
                timestamp: row[commitTimestamp],
                filesChanged: row[commitFilesChanged],
                additions: row[commitAdditions],
                deletions: row[commitDeletions]
            )
        }
    }
    
    /// Get commits for a specific date
    func getCommitsForDate(_ date: Date) throws -> [Commit] {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let query = commits
            .filter(commitTimestamp >= startOfDay && commitTimestamp < endOfDay)
            .order(commitTimestamp)
        
        return try db.prepare(query).map { row in
            Commit(
                id: UUID(uuidString: row[commitId])!,
                sessionId: UUID(uuidString: row[self.commitSessionId])!,
                hash: row[commitHash],
                message: row[commitMessage],
                author: row[commitAuthor],
                timestamp: row[commitTimestamp],
                filesChanged: row[commitFilesChanged],
                additions: row[commitAdditions],
                deletions: row[commitDeletions]
            )
        }
    }
    
    /// Get the most recent commit
    func getLatestCommit() throws -> Commit? {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let query = commits.order(commitTimestamp.desc).limit(1)
        guard let row = try db.pluck(query) else { return nil }
        
        return Commit(
            id: UUID(uuidString: row[commitId])!,
            sessionId: UUID(uuidString: row[commitSessionId])!,
            hash: row[commitHash],
            message: row[commitMessage],
            author: row[commitAuthor],
            timestamp: row[commitTimestamp],
            filesChanged: row[commitFilesChanged],
            additions: row[commitAdditions],
            deletions: row[commitDeletions]
        )
    }
    
    /// Get total commit count for today
    func getTodayCommitCount() throws -> Int {
        guard let db = db else { throw DatabaseError.notConnected }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let query = commits.filter(commitTimestamp >= startOfDay && commitTimestamp < endOfDay)
        return try db.scalar(query.count)
    }
}

// MARK: - Errors

enum DatabaseError: LocalizedError {
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Database is not connected. Call setup() first."
        }
    }
}
