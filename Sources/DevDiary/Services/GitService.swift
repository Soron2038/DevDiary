import Foundation
import os.log

/// Service for Git operations using shell commands
final class GitService {
    static let shared = GitService()
    
    private let logger = Logger(subsystem: "com.devdiary", category: "Git")
    
    private init() {}
    
    // MARK: - Repository Info
    
    /// Check if a path is a Git repository
    func isGitRepository(at path: String) -> Bool {
        let result = runGitCommand(["rev-parse", "--is-inside-work-tree"], in: path)
        return result.success && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }
    
    /// Get the repository name (folder name)
    func getRepositoryName(at path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
    
    /// Get the root path of the repository
    func getRepositoryRoot(at path: String) -> String? {
        let result = runGitCommand(["rev-parse", "--show-toplevel"], in: path)
        guard result.success else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Get the current branch name
    func getCurrentBranch(at path: String) -> String? {
        let result = runGitCommand(["branch", "--show-current"], in: path)
        guard result.success else { return nil }
        let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }
    
    /// Get the latest commit hash
    func getLatestCommitHash(at path: String) -> String? {
        let result = runGitCommand(["rev-parse", "HEAD"], in: path)
        guard result.success else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Commits
    
    /// Parsed commit data from git log
    struct GitCommit {
        let hash: String
        let message: String
        let author: String
        let timestamp: Date
        var filesChanged: Int = 0
        var additions: Int = 0
        var deletions: Int = 0
    }
    
    /// Get commits from the repository
    /// - Parameters:
    ///   - path: Repository path
    ///   - since: Only commits after this date (optional)
    ///   - limit: Maximum number of commits to return
    /// - Returns: Array of commits, newest first
    func getCommits(at path: String, since: Date? = nil, limit: Int = 100) -> [GitCommit] {
        var args = [
            "log",
            "--format=%H%n%s%n%an%n%aI%n---COMMIT_END---",
            "-n", "\(limit)"
        ]
        
        if let since = since {
            let formatter = ISO8601DateFormatter()
            args.append("--since=\(formatter.string(from: since))")
        }
        
        let result = runGitCommand(args, in: path)
        guard result.success else { return [] }
        
        return parseCommits(result.output)
    }
    
    /// Get commits that are newer than a specific commit hash
    func getCommitsSince(hash: String, at path: String, limit: Int = 50) -> [GitCommit] {
        let args = [
            "log",
            "--format=%H%n%s%n%an%n%aI%n---COMMIT_END---",
            "\(hash)..HEAD",
            "-n", "\(limit)"
        ]
        
        let result = runGitCommand(args, in: path)
        guard result.success else { return [] }
        
        return parseCommits(result.output)
    }
    
    /// Get file statistics for a commit (additions, deletions, files changed)
    func getCommitStats(hash: String, at path: String) -> (filesChanged: Int, additions: Int, deletions: Int) {
        let result = runGitCommand(["show", "--stat", "--format=", hash], in: path)
        guard result.success else { return (0, 0, 0) }
        
        // Parse the last line which contains summary like "3 files changed, 10 insertions(+), 5 deletions(-)"
        let lines = result.output.components(separatedBy: .newlines)
        guard let summaryLine = lines.last(where: { $0.contains("changed") }) else {
            return (0, 0, 0)
        }
        
        var filesChanged = 0
        var additions = 0
        var deletions = 0
        
        // Parse "X file(s) changed"
        if let match = summaryLine.range(of: #"(\d+) files? changed"#, options: .regularExpression) {
            let numStr = summaryLine[match].components(separatedBy: " ").first ?? "0"
            filesChanged = Int(numStr) ?? 0
        }
        
        // Parse "X insertion(s)"
        if let match = summaryLine.range(of: #"(\d+) insertions?"#, options: .regularExpression) {
            let numStr = summaryLine[match].components(separatedBy: " ").first ?? "0"
            additions = Int(numStr) ?? 0
        }
        
        // Parse "X deletion(s)"
        if let match = summaryLine.range(of: #"(\d+) deletions?"#, options: .regularExpression) {
            let numStr = summaryLine[match].components(separatedBy: " ").first ?? "0"
            deletions = Int(numStr) ?? 0
        }
        
        return (filesChanged, additions, deletions)
    }
    
    /// Get the configured user name for commits
    func getUserName(at path: String) -> String? {
        let result = runGitCommand(["config", "user.name"], in: path)
        guard result.success else { return nil }
        let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
    
    // MARK: - Remote URLs
    
    /// Get the remote URL for origin (or specified remote)
    func getRemoteURL(at path: String, remote: String = "origin") -> String? {
        let result = runGitCommand(["remote", "get-url", remote], in: path)
        guard result.success else { return nil }
        let url = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }
    
    /// Convert a git remote URL to HTTPS format for browser access
    /// Handles: git@github.com:user/repo.git -> https://github.com/user/repo
    ///          https://github.com/user/repo.git -> https://github.com/user/repo
    func normalizeToHTTPS(_ remoteURL: String) -> String? {
        var url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove .git suffix if present
        if url.hasSuffix(".git") {
            url = String(url.dropLast(4))
        }
        
        // Convert SSH format: git@github.com:user/repo -> https://github.com/user/repo
        if url.hasPrefix("git@") {
            // git@github.com:user/repo
            let withoutPrefix = url.dropFirst(4) // "github.com:user/repo"
            if let colonIndex = withoutPrefix.firstIndex(of: ":") {
                let host = withoutPrefix[..<colonIndex]
                let path = withoutPrefix[withoutPrefix.index(after: colonIndex)...]
                return "https://\(host)/\(path)"
            }
        }
        
        // Already HTTPS or HTTP
        if url.hasPrefix("https://") || url.hasPrefix("http://") {
            return url
        }
        
        return nil
    }
    
    /// Get the GitHub URL for a specific commit
    /// Returns nil if not a GitHub repository or no remote configured
    func getGitHubCommitURL(hash: String, at path: String) -> URL? {
        guard let remoteURL = getRemoteURL(at: path),
              let httpsURL = normalizeToHTTPS(remoteURL),
              httpsURL.contains("github.com") else {
            return nil
        }
        return URL(string: "\(httpsURL)/commit/\(hash)")
    }
    
    /// Check if a repository has a GitHub remote
    func hasGitHubRemote(at path: String) -> Bool {
        guard let remoteURL = getRemoteURL(at: path) else { return false }
        return remoteURL.contains("github.com")
    }
    
    // MARK: - Repository Status
    
    /// Combined status for a repository
    struct RepositoryStatus {
        let modifiedFiles: Int      // Uncommitted changes (modified, added, deleted)
        let stagedFiles: Int        // Files staged for commit
        let untrackedFiles: Int     // New untracked files
        let ahead: Int              // Commits ahead of remote
        let behind: Int             // Commits behind remote
        
        var hasUncommittedChanges: Bool {
            modifiedFiles > 0 || stagedFiles > 0
        }
        
        var hasRemoteChanges: Bool {
            ahead > 0 || behind > 0
        }
        
        var totalChanges: Int {
            modifiedFiles + stagedFiles
        }
        
        /// Display string for the status badge
        var displayString: String {
            var parts: [String] = []
            
            // Uncommitted changes (most important)
            if hasUncommittedChanges {
                parts.append("\(totalChanges) ×") // × for modified
            }
            
            // Remote status
            if ahead > 0 { parts.append("↑\(ahead)") }
            if behind > 0 { parts.append("↓\(behind)") }
            
            return parts.joined(separator: " ")
        }
        
        var isEmpty: Bool {
            !hasUncommittedChanges && !hasRemoteChanges
        }
    }
    
    /// Get comprehensive repository status including uncommitted changes and remote status
    func getRepositoryStatus(at path: String) -> RepositoryStatus {
        var modified = 0
        var staged = 0
        var untracked = 0
        var ahead = 0
        var behind = 0
        
        // Get working directory status
        let statusResult = runGitCommand(["status", "--porcelain"], in: path)
        if statusResult.success {
            let lines = statusResult.output.components(separatedBy: .newlines)
            for line in lines where !line.isEmpty {
                guard line.count >= 2 else { continue }
                let index = line.index(line.startIndex, offsetBy: 0)
                let workTree = line.index(line.startIndex, offsetBy: 1)
                let indexStatus = line[index]
                let workTreeStatus = line[workTree]
                
                // Untracked
                if indexStatus == "?" {
                    untracked += 1
                    continue
                }
                
                // Staged changes (index)
                if indexStatus != " " && indexStatus != "?" {
                    staged += 1
                }
                
                // Unstaged changes (work tree)
                if workTreeStatus != " " && workTreeStatus != "?" {
                    modified += 1
                }
            }
        }
        
        // Get ahead/behind status
        let revListResult = runGitCommand(["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], in: path)
        if revListResult.success {
            let output = revListResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = output.split(separator: "\t")
            if parts.count == 2 {
                behind = Int(parts[0]) ?? 0
                ahead = Int(parts[1]) ?? 0
            }
        }
        
        return RepositoryStatus(
            modifiedFiles: modified,
            stagedFiles: staged,
            untrackedFiles: untracked,
            ahead: ahead,
            behind: behind
        )
    }
    
    /// Fetch from remote to update refs
    func fetchRemote(at path: String, remote: String = "origin") {
        _ = runGitCommand(["fetch", remote, "--quiet"], in: path)
    }
    
    // MARK: - Clone
    
    /// Clone a repository to a target directory
    /// - Parameters:
    ///   - url: The clone URL (HTTPS or SSH)
    ///   - targetDirectory: The parent directory where the repo will be cloned
    ///   - name: Optional custom name for the cloned folder (defaults to repo name)
    /// - Returns: The full path to the cloned repository
    func cloneRepository(url: String, to targetDirectory: String, name: String? = nil) async throws -> String {
        // Determine the folder name from URL if not provided
        let folderName: String
        if let customName = name, !customName.isEmpty {
            folderName = customName
        } else {
            // Extract repo name from URL: https://github.com/user/repo.git -> repo
            var repoName = URL(string: url)?.lastPathComponent ?? "repository"
            if repoName.hasSuffix(".git") {
                repoName = String(repoName.dropLast(4))
            }
            folderName = repoName
        }
        
        let targetPath = (targetDirectory as NSString).appendingPathComponent(folderName)
        
        // Check if target already exists
        if FileManager.default.fileExists(atPath: targetPath) {
            throw CloneError.targetExists(targetPath)
        }
        
        // Ensure parent directory exists
        try FileManager.default.createDirectory(atPath: targetDirectory, withIntermediateDirectories: true)
        
        // Run git clone
        let result = await runGitClone(url: url, targetPath: targetPath)
        
        if result.success {
            return targetPath
        } else {
            throw CloneError.cloneFailed(result.output)
        }
    }
    
    enum CloneError: LocalizedError {
        case targetExists(String)
        case cloneFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .targetExists(let path):
                return "Target folder already exists: \(path)"
            case .cloneFailed(let output):
                return "Clone failed: \(output)"
            }
        }
    }
    
    private func runGitClone(url: String, targetPath: String) async -> (success: Bool, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["clone", url, targetPath]
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let success = process.terminationStatus == 0
                    
                    continuation.resume(returning: (success, output))
                } catch {
                    continuation.resume(returning: (false, error.localizedDescription))
                }
            }
        }
    }
    
    // MARK: - Private
    
    private func parseCommits(_ output: String) -> [GitCommit] {
        let commitBlocks = output.components(separatedBy: "---COMMIT_END---")
        var commits: [GitCommit] = []
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        for block in commitBlocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
            
            guard lines.count >= 4 else { continue }
            
            let hash = lines[0]
            let message = lines[1]
            let author = lines[2]
            let dateString = lines[3]
            
            guard !hash.isEmpty,
                  let timestamp = dateFormatter.date(from: dateString) else { continue }
            
            commits.append(GitCommit(
                hash: hash,
                message: message,
                author: author,
                timestamp: timestamp
            ))
        }
        
        return commits
    }
    
    private func runGitCommand(_ arguments: [String], in directory: String) -> (success: Bool, output: String) {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let success = process.terminationStatus == 0
            
            if !success {
                logger.debug("Git command failed: git \(arguments.joined(separator: " ")) in \(directory)")
            }
            
            return (success, output)
        } catch {
            logger.error("Failed to run git command: \(error.localizedDescription)")
            return (false, "")
        }
    }
}
