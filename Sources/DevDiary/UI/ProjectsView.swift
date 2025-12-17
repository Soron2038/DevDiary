import SwiftUI
import AppKit

/// Projects management view
struct ProjectsView: View {
    @State private var projects: [Project] = []
    @State private var projectStats: [UUID: StatisticsService.ProjectStatistics] = [:]
    @State private var selectedProject: Project?
    @State private var isLoading = true
    @State private var showingAddSheet = false
    
    var body: some View {
        HSplitView {
            // Left: Project list
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("projects.title")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "projects.add"))
                    
                    Button(action: refreshProjects) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "projects.refresh"))
                }
                .padding()
                
                Divider()
                
                if projects.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "folder.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("projects.empty")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button("projects.discover") {
                            discoverRepositories()
                        }
                        .padding(.top)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(projects, id: \.id, selection: $selectedProject) { project in
                        ProjectRow(
                            project: project,
                            stats: projectStats[project.id],
                            onToggleTracking: { toggleTracking(project) }
                        )
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 300, maxWidth: 400)
            
            // Right: Project details
            VStack {
                if let project = selectedProject {
                    ProjectDetailView(
                        project: project,
                        stats: projectStats[project.id]
                    )
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "sidebar.left")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("projects.selectProject")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            loadProjects()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddProjectSheet(onAdd: { path in
                addProject(at: path)
            })
        }
    }
    
    // MARK: - Actions
    
    private func loadProjects() {
        isLoading = true
        do {
            projects = try DatabaseManager.shared.getAllProjects()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            // Load stats for each project
            for project in projects {
                if let stats = try? StatisticsService.shared.getProjectStatistics(projectId: project.id) {
                    projectStats[project.id] = stats
                }
            }
            
            isLoading = false
        } catch {
            isLoading = false
        }
    }
    
    private func refreshProjects() {
        loadProjects()
    }
    
    private func discoverRepositories() {
        Task {
            do {
                _ = try await RepositoryDiscovery.shared.discoverRepositories()
                await MainActor.run {
                    loadProjects()
                }
            } catch {
                // Handle error
            }
        }
    }
    
    private func toggleTracking(_ project: Project) {
        var updated = project
        updated.isTracked.toggle()
        
        do {
            try DatabaseManager.shared.updateProject(updated)
            loadProjects()
        } catch {
            // Handle error
        }
    }
    
    private func addProject(at path: String) {
        do {
            _ = try RepositoryDiscovery.shared.addRepository(at: path)
            loadProjects()
        } catch {
            // Handle error
        }
    }
}

// MARK: - Supporting Views

private struct ProjectRow: View {
    let project: Project
    let stats: StatisticsService.ProjectStatistics?
    let onToggleTracking: () -> Void
    
    var body: some View {
        HStack {
            // Tracking toggle
            Button(action: onToggleTracking) {
                Image(systemName: project.isTracked ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(project.isTracked ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let stats = stats, stats.commitCount > 0 {
                    Text("\(stats.commitCount) commits • \(stats.formattedDuration)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(project.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(project.isTracked ? 1.0 : 0.6)
    }
}

private struct ProjectDetailView: View {
    let project: Project
    let stats: StatisticsService.ProjectStatistics?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.title)
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(project.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Spacer()
                    
                    // Open in Finder button
                    Button(action: openInFinder) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "projects.openInFinder"))
                }
                
                // Status
                HStack {
                    Label(
                        project.isTracked ? String(localized: "projects.tracking.on") : String(localized: "projects.tracking.off"),
                        systemImage: project.isTracked ? "eye" : "eye.slash"
                    )
                    .font(.caption)
                    .foregroundColor(project.isTracked ? .green : .secondary)
                }
            }
            .padding()
            
            Divider()
            
            // Statistics
            if let stats = stats {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ProjectStatCard(title: String(localized: "projects.stat.totalTime"), value: stats.formattedDuration)
                    ProjectStatCard(title: String(localized: "projects.stat.commits"), value: "\(stats.commitCount)")
                    ProjectStatCard(title: String(localized: "projects.stat.sessions"), value: "\(stats.sessionCount)")
                    ProjectStatCard(title: String(localized: "projects.stat.additions"), value: "+\(stats.additions)")
                    ProjectStatCard(title: String(localized: "projects.stat.deletions"), value: "-\(stats.deletions)")
                    
                    if let lastActivity = stats.lastActivity {
                        ProjectStatCard(
                            title: String(localized: "projects.stat.lastActivity"),
                            value: lastActivity.formatted(.relative(presentation: .named))
                        )
                    }
                }
                .padding()
            } else {
                VStack {
                    Text("projects.noStats")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            
            Spacer()
        }
    }
    
    private func openInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
    }
}

private struct ProjectStatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

private struct AddProjectSheet: View {
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("projects.add.title")
                .font(.headline)
            
            Text("projects.add.description")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack {
                TextField("projects.add.path", text: $selectedPath)
                    .textFieldStyle(.roundedBorder)
                
                Button("projects.add.browse") {
                    selectFolder()
                }
            }
            
            HStack {
                Button("button.cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("projects.add.confirm") {
                    onAdd(selectedPath)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(selectedPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "projects.add.selectFolder")
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }
}
