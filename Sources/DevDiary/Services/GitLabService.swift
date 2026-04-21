import Foundation
import os.log

/// GitLab integration via Personal Access Token (PAT).
/// One instance per configured GitLab `ForgeAccount` (hosted on gitlab.com or self-hosted).
///
/// Required PAT scopes: `read_api read_user read_repository`.
final class GitLabService: RemoteForgeProvider {
    static let keychainService = "DevDiary.GitLab"

    let account: ForgeAccount
    private let logger = Logger(subsystem: "com.devdiary", category: "GitLab")

    init(account: ForgeAccount) {
        self.account = account
    }

    // MARK: - Errors

    enum GitLabError: LocalizedError {
        case notConnected
        case invalidBaseURL
        case invalidToken
        case http(Int, String)
        case instanceUnreachable
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Not connected to GitLab."
            case .invalidBaseURL: return "Invalid GitLab base URL."
            case .invalidToken: return "GitLab token is invalid or expired."
            case .http(let code, let body): return "GitLab API error (\(code)): \(body)"
            case .instanceUnreachable: return "GitLab instance is not reachable."
            case .unknown(let msg): return msg
            }
        }
    }

    // MARK: - Token

    var isConnected: Bool {
        (try? KeychainService.shared.getPassword(service: Self.keychainService, account: account.keychainAccount)) != nil
    }

    func storeToken(_ pat: String) throws {
        let trimmed = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        try KeychainService.shared.setPassword(
            Data(trimmed.utf8),
            service: Self.keychainService,
            account: account.keychainAccount
        )
    }

    func currentToken() -> String? {
        guard let data = try? KeychainService.shared.getPassword(service: Self.keychainService, account: account.keychainAccount) ?? nil,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    func disconnect() throws {
        try KeychainService.shared.deletePassword(service: Self.keychainService, account: account.keychainAccount)
    }

    // MARK: - Public API

    /// Check if a base URL points to a reachable GitLab instance (no auth required).
    static func probeInstance(at baseURL: URL) async throws {
        guard let url = baseURL.appendingPathComponent("api/v4/version") as URL? else {
            throw GitLabError.invalidBaseURL
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            // Any response is fine — /version returns 401 when unauth'd on most instances,
            // but the fact that we got a response proves it's reachable.
            guard let http = resp as? HTTPURLResponse else { throw GitLabError.instanceUnreachable }
            // 401 means GitLab is there but needs auth; 200 works too.
            guard http.statusCode == 200 || http.statusCode == 401 else {
                throw GitLabError.http(http.statusCode, "unexpected status from /version")
            }
        } catch {
            throw GitLabError.instanceUnreachable
        }
    }

    /// Verify a PAT against a GitLab instance and return the username.
    /// Used before the account is persisted, so baseURL + token are passed in.
    static func verify(baseURL: URL, token: String) async throws -> (username: String, displayName: String) {
        let url = baseURL.appendingPathComponent("api/v4/user")
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        req.timeoutInterval = 10

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw GitLabError.instanceUnreachable
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw GitLabError.invalidToken
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitLabError.http(http.statusCode, body)
        }
        struct UserDTO: Decodable {
            let username: String
            let name: String?
        }
        let user = try JSONDecoder().decode(UserDTO.self, from: data)
        return (user.username, user.name ?? user.username)
    }

    func verifyCredentials() async throws -> String {
        guard let token = currentToken() else { throw GitLabError.notConnected }
        let (username, _) = try await Self.verify(baseURL: account.baseURL, token: token)
        return username
    }

    func listAssignedMergeRequests() async throws -> [ForgeMergeRequest] {
        let decoder = makeDateDecoder()
        let items: [MergeRequestDTO] = try await get(
            path: "api/v4/merge_requests",
            query: [
                "scope": "assigned_to_me",
                "state": "opened",
                "order_by": "updated_at",
                "per_page": "50"
            ],
            decoder: decoder
        )
        return items.map { dto in
            ForgeMergeRequest(
                id: ForgeRepository.makeId(accountId: account.id, remoteId: "\(dto.id)"),
                providerAccountId: account.id,
                providerKind: .gitlab,
                number: dto.iid,
                title: dto.title,
                webURL: dto.web_url,
                isDraft: dto.draft ?? dto.work_in_progress ?? false,
                createdAt: dto.created_at,
                updatedAt: dto.updated_at,
                authorLogin: dto.author?.username ?? "",
                authorAvatarURL: dto.author?.avatar_url,
                repoFullName: dto.references?.full?.components(separatedBy: "!").first
                    ?? "project-\(dto.project_id)"
            )
        }
    }

    func listAssignedIssues() async throws -> [ForgeIssue] {
        let decoder = makeDateDecoder()
        let items: [IssueDTO] = try await get(
            path: "api/v4/issues",
            query: [
                "scope": "assigned_to_me",
                "state": "opened",
                "order_by": "updated_at",
                "per_page": "50"
            ],
            decoder: decoder
        )
        return items.map { dto in
            let labels = dto.labels.enumerated().map { (idx, name) in
                ForgeLabel(id: "\(dto.id)-\(idx)", name: name, hexColor: "808080")
            }
            return ForgeIssue(
                id: ForgeRepository.makeId(accountId: account.id, remoteId: "\(dto.id)"),
                providerAccountId: account.id,
                providerKind: .gitlab,
                number: dto.iid,
                title: dto.title,
                webURL: dto.web_url,
                createdAt: dto.created_at,
                updatedAt: dto.updated_at,
                authorLogin: dto.author?.username ?? "",
                labels: labels,
                repoFullName: dto.references?.full?.components(separatedBy: "#").first
                    ?? "project-\(dto.project_id)"
            )
        }
    }

    func listRepositories(includeArchived: Bool, includeForks: Bool) async throws -> [ForgeRepository] {
        let decoder = makeDateDecoder()
        var all: [ProjectDTO] = []
        var page = 1
        let perPage = 100
        while true {
            let items: [ProjectDTO] = try await get(
                path: "api/v4/projects",
                query: [
                    "membership": "true",
                    "order_by": "last_activity_at",
                    "sort": "desc",
                    "per_page": "\(perPage)",
                    "page": "\(page)",
                    "archived": includeArchived ? "" : "false"
                ].filter { !$0.value.isEmpty },
                decoder: decoder
            )
            if items.isEmpty { break }
            all.append(contentsOf: items)
            if items.count < perPage { break }
            page += 1
            if page > 20 { break }
        }
        let filtered = all.filter { proj in
            includeForks || proj.forked_from_project == nil
        }
        return filtered.map { map(project: $0) }
    }

    func ciStatus(for repository: ForgeRepository) async throws -> ForgeCIStatus {
        guard repository.providerAccountId == account.id else { return .unknown }
        guard let _ = currentToken() else { throw GitLabError.notConnected }

        let decoder = makeDateDecoder()
        var query: [String: String] = ["per_page": "1"]
        if let branch = repository.defaultBranch {
            query["ref"] = branch
        }
        do {
            let pipelines: [PipelineDTO] = try await get(
                path: "api/v4/projects/\(repository.remoteId)/pipelines",
                query: query,
                decoder: decoder
            )
            guard let pipeline = pipelines.first else { return .noWorkflows }
            switch pipeline.status.lowercased() {
            case "success": return .success
            case "failed": return .failure
            case "running", "pending", "created", "waiting_for_resource", "preparing", "scheduled":
                return .pending
            case "canceled", "cancelled": return .cancelled
            case "skipped": return .skipped
            default: return .unknown
            }
        } catch GitLabError.http(404, _) {
            return .noWorkflows
        }
    }

    // MARK: - HTTP Helper

    private func makeDateDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func get<T: Decodable>(
        path: String,
        query: [String: String] = [:],
        decoder: JSONDecoder
    ) async throws -> T {
        guard let token = currentToken() else { throw GitLabError.notConnected }
        var components = URLComponents(url: account.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw GitLabError.invalidBaseURL }

        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw GitLabError.instanceUnreachable
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw GitLabError.invalidToken
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitLabError.http(http.statusCode, body)
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - DTOs

    private struct UserRef: Decodable {
        let username: String?
        let avatar_url: String?
    }

    private struct References: Decodable {
        /// e.g. "group/project!15" for an MR, "group/project#42" for an issue.
        let full: String?
    }

    private struct MergeRequestDTO: Decodable {
        let id: Int
        let iid: Int
        let project_id: Int
        let title: String
        let web_url: String
        let draft: Bool?
        let work_in_progress: Bool?
        let created_at: Date
        let updated_at: Date
        let author: UserRef?
        let references: References?
    }

    private struct IssueDTO: Decodable {
        let id: Int
        let iid: Int
        let project_id: Int
        let title: String
        let web_url: String
        let created_at: Date
        let updated_at: Date
        let author: UserRef?
        let labels: [String]
        let references: References?
    }

    private struct ProjectDTO: Decodable {
        let id: Int
        let name: String
        let path_with_namespace: String
        let description: String?
        let visibility: String           // public | internal | private
        let web_url: String
        let http_url_to_repo: String
        let ssh_url_to_repo: String?
        let default_branch: String?
        let last_activity_at: Date
        let star_count: Int?
        let forks_count: Int?
        let archived: Bool
        let forked_from_project: ForkRef?

        struct ForkRef: Decodable {}
    }

    private struct PipelineDTO: Decodable {
        let id: Int
        let status: String
        let web_url: String?
        let updated_at: Date?
    }

    private func map(project: ProjectDTO) -> ForgeRepository {
        ForgeRepository(
            id: ForgeRepository.makeId(accountId: account.id, remoteId: "\(project.id)"),
            providerAccountId: account.id,
            remoteId: "\(project.id)",
            name: project.name,
            fullName: project.path_with_namespace,
            description: project.description,
            isPrivate: project.visibility != "public",
            webURL: project.web_url,
            cloneURL: project.http_url_to_repo,
            sshURL: project.ssh_url_to_repo,
            defaultBranch: project.default_branch,
            updatedAt: project.last_activity_at,
            pushedAt: project.last_activity_at,
            language: nil,
            stars: project.star_count ?? 0,
            forks: project.forks_count ?? 0,
            isArchived: project.archived,
            isFork: project.forked_from_project != nil
        )
    }
}
