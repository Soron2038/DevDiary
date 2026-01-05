import SwiftUI
import AppKit

/// View showing GitHub Pull Requests and Issues
struct GitHubView: View {
    @State private var pullRequests: [GitHubPullRequest] = []
    @State private var issues: [GitHubIssue] = []
    @State private var isLoadingPRs = true
    @State private var isLoadingIssues = true
    @State private var errorMessage: String?
    @State private var isConnected = false
    @State private var showTokenExpiredAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Error banner
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button(action: { errorMessage = nil }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
            }
            
            Group {
                if !isConnected {
                    notConnectedView
                } else {
                    contentView
                }
            }
        }
        .onAppear {
            checkConnectionAndLoad()
        }
        // Re-check when window becomes active (e.g., after connecting in Settings)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkConnectionAndLoad()
        }
        .alert(String(localized: "github.tokenExpired.title"), isPresented: $showTokenExpiredAlert) {
            Button(String(localized: "button.ok")) {
                // Disconnect and reset state
                try? GitHubService.shared.disconnect()
                isConnected = false
                pullRequests = []
                issues = []
            }
        } message: {
            Text(String(localized: "github.tokenExpired.message"))
        }
    }
    
    private func checkConnectionAndLoad() {
        let connected = GitHubService.shared.isConnected
        if connected != isConnected {
            isConnected = connected
        }
        if connected && pullRequests.isEmpty && issues.isEmpty {
            loadData()
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        HSplitView {
            // Left: Pull Requests
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: String(localized: "github.prs.title"),
                    count: pullRequests.count,
                    isLoading: isLoadingPRs,
                    onRefresh: loadPullRequests
                )
                
                Divider()
                
                if isLoadingPRs {
                    loadingView
                } else if pullRequests.isEmpty {
                    emptyView(
                        icon: "arrow.triangle.pull",
                        message: String(localized: "github.prs.empty")
                    )
                } else {
                    List(pullRequests) { pr in
                        PullRequestRow(pullRequest: pr)
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 300)
            
            // Right: Issues
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: String(localized: "github.issues.title"),
                    count: issues.count,
                    isLoading: isLoadingIssues,
                    onRefresh: loadIssues
                )
                
                Divider()
                
                if isLoadingIssues {
                    loadingView
                } else if issues.isEmpty {
                    emptyView(
                        icon: "exclamationmark.circle",
                        message: String(localized: "github.issues.empty")
                    )
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
    
    // MARK: - Section Header
    
    private func sectionHeader(title: String, count: Int, isLoading: Bool, onRefresh: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            
            if !isLoading {
                Text("\(count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onRefresh) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help(String(localized: "github.refresh"))
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
            Text("github.notConnected")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("github.notConnected.hint")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private func emptyView(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Data Loading
    
    private func loadData() {
        loadPullRequests()
        loadIssues()
    }
    
    private func loadPullRequests() {
        isLoadingPRs = true
        errorMessage = nil
        Task {
            do {
                let prs = try await GitHubService.shared.fetchUserPullRequests()
                await MainActor.run {
                    self.pullRequests = prs
                    self.isLoadingPRs = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingPRs = false
                    handleError(error)
                }
            }
        }
    }
    
    private func loadIssues() {
        isLoadingIssues = true
        Task {
            do {
                let fetchedIssues = try await GitHubService.shared.fetchAssignedIssues()
                await MainActor.run {
                    self.issues = fetchedIssues
                    self.isLoadingIssues = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingIssues = false
                    handleError(error)
                }
            }
        }
    }
    
    private func handleError(_ error: Error) {
        let message = error.localizedDescription
        
        // Check for token expiration (401 errors)
        if message.contains("401") || message.lowercased().contains("expired") || message.lowercased().contains("invalid") {
            showTokenExpiredAlert = true
        } else if message.contains("offline") || message.contains("network") || message.contains("internet") {
            errorMessage = String(localized: "github.error.offline")
        } else {
            errorMessage = message
        }
    }
}

// MARK: - Pull Request Row

private struct PullRequestRow: View {
    let pullRequest: GitHubPullRequest
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            // PR icon
            Image(systemName: "arrow.triangle.pull")
                .foregroundColor(pullRequest.draft ? .secondary : .green)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pullRequest.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if pullRequest.draft {
                        Text("Draft")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(pullRequest.repoName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("#\(pullRequest.number)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(pullRequest.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Open in browser
            Button(action: openInBrowser) {
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.0)
            .help(String(localized: "github.openInBrowser"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            openInBrowser()
        }
    }
    
    private func openInBrowser() {
        if let url = URL(string: pullRequest.htmlURL) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Issue Row

private struct IssueRow: View {
    let issue: GitHubIssue
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Issue icon
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(.green)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(issue.repoName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("#\(issue.number)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Labels
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
                        Text("+\(issue.labels.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Open in browser
            Button(action: openInBrowser) {
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.0)
            .help(String(localized: "github.openInBrowser"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            openInBrowser()
        }
    }
    
    private func openInBrowser() {
        if let url = URL(string: issue.htmlURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
