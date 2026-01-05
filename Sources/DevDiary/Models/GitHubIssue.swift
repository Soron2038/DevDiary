import Foundation
import SwiftUI

/// Represents a GitHub Issue from the API
struct GitHubIssue: Codable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: String
    let state: String           // "open", "closed"
    let createdAt: Date
    let updatedAt: Date
    let user: GitHubUser
    let labels: [GitHubLabel]
    let repositoryURL: String?
    
    // For issues from /issues endpoint, repository info comes separately
    let repository: RepositoryInfo?
    
    struct GitHubUser: Codable {
        let login: String
        let avatarURL: String?
        
        enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatar_url"
        }
    }
    
    struct GitHubLabel: Codable, Identifiable {
        let id: Int
        let name: String
        let color: String  // Hex color without #
        
        var swiftUIColor: Color {
            Color(hex: color)
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case user
        case labels
        case repositoryURL = "repository_url"
        case repository
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

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
