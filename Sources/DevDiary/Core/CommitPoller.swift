import Foundation
import os.log

/// Notification names for commit events
extension Notification.Name {
    static let newCommitsDetected = Notification.Name("com.devdiary.newCommitsDetected")
    static let pollingStatusChanged = Notification.Name("com.devdiary.pollingStatusChanged")
}

/// Polls Git repositories for new commits on a regular interval
final class CommitPoller {
    static let shared = CommitPoller()
    
    private let logger = Logger(subsystem: "com.devdiary", category: "Poller")
    private let gitService = GitService.shared
    
    /// Polling interval in seconds (default: 60)
    var pollingInterval: TimeInterval = 60
    
    /// Whether polling is currently active
    private(set) var isPolling = false
    
    /// Cache of last known commit hashes per project
    private var lastKnownCommits: [UUID: String] = [:]
    
    private var pollingTask: Task<Void, Never>?
    
    private init() {}
    
    /// Start polling for new commits
    func start() {
        guard !isPolling else {
            logger.debug("Polling already active")
            return
        }
        
        isPolling = true
        logger.info("Starting commit polling (interval: \(self.pollingInterval)s)")
        
        // Initialize last known commits
        initializeLastKnownCommits()
        
        // Start polling loop
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollRepositories()
                
                try? await Task.sleep(nanoseconds: UInt64(self?.pollingInterval ?? 60) * 1_000_000_000)
            }
        }
        
        NotificationCenter.default.post(name: .pollingStatusChanged, object: nil)
    }
    
    /// Stop polling
    func stop() {
        guard isPolling else { return }
        
        isPolling = false
        pollingTask?.cancel()
        pollingTask = nil
        logger.info("Stopped commit polling")
        
        NotificationCenter.default.post(name: .pollingStatusChanged, object: nil)
    }
    
    /// Manually trigger a poll (useful for testing or manual refresh)
    func pollNow() async {
        await pollRepositories()
    }
    
    // MARK: - Private
    
    private func initializeLastKnownCommits() {
        do {
            let projects = try DatabaseManager.shared.getTrackedProjects()
            for project in projects {
                if let hash = gitService.getLatestCommitHash(at: project.path) {
                    lastKnownCommits[project.id] = hash
                }
            }
            logger.debug("Initialized \(self.lastKnownCommits.count) project commit hashes")
        } catch {
            logger.error("Failed to initialize commit hashes: \(error.localizedDescription)")
        }
    }
    
    private func pollRepositories() async {
        logger.debug("Polling repositories for new commits...")
        
        do {
            let projects = try DatabaseManager.shared.getTrackedProjects()
            var totalNewCommits = 0
            
            for project in projects {
                let newCommits = try await checkForNewCommits(project: project)
                totalNewCommits += newCommits
            }
            
            if totalNewCommits > 0 {
                logger.info("Found \(totalNewCommits) new commits")
                
                // Notify UI on main thread
                let count = totalNewCommits
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .newCommitsDetected,
                        object: nil,
                        userInfo: ["count": count]
                    )
                }
            }
        } catch {
            logger.error("Polling failed: \(error.localizedDescription)")
        }
    }
    
    private func checkForNewCommits(project: Project) async throws -> Int {
        // Check if repository still exists
        guard gitService.isGitRepository(at: project.path) else {
            logger.warning("Repository no longer exists: \(project.name)")
            return 0
        }
        
        // Get current HEAD
        guard let currentHash = gitService.getLatestCommitHash(at: project.path) else {
            return 0
        }
        
        // Check if there are new commits
        let lastKnown = lastKnownCommits[project.id]
        
        if lastKnown == currentHash {
            // No new commits
            return 0
        }
        
        // Get new commits
        let newGitCommits: [GitService.GitCommit]
        if let lastKnown = lastKnown {
            newGitCommits = gitService.getCommitsSince(hash: lastKnown, at: project.path)
        } else {
            // First time - get today's commits only
            let startOfDay = Calendar.current.startOfDay(for: Date())
            newGitCommits = gitService.getCommits(at: project.path, since: startOfDay, limit: 50)
        }
        
        guard !newGitCommits.isEmpty else {
            lastKnownCommits[project.id] = currentHash
            return 0
        }
        
        // Record activity and get session via ActivityTracker
        let session = try ActivityTracker.shared.recordActivity(for: project)
        
        // Save new commits to database
        var savedCount = 0
        for var gitCommit in newGitCommits {
            // Skip if we already have this commit
            if try DatabaseManager.shared.commitExists(hash: gitCommit.hash) {
                continue
            }
            
            // Get commit stats
            let stats = gitService.getCommitStats(hash: gitCommit.hash, at: project.path)
            gitCommit.filesChanged = stats.filesChanged
            gitCommit.additions = stats.additions
            gitCommit.deletions = stats.deletions
            
            // Save to database
            try DatabaseManager.shared.createCommit(
                sessionId: session.id,
                hash: gitCommit.hash,
                message: gitCommit.message,
                author: gitCommit.author,
                timestamp: gitCommit.timestamp,
                filesChanged: gitCommit.filesChanged,
                additions: gitCommit.additions,
                deletions: gitCommit.deletions
            )
            
            savedCount += 1
            logger.debug("Saved commit: \(gitCommit.hash.prefix(7)) - \(gitCommit.message.prefix(50))")
        }
        
        // Update last known commit
        lastKnownCommits[project.id] = currentHash
        
        return savedCount
    }
}
