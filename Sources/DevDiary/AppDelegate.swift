import AppKit
import SwiftUI
import os.log

/// Application delegate handling app lifecycle and setup
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.devdiary", category: "App")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("DevDiary starting...")
        
        // Setup database
        do {
            try DatabaseManager.shared.setup()
            logger.info("Database initialized successfully")
        } catch {
            logger.error("Failed to initialize database: \(error.localizedDescription)")
            // Show alert to user
            showDatabaseError(error)
            return
        }
        
        // Setup status item (menubar)
        StatusItemManager.shared.setup()
        
        // Run repository discovery and start polling
        Task {
            await performInitialSetup()
        }
        
        logger.info("DevDiary started successfully")
    }
    
    private func performInitialSetup() async {
        // Discover repositories
        do {
            let newRepos = try await RepositoryDiscovery.shared.discoverRepositories()
            if newRepos > 0 {
                logger.info("Discovered \(newRepos) new repositories")
            }
        } catch {
            logger.error("Repository discovery failed: \(error.localizedDescription)")
        }
        
        // Start activity tracking (session management)
        ActivityTracker.shared.start()
        
        // Start commit polling
        CommitPoller.shared.start()
        
        // Trigger initial poll
        await CommitPoller.shared.pollNow()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("DevDiary shutting down...")
        
        // Stop tracking
        CommitPoller.shared.stop()
        ActivityTracker.shared.stop()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even when all windows are closed (menubar app)
        return false
    }
    
    // MARK: - Private
    
    private func showDatabaseError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("database.error.title", comment: "Database error alert title")
        alert.informativeText = String(
            format: NSLocalizedString("database.error.message", comment: "Database error alert message"),
            error.localizedDescription
        )
        alert.alertStyle = .critical
        alert.addButton(withTitle: NSLocalizedString("button.quit", comment: "Quit button"))
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }
}
