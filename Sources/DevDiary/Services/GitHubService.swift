import Foundation
import AppKit
import SwiftUI
import os.log

/// GitHub integration using OAuth 2.0 Device Authorization Grant (Device Flow).
/// No client secret required; users authorize in the browser with a user code.
///
/// Conforms to `RemoteForgeProvider` so GitHub can be used alongside GitLab
/// instances through a single aggregating pipeline.
final class GitHubService: RemoteForgeProvider {
    static let shared = GitHubService()
    private let logger = Logger(subsystem: "com.devdiary", category: "GitHub")

    enum GitEnvironment: String, CaseIterable {
        case dev, prod
    }

    // Keychain constants
    static let keychainService = "DevDiary.GitHub"
    private let keychainService: String
    private let legacyTokenAccount = "access_token"

    private let envDefaultsKey = "GitEnvironment"

    var account: ForgeAccount {
        ForgeRegistry.shared.account(id: ForgeAccount.gitHubAccountID)
            ?? ForgeAccount(
                id: ForgeAccount.gitHubAccountID,
                kind: .github,
                displayName: "GitHub",
                baseURL: URL(string: "https://api.github.com")!,
                username: nil
            )
    }

    var selectedEnvironment: GitEnvironment {
        if let raw = UserDefaults.standard.string(forKey: envDefaultsKey), let env = GitEnvironment(rawValue: raw) {
            return env
        }
        #if DEBUG
        return .dev
        #else
        return .prod
        #endif
    }

    func setEnvironment(_ env: GitEnvironment) {
        UserDefaults.standard.set(env.rawValue, forKey: envDefaultsKey)
    }

    // OAuth constants
    // Client ID can be configured by the user in Settings or via environment variables.
    // Environment variables checked (in order):
    //   DEV_DIARY_GITHUB_CLIENT_ID_DEV / _PROD, then DEV_DIARY_GITHUB_CLIENT_ID, then GITHUB_CLIENT_ID
    var clientId: String? {
        let env = selectedEnvironment
        if let configured = UserDefaults.standard.string(forKey: "GitHubClientID.\(env.rawValue)"), !configured.isEmpty {
            return configured
        }
        let procEnv = ProcessInfo.processInfo.environment
        let perEnvKey = env == .dev ? "DEV_DIARY_GITHUB_CLIENT_ID_DEV" : "DEV_DIARY_GITHUB_CLIENT_ID_PROD"
        return procEnv[perEnvKey] ?? procEnv["DEV_DIARY_GITHUB_CLIENT_ID"] ?? procEnv["GITHUB_CLIENT_ID"]
    }

    private init() {
        self.keychainService = GitHubService.keychainService
    }

    // MARK: - Client ID

    func saveClientId(_ value: String?) {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "GitHubClientID.\(selectedEnvironment.rawValue)"
        UserDefaults.standard.set(trimmed, forKey: key)
    }

    // MARK: - Device Flow Types

    struct DeviceCode: Decodable {
        let device_code: String
        let user_code: String
        let verification_uri: String
        let verification_uri_complete: String?
        let expires_in: Int
        let interval: Int
    }

    struct AccessTokenResponse: Decodable {
        let access_token: String
        let token_type: String
        let scope: String
    }

