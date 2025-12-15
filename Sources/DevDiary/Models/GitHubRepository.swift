import Foundation

/// Represents a GitHub repository from the API
struct GitHubRepository: Identifiable, Codable, Equatable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let isPrivate: Bool
    let htmlURL: String
    let cloneURL: String
    let sshURL: String
    let updatedAt: Date
    let pushedAt: Date?
    let language: String?
    let stargazersCount: Int
    let forksCount: Int
    let isArchived: Bool
    let isFork: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case description
        case isPrivate = "private"
        case htmlURL = "html_url"
        case cloneURL = "clone_url"
        case sshURL = "ssh_url"
        case updatedAt = "updated_at"
        case pushedAt = "pushed_at"
        case language
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case isArchived = "archived"
        case isFork = "fork"
    }
    
    /// Owner and repo name (e.g., "user/repo")
    var ownerAndName: String {
        fullName
    }
    
    /// Check if this repository matches a local git remote URL
    func matchesRemoteURL(_ remoteURL: String) -> Bool {
        let normalized = remoteURL.lowercased()
        return normalized.contains(fullName.lowercased()) ||
               normalized.contains(cloneURL.lowercased()) ||
               normalized.contains(sshURL.lowercased())
    }
}
