import SwiftUI
import AppKit

/// Browsing view over remote repositories from all connected forge accounts.
/// Supports per-account filtering, search, clone, and CI status badges.
struct RemoteRepositoriesView: View {
    @State private var repositories: [ForgeRepository] = []
    @State private var localRemoteURLs: Set<String> = []
    @State private var localProjectPaths: [String: String] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showForks = true
    @State private var connectedProviders: [any RemoteForgeProvider] = []
    @State private var selectedAccountId: String? = nil   // nil = All

    @AppStorage("defaultCloneDirectory") private var defaultCloneDirectory = "~/Developer"
    @State private var cloningRepoId: String? = nil
    @State private var cloneError: String?
    @State private var showCloneSuccess = false
    @State private var lastClonedPath: String?

    @State private var ciStatuses: [String: ForgeCIStatus] = [:]
    @State private var repoStatuses: [String: GitService.RepositoryStatus] = [:]

    private var filteredRepositories: [ForgeRepository] {
        var list = repositories
        if let accountId = selectedAccountId {
            list = list.filter { $0.providerAccountId == accountId }
        }
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(search) ||
                $0.fullName.lowercased().contains(search) ||
                ($0.description?.lowercased().contains(search) ?? false)
            }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterBar
                .padding()

            if let error = cloneError {
                banner(error: error)
            }
            if showCloneSuccess, let path = lastClonedPath {
                successBanner(path: path)
            }

            Divider()

            if connectedProviders.isEmpty {
                notConnectedView
            } else if isLoading && repositories.isEmpty {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if filteredRepositories.isEmpty {
                emptyView
            } else {
                repositoryList
            }
        }
        .onAppear { refreshConnectionAndLoad() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshConnectionAndLoad()
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(String(localized: "remote.search"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 200)

            Spacer()

            if connectedProviders.count > 1 {
                accountPicker
            }

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

            Button(action: selectCloneDirectory) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text(cloneDirectoryDisplayName).lineLimit(1).truncationMode(.middle)
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .help(String(localized: "remote.cloneDirectory.tooltip"))
        }
    }

    private var accountPicker: some View {
        Menu {
            Button(String(localized: "remote.allAccounts")) { selectedAccountId = nil }
            Divider()
            ForEach(connectedProviders, id: \.account.id) { provider in
                Button(provider.account.displayName) { selectedAccountId = provider.account.id }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.2")
                Text(selectedAccountDisplay).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.caption)
        }
        .fixedSize()
    }

    private var selectedAccountDisplay: String {
        if let id = selectedAccountId,
           let provider = connectedProviders.first(where: { $0.account.id == id }) {
            return provider.account.displayName
        }
        return String(localized: "remote.allAccounts")
    }

    private func banner(error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(error).font(.caption)
            Spacer()
            Button(action: { cloneError = nil }) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
    }

