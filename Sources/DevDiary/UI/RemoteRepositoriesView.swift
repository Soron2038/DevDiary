import SwiftUI
import AppKit

/// View displaying GitHub repositories with local availability status
struct RemoteRepositoriesView: View {
    @State private var repositories: [GitHubRepository] = []
    @State private var localRemoteURLs: Set<String> = [] // Normalized URLs of local projects
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showForks = true
    
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
            }
            .padding()
            
            Divider()
            
            // Content
            if !GitHubService.shared.isConnected {
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
            loadLocalProjectURLs()
            if GitHubService.shared.isConnected {
                loadRepositories()
            }
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
                onOpenInBrowser: { openInBrowser(repo) }
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
                }
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
            for project in projects {
                if let remoteURL = GitService.shared.getRemoteURL(at: project.path),
                   let normalized = GitService.shared.normalizeToHTTPS(remoteURL) {
                    urls.insert(normalized.lowercased())
                }
            }
            localRemoteURLs = urls
        } catch {
            // Ignore errors
        }
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
}

// MARK: - Repository Row

private struct RemoteRepositoryRow: View {
    let repository: GitHubRepository
    let isLocallyAvailable: Bool
    let onOpenInBrowser: () -> Void
    
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
                    // Local status
                    if isLocallyAvailable {
                        Label(String(localized: "remote.localAvailable"), systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
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
