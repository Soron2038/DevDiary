import Foundation

/// Represents a Git commit
struct Commit: Identifiable, Equatable, Codable {
    let id: UUID
    let sessionId: UUID
    let hash: String
    let message: String
    let author: String
    let timestamp: Date
    let filesChanged: Int
    let additions: Int
    let deletions: Int
    
    init(
        id: UUID = UUID(),
        sessionId: UUID,
        hash: String,
        message: String,
        author: String,
        timestamp: Date,
        filesChanged: Int = 0,
        additions: Int = 0,
        deletions: Int = 0
    ) {
        self.id = id
        self.sessionId = sessionId
        self.hash = hash
        self.message = message
        self.author = author
        self.timestamp = timestamp
        self.filesChanged = filesChanged
        self.additions = additions
        self.deletions = deletions
    }
    
    /// Short version of the commit hash (first 7 characters)
    var shortHash: String {
        String(hash.prefix(7))
    }
    
    /// First line of the commit message
    var shortMessage: String {
        message.components(separatedBy: .newlines).first ?? message
    }
}
