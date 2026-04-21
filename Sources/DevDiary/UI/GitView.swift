import SwiftUI
import AppKit

/// Aggregated view across all connected forge providers: assigned pull/merge
/// requests on the left, assigned issues on the right. Replaces the old
/// GitHub-only tab.
struct GitView: View {
    @State private var mergeRequests: [ForgeMergeRequest] = []
    @State private var issues: [ForgeIssue] = []
    @State private var isLoadingMRs = false
    @State private var isLoadingIssues = false
    @State private var errorMessage: String?
    @State private var connectedProviders: [any RemoteForgeProvider] = []
    @State private var showTokenExpiredAlert = false

    /// Triggered from the empty state to let the parent open the Accounts sheet.
    var onOpenAccounts: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error).font(.caption)
                    Spacer()
                    Button(action: { errorMessage = nil }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
            }

            if connectedProviders.isEmpty {
                notConnectedView
            } else {
                contentView
            }
        }
        .onAppear { refreshConnectionAndLoad() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshConnectionAndLoad()
        }
        .alert(String(localized: "git.tokenExpired.title"), isPresented: $showTokenExpiredAlert) {
            Button(String(localized: "button.ok")) {
                refreshConnectionAndLoad()
            }
        } message: {
            Text(String(localized: "git.tokenExpired.message"))
        }
    }

    private func refreshConnectionAndLoad() {
        connectedProviders = ForgeRegistry.shared.connectedProviders()
        if connectedProviders.isEmpty {
            mergeRequests = []
            issues = []
            return
        }
        if mergeRequests.isEmpty && issues.isEmpty {
            loadAll()
        }
    }

    // MARK: - Content

    private var contentView: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: String(localized: "git.prs.title"),
                    count: mergeRequests.count,
                    isLoading: isLoadingMRs,
                    onRefresh: loadMergeRequests
                )
                Divider()
                if isLoadingMRs && mergeRequests.isEmpty {
                    loadingView
                } else if mergeRequests.isEmpty {
                    emptyView(icon: "arrow.triangle.pull", message: String(localized: "git.prs.empty"))
                } else {
                    List(mergeRequests) { mr in
                        MergeRequestRow(request: mr)
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 300)

            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: String(localized: "git.issues.title"),
                    count: issues.count,
                    isLoading: isLoadingIssues,
                    onRefresh: loadIssues
                )
                Divider()
                if isLoadingIssues && issues.isEmpty {
                    loadingView
                } else if issues.isEmpty {
                    emptyView(icon: "exclamationmark.circle", message: String(localized: "git.issues.empty"))
                } else {
                    List(issues) { issue in
                        IssueRow(issue: issue)
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 300)
        }
    }

    private func sectionHeader(title: String, count: Int, isLoading: Bool, onRefresh: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.headline)
            if !isLoading {
                Text("\(count)").font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onRefresh) {
                if isLoading {
                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help(String(localized: "git.refresh"))
        }
        .padding()
    }

    // MARK: - States

    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(String(localized: "git.notConnected"))
                .font(.headline)
                .foregroundColor(.secondary)
            Text(String(localized: "git.notConnected.hint"))
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
            if let onOpenAccounts {
                Button(String(localized: "git.openAccounts")) { onOpenAccounts() }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack { Spacer(); ProgressView(); Spacer() }.frame(maxWidth: .infinity)
    }

    private func emptyView(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon).font(.system(size: 36)).foregroundColor(.secondary)
            Text(message).font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading

    private func loadAll() {
        loadMergeRequests()
        loadIssues()
    }

    private func loadMergeRequests() {
        isLoadingMRs = true
        errorMessage = nil
        let providers = connectedProviders
        Task {
            var collected: [ForgeMergeRequest] = []
            var authFailure = false
            await withTaskGroup(of: Result<[ForgeMergeRequest], Error>.self) { group in
                for provider in providers {
                    group.addTask {
                        do { return .success(try await provider.listAssignedMergeRequests()) }
                        catch { return .failure(error) }
                    }
                }
                for await result in group {
                    switch result {
                    case .success(let items): collected.append(contentsOf: items)
                    case .failure(let err): if isAuthError(err) { authFailure = true }
                    }
                }
            }
            let sorted = collected.sorted { $0.updatedAt > $1.updatedAt }
            await MainActor.run {
                self.mergeRequests = sorted
                self.isLoadingMRs = false
                if authFailure { self.showTokenExpiredAlert = true }
            }
        }
    }

    private func loadIssues() {
        isLoadingIssues = true
        let providers = connectedProviders
        Task {
            var collected: [ForgeIssue] = []
            var authFailure = false
            await withTaskGroup(of: Result<[ForgeIssue], Error>.self) { group in
                for provider in providers {
                    group.addTask {
                        do { return .success(try await provider.listAssignedIssues()) }
                        catch { return .failure(error) }
                    }
                }
                for await result in group {
                    switch result {
                    case .success(let items): collected.append(contentsOf: items)
                    case .failure(let err): if isAuthError(err) { authFailure = true }
                    }
                }
            }
            let sorted = collected.sorted { $0.updatedAt > $1.updatedAt }
            await MainActor.run {
                self.issues = sorted
                self.isLoadingIssues = false
                if authFailure { self.showTokenExpiredAlert = true }
            }
        }
    }

    private func isAuthError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("401") || msg.contains("403") || msg.contains("expired") || msg.contains("invalid")
    }
}