    enum AuthError: LocalizedError {
        case missingClientId
        case invalidURL
        case accessDenied
        case expired
        case notConnected
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .missingClientId:
                return "GitHub client id not configured. Set DEV_DIARY_GITHUB_CLIENT_ID."
            case .invalidURL:
                return "Invalid URL."
            case .accessDenied:
                return "Access was denied by the user."
            case .expired:
                return "Device code expired."
            case .notConnected:
                return "Not connected to GitHub."
            case .unknown(let msg):
                return msg
            }
        }
    }

    // MARK: - Connection State

    var isConnected: Bool {
        hasToken(for: selectedEnvironment)
    }

    private func tokenAccount(for env: GitEnvironment) -> String {
        "access_token.\(env.rawValue)"
    }

    func hasToken(for env: GitEnvironment) -> Bool {
        if let _ = try? KeychainService.shared.getPassword(service: keychainService, account: tokenAccount(for: env)) {
            return true
        }
        if let _ = try? KeychainService.shared.getPassword(service: keychainService, account: legacyTokenAccount) {
            return true
        }
        return false
    }

    func disconnect() throws {
        try? KeychainService.shared.deletePassword(service: keychainService, account: tokenAccount(for: selectedEnvironment))
        try? KeychainService.shared.deletePassword(service: keychainService, account: legacyTokenAccount)
    }

    func disconnectAll() {
        try? KeychainService.shared.deletePassword(service: keychainService, account: tokenAccount(for: .dev))
        try? KeychainService.shared.deletePassword(service: keychainService, account: tokenAccount(for: .prod))
        try? KeychainService.shared.deletePassword(service: keychainService, account: legacyTokenAccount)
    }

    func currentAccessToken() -> String? {
        do {
            if let data = try KeychainService.shared.getPassword(service: keychainService, account: tokenAccount(for: selectedEnvironment)) {
                return String(data: data, encoding: .utf8)
            }
            if let data = try KeychainService.shared.getPassword(service: keychainService, account: legacyTokenAccount) {
                return String(data: data, encoding: .utf8)
            }
        } catch {
            logger.error("Keychain read error: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Device Flow

    func beginDeviceFlow(scopes: String = "repo read:user") async throws -> DeviceCode {
        FileLogger.shared.log("beginDeviceFlow called, scopes=\(scopes)")
        guard let clientId else {
            FileLogger.shared.log("ERROR: No client ID configured")
            throw AuthError.missingClientId
        }
        guard let url = URL(string: "https://github.com/login/device/code") else { throw AuthError.invalidURL }

        let encodedScope = scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = "client_id=\(clientId)&scope=\(encodedScope)"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw AuthError.unknown("No HTTP response")
        }
        let responseText = String(data: data, encoding: .utf8) ?? "<no body>"
        FileLogger.shared.log("Device code response status=\(http.statusCode)")

        guard http.statusCode == 200 else {
            throw AuthError.unknown("GitHub error (\(http.statusCode)): \(responseText)")
        }
        return try JSONDecoder().decode(DeviceCode.self, from: data)
    }

    func pollForToken(deviceCode: String, interval: Int) async throws {
        FileLogger.shared.log("pollForToken started, interval=\(interval)")
        guard let clientId else { throw AuthError.missingClientId }
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else { throw AuthError.invalidURL }

        var currentInterval = max(5, interval)
        var pollCount = 0
        while true {
            try await Task.sleep(nanoseconds: UInt64(currentInterval) * 1_000_000_000)
            pollCount += 1

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let body = "client_id=\(clientId)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            req.httpBody = body.data(using: .utf8)
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { continue }

            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let err = obj["error"] as? String {
                switch err {
                case "authorization_pending":
                    continue
                case "slow_down":
                    currentInterval += 5
                    continue
                case "expired_token":
                    throw AuthError.expired
                case "access_denied":
                    throw AuthError.accessDenied
                default:
                    throw AuthError.unknown(err)
                }
            }

            if http.statusCode == 200 {
                do {
                    let token = try JSONDecoder().decode(AccessTokenResponse.self, from: data)
                    let account = tokenAccount(for: selectedEnvironment)
                    try KeychainService.shared.setPassword(Data(token.access_token.utf8), service: keychainService, account: account)
                    logger.info("GitHub token stored in Keychain for env \(self.selectedEnvironment.rawValue)")
                    return
                } catch {
                    let responseText = String(data: data, encoding: .utf8) ?? "<no body>"
                    throw AuthError.unknown("Invalid token response: \(responseText)")
                }
            } else {
                let responseText = String(data: data, encoding: .utf8) ?? "<no body>"
                throw AuthError.unknown("HTTP \(http.statusCode): \(responseText)")
            }
        }
    }

    func openInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - RemoteForgeProvider

    func verifyCredentials() async throws -> String {
        try await fetchCurrentUserLogin()
    }

    func fetchCurrentUserLogin() async throws -> String {
        guard let token = currentAccessToken() else { throw AuthError.notConnected }
        guard let url = URL(string: "https://api.github.com/user") else { throw AuthError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            logger.error("Fetch user failed: \(text)")
            throw AuthError.unknown("Failed to load user")
        }
        struct User: Decodable { let login: String }
        let user = try JSONDecoder().decode(User.self, from: data)
        return user.login
    }

    func listAssignedMergeRequests() async throws -> [ForgeMergeRequest] {
        guard let token = currentAccessToken() else { throw AuthError.notConnected }
        let username = try await fetchCurrentUserLogin()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var all: [ForgeMergeRequest] = []
        var seen = Set<String>()

        func runQuery(_ q: String) async throws {
            let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            guard let url = URL(string: "https://api.github.com/search/issues?q=\(encoded)&sort=updated&order=desc&per_page=50") else {
                throw AuthError.invalidURL
            }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                let text = String(data: data, encoding: .utf8) ?? "<no body>"
                throw AuthError.unknown("GitHub API error: \(text)")
            }
            let response = try decoder.decode(SearchResponse<SearchIssue>.self, from: data)
            for item in response.items {
                let forgeId = ForgeRepository.makeId(accountId: account.id, remoteId: "\(item.id)")
                if seen.contains(forgeId) { continue }
                seen.insert(forgeId)
                all.append(ForgeMergeRequest(
                    id: forgeId,
                    providerAccountId: account.id,
                    providerKind: .github,
                    number: item.number,
                    title: item.title,
                    webURL: item.html_url,
                    isDraft: item.draft ?? false,
                    createdAt: item.created_at,
                    updatedAt: item.updated_at,
                    authorLogin: item.user?.login ?? "",
                    authorAvatarURL: item.user?.avatar_url,
                    repoFullName: item.repoFullName
                ))
            }
        }

        // Authored by user
        try? await runQuery("is:pr is:open author:\(username)")
        // Review requested from user
        try? await runQuery("is:pr is:open review-requested:\(username)")

        return all.sorted { $0.updatedAt > $1.updatedAt }
    }

    func listAssignedIssues() async throws -> [ForgeIssue] {
        guard let token = currentAccessToken() else { throw AuthError.notConnected }
        guard let url = URL(string: "https://api.github.com/issues?filter=assigned&state=open&sort=updated&direction=desc&per_page=50") else {
            throw AuthError.invalidURL
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AuthError.unknown("GitHub API error: \(text)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = try decoder.decode([IssueDTO].self, from: data)

        return items.compactMap { item in
            // /issues returns PRs too; filter by URL.
            if item.html_url.contains("/pull/") { return nil }
            let labels = item.labels.map { lbl in
                ForgeLabel(id: "\(lbl.id)", name: lbl.name, hexColor: lbl.color)
            }
            return ForgeIssue(
                id: ForgeRepository.makeId(accountId: account.id, remoteId: "\(item.id)"),
                providerAccountId: account.id,
                providerKind: .github,
                number: item.number,
                title: item.title,
                webURL: item.html_url,
                createdAt: item.created_at,
                updatedAt: item.updated_at,
                authorLogin: item.user?.login ?? "",
                labels: labels,
                repoFullName: item.repoFullName
            )
        }
    }

    func listRepositories(includeArchived: Bool, includeForks: Bool) async throws -> [ForgeRepository] {
        guard let token = currentAccessToken() else { throw AuthError.notConnected }

        var allRepos: [RepositoryDTO] = []
        var page = 1
        let perPage = 100

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        while true {
            guard let url = URL(string: "https://api.github.com/user/repos?per_page=\(perPage)&page=\(page)&sort=updated&direction=desc") else {
                throw AuthError.invalidURL
            }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw AuthError.unknown("No HTTP response")
            }
            if http.statusCode == 401 { throw AuthError.unknown("Token expired or invalid") }
            guard http.statusCode == 200 else {
                let text = String(data: data, encoding: .utf8) ?? "<no body>"
                throw AuthError.unknown("GitHub API error (\(http.statusCode)): \(text)")
            }
            let repos = try decoder.decode([RepositoryDTO].self, from: data)
            if repos.isEmpty { break }
            allRepos.append(contentsOf: repos)
            if repos.count < perPage { break }
            page += 1
            if page > 20 { break }
        }

        let filtered = allRepos.filter { repo in
            (includeArchived || !repo.archived) && (includeForks || !repo.fork)
        }
        return filtered.map { map(repo: $0) }
    }

    func ciStatus(for repository: ForgeRepository) async throws -> ForgeCIStatus {
        guard repository.providerAccountId == account.id else { return .unknown }
        guard let token = currentAccessToken() else { throw AuthError.notConnected }

        let parts = repository.fullName.split(separator: "/")
        guard parts.count == 2 else { return .unknown }
        let owner = String(parts[0])
        let repoName = String(parts[1])

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repoName)/actions/runs?per_page=1") else {
            throw AuthError.invalidURL
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return .unknown }
        if http.statusCode == 404 { return .noWorkflows }
        guard http.statusCode == 200 else { return .unknown }

        struct RunsResp: Decodable { let workflow_runs: [Run] }
        struct Run: Decodable { let status: String; let conclusion: String? }

        let response = try JSONDecoder().decode(RunsResp.self, from: data)
        guard let run = response.workflow_runs.first else { return .noWorkflows }
        if run.status != "completed" { return .pending }
        switch run.conclusion?.lowercased() {
        case "success": return .success
        case "failure", "timed_out": return .failure
        case "cancelled": return .cancelled
        case "skipped": return .skipped
        default: return .unknown
        }
    }

    // MARK: - Internal DTOs

    private struct SearchResponse<T: Decodable>: Decodable {
        let total_count: Int
        let items: [T]
    }

    private struct UserDTO: Decodable {
        let login: String
        let avatar_url: String?
    }

    private struct SearchIssue: Decodable {
        let id: Int
        let number: Int
        let title: String
        let html_url: String
        let draft: Bool?
        let created_at: Date
        let updated_at: Date
        let user: UserDTO?
        let repository_url: String?

        var repoFullName: String {
            guard let url = repository_url else { return "" }
            let parts = url.split(separator: "/")
            guard parts.count >= 2 else { return "" }
            return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
        }
    }

    private struct IssueDTO: Decodable {
        let id: Int
        let number: Int
        let title: String
        let html_url: String
        let created_at: Date
        let updated_at: Date
        let user: UserDTO?
        let labels: [LabelDTO]
        let repository_url: String?

        struct LabelDTO: Decodable {
            let id: Int
            let name: String
            let color: String
        }

        var repoFullName: String {
            guard let url = repository_url else { return "Unknown" }
            let parts = url.split(separator: "/")
            guard parts.count >= 2 else { return "Unknown" }
            return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
        }
    }

    private struct RepositoryDTO: Decodable {
        let id: Int
        let name: String
        let full_name: String
        let description: String?
        let `private`: Bool
        let html_url: String
        let clone_url: String
        let ssh_url: String?
        let default_branch: String?
        let updated_at: Date
        let pushed_at: Date?
        let language: String?
        let stargazers_count: Int
        let forks_count: Int
        let archived: Bool
        let fork: Bool
    }

    private func map(repo: RepositoryDTO) -> ForgeRepository {
        ForgeRepository(
            id: ForgeRepository.makeId(accountId: account.id, remoteId: "\(repo.id)"),
            providerAccountId: account.id,
            remoteId: "\(repo.id)",
            name: repo.name,
            fullName: repo.full_name,
            description: repo.description,
            isPrivate: repo.`private`,
            webURL: repo.html_url,
            cloneURL: repo.clone_url,
            sshURL: repo.ssh_url,
            defaultBranch: repo.default_branch,
            updatedAt: repo.updated_at,
            pushedAt: repo.pushed_at,
            language: repo.language,
            stars: repo.stargazers_count,
            forks: repo.forks_count,
            isArchived: repo.archived,
            isFork: repo.fork
        )
    }
}
