import Foundation

/// Identifies which remote forge an account belongs to.
enum ForgeKind: String, Codable, CaseIterable {
    case github
    case gitlab
}

/// Account-level configuration for a connected remote forge (GitHub or a GitLab instance).
/// Metadata is persisted in UserDefaults; the access token lives in the Keychain under
/// the account's `keychainAccount` and the provider-specific `keychainService`.
struct ForgeAccount: Codable, Identifiable, Equatable {
    /// Stable identifier. For GitHub this is the constant `"github"`. For GitLab
    /// it is a UUID so multiple instances can coexist.
    let id: String
    let kind: ForgeKind
    /// Human-readable label shown in lists and badges (e.g. "GitHub" or "gitlab.mpsd.mpg.de").
    var displayName: String
    /// Base URL of the API (e.g. `https://api.github.com` or `https://gitlab.example.com`).
    let baseURL: URL
    /// Remembered login/username from the last successful verification.
    var username: String?

    var keychainAccount: String { id }

    /// The canonical GitHub account identifier.
    static let gitHubAccountID = "github"
}