// MARK: - Rows

private struct MergeRequestRow: View {
    let request: ForgeMergeRequest
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.pull")
                .foregroundColor(request.isDraft ? .secondary : .green)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(request.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    ProviderBadge(accountId: request.providerAccountId, kind: request.providerKind)

                    if request.isDraft {
                        Text(String(localized: "git.draft"))
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(3)
                    }
                }

                HStack(spacing: 8) {
                    Text(request.repoFullName).font(.caption).foregroundColor(.secondary)
                    Text("\(request.kindLabel) #\(request.number)")
                        .font(.caption).foregroundColor(.secondary)
                    Text(request.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(action: openInBrowser) {
                Image(systemName: "arrow.up.right.square").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.0)
            .help(String(localized: "git.openInBrowser"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .onTapGesture(count: 2) { openInBrowser() }
    }

    private func openInBrowser() {
        if let url = URL(string: request.webURL) { NSWorkspace.shared.open(url) }
    }
}

private struct IssueRow: View {
    let issue: ForgeIssue
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(.green)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(issue.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    ProviderBadge(accountId: issue.providerAccountId, kind: issue.providerKind)
                }

                HStack(spacing: 8) {
                    Text(issue.repoFullName).font(.caption).foregroundColor(.secondary)
                    Text("#\(issue.number)").font(.caption).foregroundColor(.secondary)

                    ForEach(issue.labels.prefix(3)) { label in
                        Text(label.name)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(label.swiftUIColor.opacity(0.3))
                            .foregroundColor(label.swiftUIColor)
                            .cornerRadius(3)
                    }
                    if issue.labels.count > 3 {
                        Text("+\(issue.labels.count - 3)").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button(action: openInBrowser) {
                Image(systemName: "arrow.up.right.square").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.0)
            .help(String(localized: "git.openInBrowser"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .onTapGesture(count: 2) { openInBrowser() }
    }

    private func openInBrowser() {
        if let url = URL(string: issue.webURL) { NSWorkspace.shared.open(url) }
    }
}

/// Small badge identifying which account a row came from.
struct ProviderBadge: View {
    let accountId: String
    let kind: ForgeKind

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label).font(.caption2)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(backgroundColor.opacity(0.18))
        .foregroundColor(backgroundColor)
        .cornerRadius(3)
    }

    private var icon: String {
        switch kind {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return "triangle.righthalf.filled"
        }
    }

    private var label: String {
        if let account = ForgeRegistry.shared.account(id: accountId) {
            return account.displayName
        }
        return kind.rawValue
    }

    private var backgroundColor: Color {
        switch kind {
        case .github: return .primary
        case .gitlab: return .orange
        }
    }
}
