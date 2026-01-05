import Foundation
import SQLite

/// Manages database schema migrations
final class MigrationManager {
    private let db: Connection
    
    // Migration version table
    private let migrations = Table("schema_migrations")
    private let version = Expression<Int>("version")
    private let appliedAt = Expression<Date>("applied_at")
    
    init(db: Connection) {
        self.db = db
    }
    
    /// Run all pending migrations
    func migrate() throws {
        try createMigrationsTableIfNeeded()
        
        let currentVersion = try getCurrentVersion()
        let allMigrations = Self.allMigrations
        
        for migration in allMigrations where migration.version > currentVersion {
            try migration.up(db)
            try recordMigration(version: migration.version)
        }
    }
    
    /// Get the current schema version
    func getCurrentVersion() throws -> Int {
        let query = migrations.select(version).order(version.desc).limit(1)
        return try db.pluck(query)?[version] ?? 0
    }
    
    // MARK: - Private
    
    private func createMigrationsTableIfNeeded() throws {
        try db.run(migrations.create(ifNotExists: true) { t in
            t.column(version, primaryKey: true)
            t.column(appliedAt)
        })
    }
    
    private func recordMigration(version: Int) throws {
        try db.run(migrations.insert(
            self.version <- version,
            appliedAt <- Date()
        ))
    }
}

// MARK: - Migration Protocol

protocol Migration {
    var version: Int { get }
    func up(_ db: Connection) throws
}

// MARK: - Migrations

extension MigrationManager {
    /// All migrations in order
    static let allMigrations: [Migration] = [
        Migration001_InitialSchema()
    ]
}

// MARK: - Migration 001: Initial Schema

struct Migration001_InitialSchema: Migration {
    let version = 1
    
    func up(_ db: Connection) throws {
        // Projects table
        let projects = Table("projects")
        try db.run(projects.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("name"))
            t.column(Expression<String>("path"), unique: true)
            t.column(Expression<Bool>("is_tracked"))
            t.column(Expression<Date>("created_at"))
        })
        
        // Sessions table
        let sessions = Table("sessions")
        try db.run(sessions.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("project_id"))
            t.column(Expression<Date>("start_time"))
            t.column(Expression<Date?>("end_time"))
            t.column(Expression<Bool>("is_active"))
            
            t.foreignKey(
                Expression<String>("project_id"),
                references: projects, Expression<String>("id"),
                delete: .cascade
            )
        })
        
        // Commits table
        let commits = Table("commits")
        try db.run(commits.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("session_id"))
            t.column(Expression<String>("hash"))
            t.column(Expression<String>("message"))
            t.column(Expression<String>("author"))
            t.column(Expression<Date>("timestamp"))
            t.column(Expression<Int>("files_changed"))
            t.column(Expression<Int>("additions"))
            t.column(Expression<Int>("deletions"))
            
            t.foreignKey(
                Expression<String>("session_id"),
                references: sessions, Expression<String>("id"),
                delete: .cascade
            )
        })
        
        // Create indexes for common queries
        try db.run(sessions.createIndex(Expression<String>("project_id"), ifNotExists: true))
        try db.run(sessions.createIndex(Expression<Date>("start_time"), ifNotExists: true))
        try db.run(commits.createIndex(Expression<String>("session_id"), ifNotExists: true))
        try db.run(commits.createIndex(Expression<Date>("timestamp"), ifNotExists: true))
        try db.run(commits.createIndex(Expression<String>("hash"), unique: true, ifNotExists: true))
    }
}