    private func successBanner(path: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text(String(format: String(localized: "remote.cloneSuccess"), (path as NSString).lastPathComponent))
                .font(.caption)
            Spacer()
            Button(String(localized: "remote.openInFinder")) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            }
            .font(.caption)
            Button(action: { showCloneSuccess = false }) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.green.opacity(0.1))
    }

    // MARK: - States

    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "link.badge.plus").font(.system(size: 48)).foregroundColor(.secondary)
            Text(String(localized: "remote.notConnected")).font(.headline).foregroundColor(.secondary)
            Text(String(localized: "remote.notConnected.hint"))
                .font(.subheadline).foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingView: some View {
        VStack {
            Spacer(); ProgressView()
            Text(String(localized: "remote.loading")).font(.subheadline).foregroundColor(.secondary).padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundColor(.orange)
            Text(message).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button(String(localized: "remote.retry")) { loadRepositories() }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray").font(.system(size: 48)).foregroundColor(.secondary)
            Text(String(localized: "remote.empty")).font(.headline).foregroundColor(.secondary)
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
                ciStatus: ciStatuses[repo.id],
                onOpenInBrowser: { openInBrowser(repo) },
                onClone: { cloneRepository(repo) }
            )
        }
        .listStyle(.plain)
    }

    // MARK: - Loading

    private func refreshConnectionAndLoad() {
        loadLocalProjectURLs()
        connectedProviders = ForgeRegistry.shared.connectedProviders()
        if connectedProviders.isEmpty {
            repositories = []
            return
        }
        if repositories.isEmpty {
            loadRepositories()
        }
    }

    private func loadRepositories() {
        isLoading = true
        errorMessage = nil
        let providers = connectedProviders
        Task {
            var collected: [ForgeRepository] = []
            var firstError: String?
            await withTaskGroup(of: Result<[ForgeRepository], Error>.self) { group in
                for provider in providers {
                    let archived = showArchived
                    let forks = showForks
                    group.addTask {
                        do {
                            let items = try await provider.listRepositories(includeArchived: archived, includeForks: forks)
                            return .success(items)
                        } catch {
                            return .failure(error)
                        }
                    }
                }
                for await result in group {
                    switch result {
                    case .success(let items): collected.append(contentsOf: items)
                    case .failure(let err):
                        if firstError == nil { firstError = err.localizedDescription }
                    }
                }
            }
            let sorted = collected.sorted { $0.updatedAt > $1.updatedAt }
            await MainActor.run {
                self.repositories = sorted
                self.isLoading = false
                if self.repositories.isEmpty, let err = firstError {
                    self.errorMessage = err
                } else {
                    self.errorMessage = nil
                }
                self.loadRepoStatuses(for: sorted)
            }
            await loadCIStatuses(for: sorted)
        }
    }

    private func loadCIStatuses(for repos: [ForgeRepository]) async {
        var result: [String: ForgeCIStatus] = [:]
        // Group by provider so each provider does its own parallel fan-out.
        let byAccount = Dictionary(grouping: repos, by: { $0.providerAccountId })
        for (accountId, list) in byAccount {
            guard let provider = ForgeRegistry.shared.provider(for: accountId) else { continue }
            let statuses = await provider.ciStatuses(for: list)
            result.merge(statuses) { $1 }
        }
        let snapshot = result
        await MainActor.run {
            self.ciStatuses = snapshot
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
            // ignore
        }
    }

    private func getLocalPath(for repo: ForgeRepository) -> String? {
        localProjectPaths[repo.webURL.lowercased()]
    }

    private func isLocallyAvailable(_ repo: ForgeRepository) -> Bool {
        localRemoteURLs.contains(repo.webURL.lowercased())
    }

    private func openInBrowser(_ repo: ForgeRepository) {
        if let url = URL(string: repo.webURL) { NSWorkspace.shared.open(url) }
    }

    private func loadRepoStatuses(for repos: [ForgeRepository]) {
        var statuses: [String: GitService.RepositoryStatus] = [:]
        for repo in repos {
            if let localPath = getLocalPath(for: repo) {
                statuses[repo.id] = GitService.shared.getRepositoryStatus(at: localPath)
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
        let expandedPath = (defaultCloneDirectory as NSString).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: expandedPath)
        if panel.runModal() == .OK, let url = panel.url {
            defaultCloneDirectory = url.path
        }
    }

    private func cloneRepository(_ repo: ForgeRepository) {
        guard cloningRepoId == nil else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "remote.cloneDirectory.select")
        panel.prompt = String(localized: "remote.clone")
        let expandedPath = (defaultCloneDirectory as NSString).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: expandedPath)

        guard panel.runModal() == .OK, let targetURL = panel.url else { return }
        let targetDir = targetURL.path

        cloningRepoId = repo.id
        cloneError = nil
        showCloneSuccess = false

        Task {
            do {
                let clonedPath = try await GitService.shared.cloneRepository(url: repo.cloneURL, to: targetDir)
                _ = try? RepositoryDiscovery.shared.addRepository(at: clonedPath)
                await MainActor.run {
                    self.cloningRepoId = nil
                    self.lastClonedPath = clonedPath
                    self.showCloneSuccess = true
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

// MARK: - Row

private struct RemoteRepositoryRow: View {
    let repository: ForgeRepository
    let isLocallyAvailable: Bool
    let repositoryStatus: GitService.RepositoryStatus?
    let isCloning: Bool
    let ciStatus: ForgeCIStatus?
    let onOpenInBrowser: () -> Void
    let onClone: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: repository.isPrivate ? "lock.fill" : "folder.fill")
                .foregroundColor(repository.isPrivate ? .orange : .accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repository.name).font(.subheadline).fontWeight(.medium)

                    if let status = ciStatus, status != .noWorkflows, status != .unknown {
                        Image(systemName: status.icon)
                            .font(.caption)
                            .foregroundColor(status.color)
                            .help(String(localized: String.LocalizationValue(status.localizationKey)))
                    } else if ciStatus == nil {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    }

                    ProviderBadge(
                        accountId: repository.providerAccountId,
                        kind: ForgeRegistry.shared.account(id: repository.providerAccountId)?.kind ?? .github
                    )

                    if repository.isArchived {
                        Text(String(localized: "remote.archived"))
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(3)
                    }

                    if repository.isFork {
                        Image(systemName: "tuningfork").font(.caption2).foregroundColor(.secondary)
                    }
                }

                if let description = repository.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }

                HStack(spacing: 12) {
                    if isLocallyAvailable {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text(String(localized: "remote.localAvailable"))
                            if let status = repositoryStatus, status.hasRemoteChanges {
                                HStack(spacing: 2) {
                                    if status.ahead > 0 { Text("↑\(status.ahead)").foregroundColor(.orange) }
                                    if status.behind > 0 { Text("↓\(status.behind)").foregroundColor(.blue) }
                                }
                            }
                        }
                        .font(.caption)
                    } else {
                        Label(String(localized: "remote.notLocal"), systemImage: "arrow.down.circle")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    if let language = repository.language {
                        Text(language).font(.caption).foregroundColor(.secondary)
                    }

                    if repository.stars > 0 {
                        Label("\(repository.stars)", systemImage: "star")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if !isLocallyAvailable {
                if isCloning {
                    ProgressView().scaleEffect(0.6).frame(width: 20, height: 20)
                } else {
                    Button(action: onClone) {
                        Image(systemName: "arrow.down.circle").foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1.0 : 0.3)
                    .help(String(localized: "remote.clone"))
                }
            }

            Button(action: onOpenInBrowser) {
                Image(systemName: "arrow.up.right.square").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.0)
            .help(String(localized: "remote.openInBrowser"))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
