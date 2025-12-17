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
