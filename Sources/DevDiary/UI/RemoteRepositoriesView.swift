import SwiftUI
import AppKit

/// View displaying GitHub repositories with local availability status
struct RemoteRepositoriesView: View {
    @State private var repositories: [GitHubRepository] = []
    @State private var localRemoteURLs: Set<String> = [] // Normalized URLs of local projects
    @State private var localProjectPaths: [String: String] = [:] // Normalized URL -> local path
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showForks = true
    @State private var isConnected = false
    
    // Clone state
    @AppStorage("defaultCloneDirectory") private var defaultCloneDirectory = "~/Developer"
    @State private var cloningRepoId: Int? = nil
    @State private var cloneError: String?
    @State private var showCloneSuccess = false
    @State private var lastClonedPath: String?
    
    // CI status
    @State private var workflowStatuses: [Int: GitHubService.WorkflowRunStatus] = [:]
    @State private var isLoadingStatuses = false
    
    // Git status for local repos
    @State private var repoStatuses: [Int: GitService.RepositoryStatus] = [:]
    
    private var filteredRepositories: [GitHubRepository] {
        if searchText.isEmpty {
            return repositories
        }
        let search = searchText.lowercased()
        return repositories.filter {
            $0.name.lowercased().contains(search) ||
            $0.fullName.lowercased().contains(search) ||
            ($0.description?.lowercased().contains(search) ?? false)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with search and filters
            HStack {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(String(localized: "remote.search"), text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .frame(maxWidth: 200)
                
                Spacer()
                
                // Filters
                Toggle(String(localized: "remote.showForks"), isOn: $showForks)
                    .toggleStyle(.checkbox)
                    .onChange(of: showForks) { _ in loadRepositories() }
                
                Toggle(String(localized: "remote.showArchived"), isOn: $showArchived)
                    .toggleStyle(.checkbox)
                    .onChange(of: showArchived) { _ in loadRepositories() }
                
                Button(action: loadRepositories) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(String(localized: "remote.refresh"))
                
                // Clone directory picker
                Button(action: selectCloneDirectory) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text(cloneDirectoryDisplayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .help(String(localized: "remote.cloneDirectory.tooltip"))
            }
            .padding()
            
            // Clone status banner
            if let error = cloneError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button(action: { cloneError = nil }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
            }
            
            if showCloneSuccess, let path = lastClonedPath {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(String(format: String(localized: "remote.cloneSuccess"), (path as NSString).lastPathComponent))
                        .font(.caption)
                    Spacer()
                    Button(String(localized: "remote.openInFinder")) {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                    }
                    .font(.caption)
                    Button(action: { showCloneSuccess = false }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
            }
            
            Divider()
            
            // Content
            if !isConnected {
                notConnectedView
            } else if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if filteredRepositories.isEmpty {
                emptyView
            } else {
                repositoryList
            }
        }
        .onAppear {
            checkConnectionAndLoad()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkConnectionAndLoad()
        }
    }
    
    private func checkConnectionAndLoad() {
        loadLocalProjectURLs()
        let connected = GitHubService.shared.isConnected
        if connected != isConnected {
            isConnected = connected
        }
        if connected && repositories.isEmpty {
            loadRepositories()
        }
    }
    
    // MARK: - Subviews
    
    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("remote.notConnected")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("remote.notConnected.hint")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
            Text("remote.loading")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "remote.retry")) {
                loadRepositories()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("remote.empty")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var repositoryList: some View {
        List(filteredRepositories) { repo in
            RemoteRepositoryRow(
                repository: repo,
                isLocallyAvailable: isLocallyAvailable(repo),
                repositoryStatus: repoStatuses[repo.id],
                isCloning: cloningRepoId == repo.id,
                workflowStatus: workflowStatuses[repo.id],
                onOpenInBrowser: { openInBrowser(repo) },
                onClone: { cloneRepository(repo) },
                onOpenActions: { openActionsPage(repo) }
            )
        }
        .listStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func loadRepositories() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let repos = try await GitHubService.shared.fetchRepositories(
                    includeArchived: showArchived,
                    includeForks: showForks
                )
                await MainActor.run {
                    self.repositories = repos
                    self.isLoading = false
                    // Load git status for local repos
                    self.loadRepoStatuses(for: repos)
                }
                // Load workflow statuses in background
                await loadWorkflowStatuses(for: repos)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadLocalProjectURLs() {
        do {
            let projects = try DatabaseManager.shared.getAllProjects()
            var urls = Set<String>()
            var paths: [String: String] = [:]
            for project in projects {
                if let remoteURL = GitService.shared.getRemoteURL(at: project.path),
                   let normalized = GitService.shared.normalizeToHTTPS(remoteURL) {
                    let normalizedLower = normalized.lowercased()
                    urls.insert(normalizedLower)
                    paths[normalizedLower] = project.path
                }
            }
            localRemoteURLs = urls
            localProjectPaths = paths
        } catch {
            // Ignore errors
        }
    }
    
    private func getLocalPath(for repo: GitHubRepository) -> String? {
        let repoURL = repo.htmlURL.lowercased()
        return localProjectPaths[repoURL]
    }
    
    private func isLocallyAvailable(_ repo: GitHubRepository) -> Bool {
        let repoURL = repo.htmlURL.lowercased()
        return localRemoteURLs.contains(repoURL)
    }
    
    private func openInBrowser(_ repo: GitHubRepository) {
        if let url = URL(string: repo.htmlURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openActionsPage(_ repo: GitHubRepository) {
        if let url = URL(string: "\(repo.htmlURL)/actions") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func loadWorkflowStatuses(for repos: [GitHubRepository]) async {
        await MainActor.run {
            isLoadingStatuses = true
        }
        
        let statuses = await GitHubService.shared.fetchWorkflowStatuses(for: repos)
        
        await MainActor.run {
            self.workflowStatuses = statuses
            self.isLoadingStatuses = false
        }
    }
    
    private func loadRepoStatuses(for repos: [GitHubRepository]) {
        var statuses: [Int: GitService.RepositoryStatus] = [:]
        
        for repo in repos {
            if let localPath = getLocalPath(for: repo) {
                let status = GitService.shared.getRepositoryStatus(at: localPath)
                statuses[repo.id] = status
            }
        }
        
        repoStatuses = statuses
    }
    
    private var cloneDirectoryDisplayName: String {
        let path = (defaultCloneDirectory as NSString).expandingTildeInPath
        return (path as NSString).lastPathComponent
    }
    
    private func selectCloneDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "remote.cloneDirectory.select")
        
        // Start at current clone directory
        let expandedPath = (defaultCloneDirectory as NSString).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: expandedPath)
        
        if panel.runModal() == .OK, let url = panel.url {
            defaultCloneDirectory = url.path
        }
    }
    
    private func cloneRepository(_ repo: GitHubRepository) {
        guard cloningRepoId == nil else { return } // Already cloning
        
        cloningRepoId = repo.id
        cloneError = nil
        showCloneSuccess = false
        
        Task {
            do {
                let targetDir = (defaultCloneDirectory as NSString).expandingTildeInPath
                let clonedPath = try await GitService.shared.cloneRepository(
                    url: repo.cloneURL,
                    to: targetDir
                )
                
                // Add to tracked projects
                _ = try? RepositoryDiscovery.shared.addRepository(at: clonedPath)
                
                await MainActor.run {
                    self.cloningRepoId = nil
                    self.lastClonedPath = clonedPath
                    self.showCloneSuccess = true
                    // Refresh local URLs to show new status
                    self.loadLocalProjectURLs()
                }
            } catch {
                await MainActor.run {
                    self.cloningRepoId = nil
                    self.cloneError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Repository Row

private struct RemoteRepositoryRow: View {
    let repository: GitHubRepository
    let isLocallyAvailable: Bool
    let repositoryStatus: GitService.RepositoryStatus?
    let isCloning: Bool
    let workflowStatus: GitHubService.WorkflowRunStatus?
    let onOpenInBrowser: () -> Void
    let onClone: () -> Void
    let onOpenActions: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Visibility icon
            Image(systemName: repository.isPrivate ? "lock.fill" : "folder.fill")
                .foregroundColor(repository.isPrivate ? .orange : .accentColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repository.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // CI Status badge
                    if let status = workflowStatus {
                        if status != .noWorkflows && status != .unknown {
                            Button(action: onOpenActions) {
                                Image(systemName: status.icon)
                                    .font(.caption)
                                    .foregroundColor(status.color)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: String.LocalizationValue(status.localizationKey)))
                        }
                    } else {
                        // Loading indicator while fetching status
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    }
                    
                    if repository.isArchived {
                        Text("archived")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(3)
                    }
                    
                    if repository.isFork {
                        Image(systemName: "tuningfork")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let description = repository.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 12) {
                    // Local status with ahead/behind
                    if isLocallyAvailable {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(String(localized: "remote.localAvailable"))
                            
                            // Show ahead/behind status
                            if let status = repositoryStatus, status.hasRemoteChanges {
                                HStack(spacing: 2) {
                                    if status.ahead > 0 {
                                        Text("↑\(status.ahead)")
                                            .foregroundColor(.orange)
                                    }
                                    if status.behind > 0 {
                                        Text("↓\(status.behind)")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                        .font(.caption)
                    } else {
                        Label(String(localized: "remote.notLocal"), systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Language
                    if let language = repository.language {
                        Text(language)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Stars
                    if repository.stargazersCount > 0 {
                        Label("\(repository.stargazersCount)", systemImage: "star")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Clone button (for non-local repos)
            if !isLocallyAvailable {
                if isCloning {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 20, height: 20)
                } else {
                    Button(action: onClone) {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1.0 : 0.3)
                    .help(String(localized: "remote.clone"))
                }
            }
            
            // Open in browser button (visible on hover)
            Button(action: onOpenInBrowser) {
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.0)
            .help(String(localized: "remote.openInBrowser"))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
