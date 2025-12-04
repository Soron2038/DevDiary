import AppKit
import SwiftUI

/// Manages the main dashboard window
final class DashboardWindow: NSObject {
    static let shared = DashboardWindow()
    
    private var window: NSWindow?
    private let windowFrameKey = "DashboardWindowFrame"
    
    private override init() {
        super.init()
    }
    
    /// Show the dashboard window
    func show() {
        // For menubar apps, we need to set activation policy temporarily
        NSApp.setActivationPolicy(.regular)
        
        if let window = window {
            // Window exists, bring to front
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create new window
        let contentView = DashboardView()
        let hostingController = NSHostingController(rootView: contentView)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window?.contentViewController = hostingController
        window?.title = "DevDiary"
        window?.minSize = NSSize(width: 700, height: 500)
        window?.isReleasedWhenClosed = false
        window?.delegate = self
        
        // Restore window position or center
        if let frameString = UserDefaults.standard.string(forKey: windowFrameKey) {
            window?.setFrame(from: frameString)
        } else {
            window?.center()
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Close the dashboard window
    func close() {
        window?.close()
    }
    
    /// Check if the window is currently visible
    var isVisible: Bool {
        window?.isVisible ?? false
    }
}

// MARK: - NSWindowDelegate

extension DashboardWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Save window position
        if let frame = window?.frameDescriptor {
            UserDefaults.standard.set(frame, forKey: windowFrameKey)
        }
        // Return to accessory mode when window closes
        NSApp.setActivationPolicy(.accessory)
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Could refresh data here if needed
    }
}
