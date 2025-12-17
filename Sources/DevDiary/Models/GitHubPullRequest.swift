import Foundation

/// Represents a GitHub Pull Request from the API
struct GitHubPullRequest: Codable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: String
    let state: String           // "open", "closed"
    let draft: Bool
    let createdAt: Date
    let updatedAt: Date
    let user: GitHubUser
    let repository: RepositoryInfo?
    
    // From search API - repository info is nested differently
    let repositoryURL: String?
    
    struct GitHubUser: Codable {
        let login: String
        let avatarURL: String?
        
        enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatar_url"
        }
    }
    
    struct RepositoryInfo: Codable {
        let fullName: String
        
        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case htmlURL = "html_url"
        case state
        case draft
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case user
        case repository
        case repositoryURL = "repository_url"
    }
    
    /// Extract repository name from URL or nested object
    var repoName: String {
        if let repo = repository {
            return repo.fullName
        }
        // Parse from repository_url: "https://api.github.com/repos/owner/name"
        if let url = repositoryURL {
            let parts = url.split(separator: "/")
            if parts.count >= 2 {
                return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
            }
        }
        return "Unknown"
    }
    
    var isOpen: Bool { state == "open" }
}

/// Response wrapper for search API
struct GitHubSearchResponse<T: Codable>: Codable {
    let totalCount: Int
    let incompleteResults: Bool
    let items: [T]
    
    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case incompleteResults = "incomplete_results"
        case items
    }
}
