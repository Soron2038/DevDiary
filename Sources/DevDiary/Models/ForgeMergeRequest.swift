import Foundation

/// Provider-agnostic representation of a Pull Request (GitHub) or Merge Request (GitLab).
struct ForgeMergeRequest: Identifiable, Equatable {
    let id: String                    // "<accountId>:<providerId>"
    let providerAccountId: String
    let providerKind: ForgeKind
    let number: Int
    let title: String
    let webURL: String
    let isDraft: Bool
    let createdAt: Date
    let updatedAt: Date
    let authorLogin: String
    let authorAvatarURL: String?
    let repoFullName: String

    /// Short label shown next to the row — "PR" for GitHub, "MR" for GitLab.
    var kindLabel: String {
        switch providerKind {
        case .github: return "PR"
        case .gitlab: return "MR"
        }
    }
}
