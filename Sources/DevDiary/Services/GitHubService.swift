import Foundation
import AppKit
import SwiftUI
import os.log

/// GitHub integration using OAuth 2.0 Device Authorization Grant (Device Flow)
/// No client secret required; users authorize in the browser with a user code.
final class GitHubService {
    static let shared = GitHubService()
    private let logger = Logger(subsystem: "com.devdiary", category: "GitHub")

    enum GitEnvironment: String, CaseIterable {
        case dev, prod
    }

    // Keychain constants
    private let keychainService = "DevDiary.GitHub"
    private let legacyTokenAccount = "access_token"

    private let envDefaultsKey = "GitEnvironment"

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
        // 1) User-configured per-environment Client ID
        if let configured = UserDefaults.standard.string(forKey: "GitHubClientID.\(env.rawValue)"), !configured.isEmpty {
            return configured
        }
        // 2) Environment variables
        let procEnv = ProcessInfo.processInfo.environment
        let perEnvKey = env == .dev ? "DEV_DIARY_GITHUB_CLIENT_ID_DEV" : "DEV_DIARY_GITHUB_CLIENT_ID_PROD"
        return procEnv[perEnvKey] ?? procEnv["DEV_DIARY_GITHUB_CLIENT_ID"] ?? procEnv["GITHUB_CLIENT_ID"]
    }

    private init() {}

    // MARK: - Public API

    func saveClientId(_ value: String?) {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "GitHubClientID.\(selectedEnvironment.rawValue)"
        UserDefaults.standard.set(trimmed, forKey: key)
    }

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
            case .unknown(let msg):
                return msg
            }
        }
    }

    var isConnected: Bool {
        hasToken(for: selectedEnvironment)
    }

    private func tokenAccount(for env: GitEnvironment) -> String {
        "access_token.\(env.rawValue)"
    }

    func hasToken(for env: GitEnvironment) -> Bool {
        // Check per-env token first, fallback to legacy
        if let _ = try? KeychainService.shared.getPassword(service: keychainService, account: tokenAccount(for: env)) {
            return true
        }
        if let _ = try? KeychainService.shared.getPassword(service: keychainService, account: legacyTokenAccount) {
            return true
        }
        return false
    }

    func disconnect() throws {
        // Delete token for current environment and legacy
        try? KeychainService.shared.deletePassword(service: keychainService, account: tokenAccount(for: selectedEnvironment))
        try? KeychainService.shared.deletePassword(service: keychainService, account: legacyTokenAccount)
    }

    func disconnectAll() {
        // Remove tokens for both envs and legacy
        try? KeychainService.shared.deletePassword(service: keychainService, account: tokenAccount(for: .dev))
        try? KeychainService.shared.deletePassword(service: keychainService, account: tokenAccount(for: .prod))
        try? KeychainService.shared.deletePassword(service: keychainService, account: legacyTokenAccount)
    }

    func currentAccessToken() -> String? {
        do {
            // Prefer current environment token
            if let data = try KeychainService.shared.getPassword(service: keychainService, account: tokenAccount(for: selectedEnvironment)) {
                return String(data: data, encoding: .utf8)
            }
            // Fallback to legacy account
            if let data = try KeychainService.shared.getPassword(service: keychainService, account: legacyTokenAccount) {
                return String(data: data, encoding: .utf8)
            }
        } catch {
            logger.error("Keychain read error: \(error.localizedDescription)")
        }
        return nil
    }

    // Begin the device flow: returns instructions for the user
    func beginDeviceFlow(scopes: String = "repo read:user") async throws -> DeviceCode {
        FileLogger.shared.log("beginDeviceFlow called, scopes=\(scopes)")
        guard let clientId else {
            FileLogger.shared.log("ERROR: No client ID configured")
            throw AuthError.missingClientId
        }
        FileLogger.shared.log("Using clientId: \(clientId.prefix(8))...")
        guard let url = URL(string: "https://github.com/login/device/code") else { throw AuthError.invalidURL }

        // URL-encode the scope (spaces → %20)
        let encodedScope = scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes
        FileLogger.shared.log("Encoded scope: \(encodedScope)")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = "client_id=\(clientId)&scope=\(encodedScope)"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        FileLogger.shared.log("Sending POST to \(url.absoluteString)")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            FileLogger.shared.log("ERROR: No HTTP response object")
            throw AuthError.unknown("No HTTP response")
        }
        let responseText = String(data: data, encoding: .utf8) ?? "<no body>"
        FileLogger.shared.log("Response status=\(http.statusCode), body=\(responseText)")
        logger.info("Device code response (\(http.statusCode)): \(responseText)")
        
        guard http.statusCode == 200 else {
            FileLogger.shared.log("ERROR: Non-200 status")
            logger.error("Device code request failed: \(responseText)")
            throw AuthError.unknown("GitHub error (\(http.statusCode)): \(responseText)")
        }
        do {
            let device = try JSONDecoder().decode(DeviceCode.self, from: data)
            FileLogger.shared.log("SUCCESS: Got device code, user_code=\(device.user_code)")
            return device
        } catch {
            FileLogger.shared.log("ERROR decoding DeviceCode: \(error)")
            throw error
        }
    }

    // Poll for access token, saves token in Keychain on success
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
            
            let responseText = String(data: data, encoding: .utf8) ?? "<no body>"
            FileLogger.shared.log("Poll #\(pollCount): status=\(http.statusCode), body=\(responseText)")

            // GitHub returns 200 for BOTH success AND pending/error states!
            // First check if this is an error response
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let err = obj["error"] as? String {
                FileLogger.shared.log("Poll #\(pollCount): error=\(err)")
                switch err {
                case "authorization_pending":
                    continue // keep polling - user hasn't authorized yet
                case "slow_down":
                    currentInterval += 5
                    FileLogger.shared.log("Slowing down, new interval=\(currentInterval)")
                    continue
                case "expired_token":
                    throw AuthError.expired
                case "access_denied":
                    throw AuthError.accessDenied
                default:
                    throw AuthError.unknown(err)
                }
            }
            
            // No error field - try to decode the token
            if http.statusCode == 200 {
                do {
                    let token = try JSONDecoder().decode(AccessTokenResponse.self, from: data)
                    FileLogger.shared.log("SUCCESS: Got access token")
                    let account = tokenAccount(for: selectedEnvironment)
                    try KeychainService.shared.setPassword(Data(token.access_token.utf8), service: keychainService, account: account)
                    logger.info("GitHub token stored in Keychain for env \(self.selectedEnvironment.rawValue)")
                    return
                } catch {
                    FileLogger.shared.log("Failed to decode token response: \(error)")
                    throw AuthError.unknown("Invalid token response: \(responseText)")
                }
            } else {
                throw AuthError.unknown("HTTP \(http.statusCode): \(responseText)")
            }
        }
    }

    // Fetch current user login to show connected identity
    func fetchCurrentUserLogin() async throws -> String {
        guard let token = currentAccessToken() else { throw AuthError.unknown("No token") }
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

    // Open verification URI in the user's default browser
    func openInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Workflow Status
    
    /// Status of the latest GitHub Actions workflow run
    enum WorkflowRunStatus: String {
        case success
        case failure
        case pending      // queued, in_progress, waiting
        case cancelled
        case skipped
        case unknown
        case noWorkflows  // Repository has no workflows
        
        var color: Color {
            switch self {
            case .success: return .green
            case .failure: return .red
            case .pending: return .orange
            case .cancelled, .skipped: return .gray
            case .unknown, .noWorkflows: return .secondary
            }
        }
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .failure: return "xmark.circle.fill"
            case .pending: return "clock.fill"
            case .cancelled: return "nosign"
            case .skipped: return "arrow.right.circle"
            case .unknown: return "questionmark.circle"
            case .noWorkflows: return "minus.circle"
            }
        }
        
        var localizationKey: String {
            "workflow.status.\(rawValue)"
        }
    }
    
    /// Fetch the status of the latest workflow run for a repository
    func fetchLatestWorkflowStatus(owner: String, repo: String) async throws -> WorkflowRunStatus {
        guard let token = currentAccessToken() else { throw AuthError.unknown("Not connected to GitHub") }
        
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/actions/runs?per_page=1") else {
            throw AuthError.invalidURL
        }
        
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw AuthError.unknown("No HTTP response")
        }
        
        // 404 means repo might not have actions enabled or doesn't exist
        if http.statusCode == 404 {
            return .noWorkflows
        }
        
        guard http.statusCode == 200 else {
            return .unknown
        }
        
        // Parse response
        struct WorkflowRunsResponse: Decodable {
            let total_count: Int
            let workflow_runs: [WorkflowRun]
        }
        
        struct WorkflowRun: Decodable {
            let status: String       // queued, in_progress, completed, etc.
            let conclusion: String?  // success, failure, cancelled, skipped, etc. (only when completed)
        }
        
        let response = try JSONDecoder().decode(WorkflowRunsResponse.self, from: data)
        
        if response.workflow_runs.isEmpty {
            return .noWorkflows
        }
        
        let run = response.workflow_runs[0]
        
        // If not completed, it's pending
        if run.status != "completed" {
            return .pending
        }
        
        // Map conclusion to status
        switch run.conclusion?.lowercased() {
        case "success":
            return .success
        case "failure", "timed_out":
            return .failure
        case "cancelled":
            return .cancelled
        case "skipped":
            return .skipped
        default:
            return .unknown
        }
    }
    
    /// Fetch workflow statuses for multiple repositories in parallel
    func fetchWorkflowStatuses(for repositories: [GitHubRepository]) async -> [Int: WorkflowRunStatus] {
        var statuses: [Int: WorkflowRunStatus] = [:]
        
        await withTaskGroup(of: (Int, WorkflowRunStatus).self) { group in
            for repo in repositories {
                group.addTask {
                    let parts = repo.fullName.split(separator: "/")
                    guard parts.count == 2 else { return (repo.id, .unknown) }
                    let owner = String(parts[0])
                    let repoName = String(parts[1])
                    
                    do {
                        let status = try await self.fetchLatestWorkflowStatus(owner: owner, repo: repoName)
                        return (repo.id, status)
                    } catch {
                        return (repo.id, .unknown)
                    }
                }
            }
            
            for await (repoId, status) in group {
                statuses[repoId] = status
            }
        }
        
        return statuses
    }
    
    // MARK: - Pull Requests API
    
    /// Fetch open pull requests for the current user (authored or review requested)
    func fetchUserPullRequests() async throws -> [GitHubPullRequest] {
        guard let token = currentAccessToken() else { throw AuthError.unknown("Not connected to GitHub") }
        
        // Get current username first
        let username = try await fetchCurrentUserLogin()
        
        // Search for PRs authored by user OR where review is requested
        let query = "is:pr is:open author:\(username) OR is:pr is:open review-requested:\(username)"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        
        guard let url = URL(string: "https://api.github.com/search/issues?q=\(encodedQuery)&sort=updated&order=desc&per_page=50") else {
            throw AuthError.invalidURL
        }
        
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw AuthError.unknown("No HTTP response")
        }
        
        guard http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            logger.error("Fetch PRs failed: \(text)")
            throw AuthError.unknown("GitHub API error (\(http.statusCode))")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let response = try decoder.decode(GitHubSearchResponse<GitHubPullRequest>.self, from: data)
        return response.items
    }
    
    // MARK: - Issues API
    
    /// Fetch issues assigned to the current user
    func fetchAssignedIssues() async throws -> [GitHubIssue] {
        guard let token = currentAccessToken() else { throw AuthError.unknown("Not connected to GitHub") }
        
        guard let url = URL(string: "https://api.github.com/issues?filter=assigned&state=open&sort=updated&direction=desc&per_page=50") else {
            throw AuthError.invalidURL
        }
        
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw AuthError.unknown("No HTTP response")
        }
        
        guard http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            logger.error("Fetch issues failed: \(text)")
            throw AuthError.unknown("GitHub API error (\(http.statusCode))")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // Filter out pull requests (GitHub returns PRs as issues too)
        let allIssues = try decoder.decode([GitHubIssue].self, from: data)
        return allIssues.filter { issue in
            // PRs have a pull_request key, but our model doesn't include it
            // We check the HTML URL instead - PRs have /pull/ in the URL
            !issue.htmlURL.contains("/pull/")
        }
    }
    
    // MARK: - Repository API
    
    /// Fetch all repositories for the authenticated user
    /// - Parameters:
    ///   - includeArchived: Whether to include archived repos (default: false)
    ///   - includeForks: Whether to include forked repos (default: true)
    /// - Returns: Array of repositories sorted by last update
    func fetchRepositories(includeArchived: Bool = false, includeForks: Bool = true) async throws -> [GitHubRepository] {
        guard let token = currentAccessToken() else { throw AuthError.unknown("Not connected to GitHub") }
        
        var allRepos: [GitHubRepository] = []
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
            
            if http.statusCode == 401 {
                throw AuthError.unknown("Token expired or invalid")
            }
            
            guard http.statusCode == 200 else {
                let text = String(data: data, encoding: .utf8) ?? "<no body>"
                logger.error("Fetch repos failed: \(text)")
                throw AuthError.unknown("GitHub API error (\(http.statusCode))")
            }
            
            let repos = try decoder.decode([GitHubRepository].self, from: data)
            
            if repos.isEmpty {
                break
            }
            
            allRepos.append(contentsOf: repos)
            
            // GitHub returns fewer items than perPage when we've reached the last page
            if repos.count < perPage {
                break
            }
            
            page += 1
            
            // Safety limit to prevent infinite loops
            if page > 20 {
                logger.warning("Reached page limit while fetching repositories")
                break
            }
        }
        
        // Filter based on parameters
        var filtered = allRepos
        if !includeArchived {
            filtered = filtered.filter { !$0.isArchived }
        }
        if !includeForks {
            filtered = filtered.filter { !$0.isFork }
        }
        
        return filtered
    }
}
