import Foundation

/// Maps a git remote URL (HTTPS or SSH) to the configured `ForgeAccount` that
/// should own it. Matching is purely host-based, so it works without API calls.
enum RemoteURLResolver {
    /// Extract the host portion of a git remote URL.
    /// Handles both HTTPS (`https://host/path`) and SSH (`git@host:path`) forms.
    static func host(from remoteURL: String) -> String? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // SSH form: git@host:owner/repo(.git)
        if trimmed.hasPrefix("git@") {
            let body = trimmed.dropFirst(4)
            if let colon = body.firstIndex(of: ":") {
                return String(body[..<colon]).lowercased()
            }
            return nil
        }

        // URL-based form (https://, http://, ssh://, git://)
        if let url = URL(string: trimmed), let host = url.host {
            return host.lowercased()
        }
        return nil
    }

    /// Resolve the best-matching configured account for a remote URL.
    /// Returns `nil` if no configured account has a matching host.
    static func account(for remoteURL: String, in registry: ForgeRegistry = .shared) -> ForgeAccount? {
        guard let host = host(from: remoteURL) else { return nil }

        // github.com always maps to the GitHub account (if present).
        if host == "github.com" {
            return registry.account(id: ForgeAccount.gitHubAccountID)
        }

        // Match against the host of each configured GitLab account's baseURL.
        for account in registry.accounts(of: .gitlab) {
            if let accountHost = account.baseURL.host?.lowercased(), accountHost == host {
                return account
            }
        }
        return nil
    }
}
