import Foundation

/// Provider-agnostic representation of a remote repository.
struct ForgeRepository: Identifiable, Equatable {
    /// Stable ID in the form `"<accountId>:<providerId>"` so rows from multiple
    /// accounts can coexist in a single SwiftUI list.
    let id: String
    let providerAccountId: String
    let remoteId: String              // Provider-native ID (GitHub: numeric, GitLab: numeric)
    let name: String                  // Short name, e.g. "DevDiary"
    let fullName: String              // "owner/name" (GitHub) or "group/subgroup/name" (GitLab)
    let description: String?
    let isPrivate: Bool
    let webURL: String                // Browsable HTTPS URL
    let cloneURL: String              // Clone URL (HTTPS)
    let sshURL: String?
    let defaultBranch: String?
    let updatedAt: Date
    let pushedAt: Date?
    let language: String?
    let stars: Int
    let forks: Int
    let isArchived: Bool
    let isFork: Bool

    /// Build the stable list ID from the pieces.
    static func makeId(accountId: String, remoteId: String) -> String {
        "\(accountId):\(remoteId)"
    }
}
