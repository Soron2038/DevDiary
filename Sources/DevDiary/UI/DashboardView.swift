import SwiftUI

/// Main dashboard view with tab navigation
struct DashboardView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("dashboard.tab.today", systemImage: "calendar")
                }
                .tag(0)
            
            HistoryView()
                .tabItem {
                    Label("dashboard.tab.history", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)
            
            ProjectsView()
                .tabItem {
                    Label("dashboard.tab.projects", systemImage: "folder")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Label("dashboard.tab.settings", systemImage: "gear")
                }
                .tag(3)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
