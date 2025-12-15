import SwiftUI
import AppKit

/// Tab selection for Projects view
enum ProjectsTab: String, CaseIterable {
    case local
    case remote
}

/// Projects container view with tab picker
struct ProjectsView: View {
    @State private var selectedTab: ProjectsTab = .local
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("projects.tab.local").tag(ProjectsTab.local)
                Text("projects.tab.remote").tag(ProjectsTab.remote)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .padding(.vertical, 8)
            
            Divider()
            
            // Content based on selected tab
            switch selectedTab {
            case .local:
                LocalProjectsView()
            case .remote:
                RemoteRepositoriesView()
            }
        }
    }
}

/// Local projects management view
struct LocalProjectsView: View {
    @State private var projects: [Project] = []
    @State private var projectStats: [UUID: StatisticsService.ProjectStatistics] = [:]
    @State private var repoStatuses: [UUID: GitService.RepositoryStatus] = [:]
    @State private var selectedProject: Project?
    @State private var isLoading = true
    @State private var showingAddSheet = false
    @State private var showingRemoveAlert = false
    @State private var projectToRemove: Project?
    
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
                    
                    Button(action: {
                        if let selected = selectedProject {
                            projectToRemove = selected
                            showingRemoveAlert = true
                        }
                    }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedProject == nil)
                    .help(String(localized: "projects.remove.tooltip"))
                    
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
                            repoStatus: repoStatuses[project.id],
                            onToggleTracking: { toggleTracking(project) },
                            onRemove: {
                                projectToRemove = project
                                showingRemoveAlert = true
                            }
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
        .alert(String(localized: "projects.remove.confirm.title"), isPresented: $showingRemoveAlert, presenting: projectToRemove) { project in
            Button(String(localized: "button.cancel"), role: .cancel) {}
            Button(String(localized: "projects.remove.confirm.delete"), role: .destructive) {
                removeProject(project)
            }
        } message: { _ in
            Text(String(localized: "projects.remove.confirm.message"))
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
            
            // Load repository statuses in background
            loadRepoStatuses()
        } catch {
            isLoading = false
        }
    }
    
    private func refreshProjects() {
        // Fetch from remotes first for accurate status
        Task {
            for project in projects {
                GitService.shared.fetchRemote(at: project.path)
            }
            await MainActor.run {
                loadProjects()
            }
        }
    }
    
    private func loadRepoStatuses() {
        Task {
            var statuses: [UUID: GitService.RepositoryStatus] = [:]
            for project in projects {
                let status = GitService.shared.getRepositoryStatus(at: project.path)
                statuses[project.id] = status
            }
            await MainActor.run {
                self.repoStatuses = statuses
            }
        }
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
    
    private func removeProject(_ project: Project) {
        do {
            try DatabaseManager.shared.deleteProject(project)
            if selectedProject?.id == project.id {
                selectedProject = nil
            }
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
    let repoStatus: GitService.RepositoryStatus?
    let onToggleTracking: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            // Tracking toggle
            Button(action: onToggleTracking) {
                Image(systemName: project.isTracked ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(project.isTracked ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // Repository status badge
                    if let status = repoStatus, !status.isEmpty {
                        Text(status.displayString)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(statusBackgroundColor(status))
                            .foregroundColor(statusForegroundColor(status))
                            .cornerRadius(4)
                    }
                }
                
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
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label(String(localized: "projects.remove"), systemImage: "trash")
            }
        }
    }
    
    private func statusBackgroundColor(_ status: GitService.RepositoryStatus) -> Color {
        if status.hasUncommittedChanges {
            return Color.orange.opacity(0.2)  // Uncommitted changes
        } else if status.behind > 0 {
            return Color.blue.opacity(0.2)    // Behind: needs pull
        } else if status.ahead > 0 {
            return Color.green.opacity(0.2)   // Ahead: needs push
        }
        return Color.secondary.opacity(0.2)
    }
    
    private func statusForegroundColor(_ status: GitService.RepositoryStatus) -> Color {
        if status.hasUncommittedChanges {
            return .orange
        } else if status.behind > 0 {
            return .blue
        } else if status.ahead > 0 {
            return .green
        }
        return .secondary
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
