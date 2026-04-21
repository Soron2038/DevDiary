import Foundation
import os.log

/// Uniform async interface over all remote forges (GitHub, GitLab instances).
/// Each conforming type owns exactly one `ForgeAccount`.
protocol RemoteForgeProvider: AnyObject {
    var account: ForgeAccount { get }
    var isConnected: Bool { get }

    /// Verify the stored credentials against the forge API. Returns the username
    /// on success. Throws if the credentials are missing or invalid.
    func verifyCredentials() async throws -> String

    func listAssignedMergeRequests() async throws -> [ForgeMergeRequest]
    func listAssignedIssues() async throws -> [ForgeIssue]
    func listRepositories(includeArchived: Bool, includeForks: Bool) async throws -> [ForgeRepository]
    func ciStatus(for repository: ForgeRepository) async throws -> ForgeCIStatus

    /// Remove any stored credentials for this account.
    func disconnect() throws
}

extension RemoteForgeProvider {
    /// Convenience fetch that loads CI status for many repos in parallel and
    /// swallows individual failures as `.unknown`.
    func ciStatuses(for repositories: [ForgeRepository]) async -> [String: ForgeCIStatus] {
        await withTaskGroup(of: (String, ForgeCIStatus).self) { group in
            for repo in repositories {
                group.addTask {
                    do {
                        let status = try await self.ciStatus(for: repo)
                        return (repo.id, status)
                    } catch {
                        return (repo.id, .unknown)
                    }
                }
            }
            var result: [String: ForgeCIStatus] = [:]
            for await (id, status) in group {
                result[id] = status
            }
            return result
        }
    }
}

// MARK: - Registry

/// Central registry of all configured forge accounts and their provider instances.
/// Persists account metadata in UserDefaults; tokens live in the Keychain.
final class ForgeRegistry {
    static let shared = ForgeRegistry()

    private let logger = Logger(subsystem: "com.devdiary", category: "ForgeRegistry")
    private let accountsKey = "ForgeAccounts.v1"

    private var accountsCache: [ForgeAccount] = []
    private var providerCache: [String: any RemoteForgeProvider] = [:]
    private let lock = NSLock()

    private init() {
        loadAccounts()
        ensureGitHubAccount()
    }

    // MARK: Accounts

    /// All configured accounts (GitHub is always present, even when not connected).
    func accounts() -> [ForgeAccount] {
        lock.lock()
        defer { lock.unlock() }
        return accountsCache
    }

    /// Accounts filtered by kind (stable order).
    func accounts(of kind: ForgeKind) -> [ForgeAccount] {
        accounts().filter { $0.kind == kind }
    }

    func account(id: String) -> ForgeAccount? {
        accounts().first(where: { $0.id == id })
    }

    // MARK: Providers

    /// Resolve (and cache) the provider for an account.
    func provider(for account: ForgeAccount) -> any RemoteForgeProvider {
        lock.lock()
        defer { lock.unlock() }
        if let cached = providerCache[account.id] {
            return cached
        }
        let provider: any RemoteForgeProvider
        switch account.kind {
        case .github:
            provider = GitHubService.shared
        case .gitlab:
            provider = GitLabService(account: account)
        }
        providerCache[account.id] = provider
        return provider
    }

    func provider(for accountId: String) -> (any RemoteForgeProvider)? {
        guard let account = account(id: accountId) else { return nil }
        return provider(for: account)
    }

    /// Every configured provider (useful for cross-account aggregation views).
    func allProviders() -> [any RemoteForgeProvider] {
        accounts().map { provider(for: $0) }
    }

    /// Every provider whose credentials are currently stored.
    func connectedProviders() -> [any RemoteForgeProvider] {
        allProviders().filter { $0.isConnected }
    }

    // MARK: Mutation

    /// Create and persist a new GitLab account. The caller is responsible for
    /// storing the PAT in the Keychain under the returned account's keychainAccount.
    @discardableResult
    func addGitLabAccount(baseURL: URL, displayName: String, username: String?) -> ForgeAccount {
        let account = ForgeAccount(
            id: UUID().uuidString,
            kind: .gitlab,
            displayName: displayName,
            baseURL: baseURL,
            username: username
        )
        lock.lock()
        accountsCache.append(account)
        lock.unlock()
        persistAccounts()
        return account
    }

    /// Update mutable metadata (displayName, username) on an existing account.
    func updateAccount(_ updated: ForgeAccount) {
        lock.lock()
        if let idx = accountsCache.firstIndex(where: { $0.id == updated.id }) {
            accountsCache[idx] = updated
        }
        // Invalidate cached provider so it picks up new metadata on next access.
        providerCache[updated.id] = nil
        lock.unlock()
        persistAccounts()
    }

    /// Remove an account (GitHub cannot be removed — only disconnected).
    func removeAccount(id: String) {
        guard id != ForgeAccount.gitHubAccountID else {
            logger.warning("Refusing to remove the GitHub account (disconnect instead)")
            return
        }
        lock.lock()
        if let idx = accountsCache.firstIndex(where: { $0.id == id }) {
            let account = accountsCache.remove(at: idx)
            providerCache[id] = nil
            lock.unlock()
            // Drop token
            try? KeychainService.shared.deletePassword(
                service: GitLabService.keychainService,
                account: account.keychainAccount
            )
            persistAccounts()
        } else {
            lock.unlock()
        }
    }

    // MARK: - Persistence

    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: accountsKey) else {
            accountsCache = []
            return
        }
        do {
            accountsCache = try JSONDecoder().decode([ForgeAccount].self, from: data)
        } catch {
            logger.error("Failed to decode accounts: \(error.localizedDescription)")
            accountsCache = []
        }
    }

    private func persistAccounts() {
        lock.lock()
        let snapshot = accountsCache
        lock.unlock()
        do {
            let data = try JSONEncoder().encode(snapshot)
            UserDefaults.standard.set(data, forKey: accountsKey)
        } catch {
            logger.error("Failed to encode accounts: \(error.localizedDescription)")
        }
    }

    private func ensureGitHubAccount() {
        lock.lock()
        let hasGitHub = accountsCache.contains(where: { $0.id == ForgeAccount.gitHubAccountID })
        lock.unlock()
        guard !hasGitHub else { return }
        let gh = ForgeAccount(
            id: ForgeAccount.gitHubAccountID,
            kind: .github,
            displayName: "GitHub",
            baseURL: URL(string: "https://api.github.com")!,
            username: nil
        )
        lock.lock()
        accountsCache.insert(gh, at: 0)
        lock.unlock()
        persistAccounts()
    }
}
