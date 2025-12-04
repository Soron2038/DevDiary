import Foundation
import os.log

/// Discovers Git repositories in common development directories
final class RepositoryDiscovery {
    static let shared = RepositoryDiscovery()
    
    private let logger = Logger(subsystem: "com.devdiary", category: "Discovery")
    private let gitService = GitService.shared
    private let maxDepth = 3
    
    /// Standard directories to scan for Git repositories
    private var searchDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Code"),
            home.appendingPathComponent("Documents"),
            // Also check iCloud Drive code folders
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Code")
        ]
    }
    
    private init() {}
    
    /// Discover Git repositories and add new ones to the database
    /// - Returns: Number of newly discovered repositories
    @discardableResult
    func discoverRepositories() async throws -> Int {
        logger.info("Starting repository discovery...")
        
        let existingPaths = try await getExistingProjectPaths()
        var newCount = 0
        
        for directory in searchDirectories {
            guard FileManager.default.fileExists(atPath: directory.path) else {
                logger.debug("Skipping non-existent directory: \(directory.path)")
                continue
            }
            
            logger.debug("Scanning: \(directory.path)")
            let repos = findGitRepositories(in: directory, currentDepth: 0)
            
            for repoPath in repos {
                if !existingPaths.contains(repoPath) {
                    let name = gitService.getRepositoryName(at: repoPath)
                    do {
                        try DatabaseManager.shared.createProject(name: name, path: repoPath)
                        newCount += 1
                        logger.info("Discovered new repository: \(name)")
                    } catch {
                        logger.error("Failed to save repository \(name): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        logger.info("Discovery complete. Found \(newCount) new repositories.")
        return newCount
    }
    
    /// Manually add a repository at the given path
    /// - Parameter path: Path to the Git repository
    /// - Returns: The created Project, or nil if invalid/duplicate
    func addRepository(at path: String) throws -> Project? {
        // Normalize path
        let normalizedPath = (path as NSString).expandingTildeInPath
        
        // Check if it's a valid Git repository
        guard gitService.isGitRepository(at: normalizedPath) else {
            logger.warning("Not a Git repository: \(normalizedPath)")
            return nil
        }
        
        // Get the repository root (in case path is a subdirectory)
        let repoRoot = gitService.getRepositoryRoot(at: normalizedPath) ?? normalizedPath
        
        // Check if already exists
        if let existing = try DatabaseManager.shared.getProject(byPath: repoRoot) {
            logger.debug("Repository already exists: \(existing.name)")
            return existing
        }
        
        // Create new project
        let name = gitService.getRepositoryName(at: repoRoot)
        let project = try DatabaseManager.shared.createProject(name: name, path: repoRoot)
        logger.info("Added repository: \(name)")
        
        return project
    }
    
    // MARK: - Private
    
    private func getExistingProjectPaths() async throws -> Set<String> {
        let projects = try DatabaseManager.shared.getAllProjects()
        return Set(projects.map { $0.path })
    }
    
    private func findGitRepositories(in directory: URL, currentDepth: Int) -> [String] {
        guard currentDepth <= maxDepth else { return [] }
        
        var repositories: [String] = []
        let fileManager = FileManager.default
        
        // Check if this directory is a Git repository
        let gitDir = directory.appendingPathComponent(".git")
        if fileManager.fileExists(atPath: gitDir.path) {
            // Found a repository, don't recurse further
            return [directory.path]
        }
        
        // Recurse into subdirectories
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        
        for item in contents {
            guard let isDirectory = try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDirectory == true else {
                continue
            }
            
            // Skip common non-project directories
            let name = item.lastPathComponent
            if shouldSkipDirectory(name) {
                continue
            }
            
            repositories.append(contentsOf: findGitRepositories(in: item, currentDepth: currentDepth + 1))
        }
        
        return repositories
    }
    
    private func shouldSkipDirectory(_ name: String) -> Bool {
        let skipPatterns = [
            "node_modules",
            ".build",
            "build",
            "DerivedData",
            "Pods",
            ".git",
            "vendor",
            "Carthage",
            ".swiftpm"
        ]
        return skipPatterns.contains(name)
    }
}
