import Foundation
import AppKit
import os.log

/// GitHub integration using OAuth 2.0 Device Authorization Grant (Device Flow)
/// No client secret required; users authorize in the browser with a user code.
final class GitHubService {
    static let shared = GitHubService()
    private let logger = Logger(subsystem: "com.devdiary", category: "GitHub")

    // Keychain constants
    private let keychainService = "DevDiary.GitHub"
    private let tokenAccount = "access_token"

    // OAuth constants
    // Provide client id via environment variable during development.
    // e.g., export DEV_DIARY_GITHUB_CLIENT_ID=xxxxxxxxxxxxxxxxxxxx
    private var clientId: String? {
        let env = ProcessInfo.processInfo.environment
        return env["DEV_DIARY_GITHUB_CLIENT_ID"] ?? env["GITHUB_CLIENT_ID"]
    }

    private init() {}

    // MARK: - Public API

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
        (try? KeychainService.shared.getPassword(service: keychainService, account: tokenAccount)) != nil
    }

    func disconnect() throws {
        try KeychainService.shared.deletePassword(service: keychainService, account: tokenAccount)
    }

    func currentAccessToken() -> String? {
        do {
            if let data = try KeychainService.shared.getPassword(service: keychainService, account: tokenAccount) {
                return String(data: data, encoding: .utf8)
            }
        } catch {
            logger.error("Keychain read error: \(error.localizedDescription)")
        }
        return nil
    }

    // Begin the device flow: returns instructions for the user
    func beginDeviceFlow(scopes: String = "repo read:user") async throws -> DeviceCode {
        guard let clientId else { throw AuthError.missingClientId }
        guard let url = URL(string: "https://github.com/login/device/code") else { throw AuthError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = "client_id=\(clientId)&scope=\(scopes)"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            logger.error("Device code request failed: \(text)")
            throw AuthError.unknown("Failed to start device flow")
        }
        let device = try JSONDecoder().decode(DeviceCode.self, from: data)
        return device
    }

    // Poll for access token, saves token in Keychain on success
    func pollForToken(deviceCode: String, interval: Int) async throws {
        guard let clientId else { throw AuthError.missingClientId }
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else { throw AuthError.invalidURL }

        var currentInterval = max(5, interval)
        while true {
            try await Task.sleep(nanoseconds: UInt64(currentInterval) * 1_000_000_000)

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let body = "client_id=\(clientId)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            req.httpBody = body.data(using: .utf8)
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { continue }

            if http.statusCode == 200 {
                // Success
                let token = try JSONDecoder().decode(AccessTokenResponse.self, from: data)
                try KeychainService.shared.setPassword(Data(token.access_token.utf8), service: keychainService, account: tokenAccount)
                logger.info("GitHub token stored in Keychain")
                return
            } else {
                // Error payload is JSON: {"error":"authorization_pending"|"slow_down"|"expired_token"|"access_denied"}
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let err = obj["error"] as? String {
                    switch err {
                    case "authorization_pending":
                        continue // keep polling
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
                let text = String(data: data, encoding: .utf8) ?? "<no body>"
                throw AuthError.unknown("HTTP \(http.statusCode): \(text)")
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
}
