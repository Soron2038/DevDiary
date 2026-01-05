import AppKit
import SwiftUI

/// Manages the menubar status item and its popover
final class StatusItemManager: NSObject {
    static let shared = StatusItemManager()
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    
    private override init() {
        super.init()
    }
    
    /// Setup the status item in the menubar
    func setup() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Use SF Symbol for code icon
            button.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "DevDiary")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 420)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.contentViewController = NSHostingController(rootView: MenuBarView())
        
        // Setup event monitor to close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover?.isShown == true {
                self?.closePopover()
            }
        }
        
        // Register keyboard shortcut (⌘⇧D)
        setupKeyboardShortcut()
        
        // Subscribe to notifications for badge updates
        setupNotificationObservers()
    }
    
    /// Toggle the popover visibility
    @objc func togglePopover() {
        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
    
    /// Show the popover
    func showPopover() {
        guard let button = statusItem?.button else { return }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // Make sure the popover window becomes key
        popover?.contentViewController?.view.window?.makeKey()
    }
    
    /// Close the popover
    func closePopover() {
        popover?.performClose(nil)
    }
    
    /// Update the badge count on the status item
    func updateBadge(count: Int) {
        // For now, we just update the tooltip
        // Badge implementation would require custom drawing
        statusItem?.button?.toolTip = count > 0 
            ? String(format: NSLocalizedString("menubar.tooltip.commits", comment: "Tooltip with commit count"), count)
            : NSLocalizedString("menubar.tooltip.noCommits", comment: "Tooltip with no commits")
    }
    
    // MARK: - Private
    
    private func setupKeyboardShortcut() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ⌘⇧D
            if event.modifierFlags.contains([.command, .shift]) && event.charactersIgnoringModifiers == "d" {
                self?.togglePopover()
                return nil
            }
            return event
        }
    }
    
    private func setupNotificationObservers() {
        // Update badge when new commits are detected
        NotificationCenter.default.addObserver(
            forName: .newCommitsDetected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.refreshBadge()
        }
        
        // Update when session changes
        NotificationCenter.default.addObserver(
            forName: .sessionStarted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateSessionIndicator(active: true)
        }
        
        NotificationCenter.default.addObserver(
            forName: .sessionEnded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateSessionIndicator(active: false)
        }
    }
    
    private func refreshBadge() {
        do {
            let count = try DatabaseManager.shared.getTodayCommitCount()
            updateBadge(count: count)
        } catch {
            // Silently fail
        }
    }
    
    private func updateSessionIndicator(active: Bool) {
        // Could update icon or add visual indicator for active session
        // For now, just refresh tooltip
        refreshBadge()
    }
    
    deinit {
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
