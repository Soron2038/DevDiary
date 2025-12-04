import Foundation

/// Represents a tracked Git repository
struct Project: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var path: String
    var isTracked: Bool
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        isTracked: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.isTracked = isTracked
        self.createdAt = createdAt
    }
}
