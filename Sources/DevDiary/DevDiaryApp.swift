import SwiftUI

@main
struct DevDiaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty settings scene - we're a menubar-only app
        Settings {
            EmptyView()
        }
    }
}
