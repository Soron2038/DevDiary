import SwiftUI

/// Onboarding view shown on first launch
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var isDiscovering = false
    @State private var discoveredRepos = 0
    
    private let totalPages = 3
    
    var body: some View {
        VStack(spacing: 0) {
            // Content
            TabView(selection: $currentPage) {
                welcomePage
                    .tag(0)
                
                privacyPage
                    .tag(1)
                
                setupPage
                    .tag(2)
            }
            .tabViewStyle(.automatic)
            .animation(.easeInOut, value: currentPage)
            
            Divider()
            
            // Navigation
            HStack {
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut, value: currentPage)
                    }
                }
                
                Spacer()
                
                // Buttons
                if currentPage > 0 {
                    Button(String(localized: "onboarding.button.back")) {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                if currentPage < totalPages - 1 {
                    Button(String(localized: "onboarding.button.next")) {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(String(localized: "onboarding.button.start")) {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDiscovering)
                }
            }
            .padding()
        }
        .frame(width: 520, height: 480)
    }
    
    // MARK: - Pages
    
    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("onboarding.welcome.title")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("onboarding.welcome.subtitle")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            
            // Features
            HStack(spacing: 32) {
                FeatureItem(
                    icon: "clock",
                    title: String(localized: "onboarding.feature.tracking"),
                    color: .blue
                )
                
                FeatureItem(
                    icon: "arrow.triangle.branch",
                    title: String(localized: "onboarding.feature.git"),
                    color: .green
                )
                
                FeatureItem(
                    icon: "lock.shield",
                    title: String(localized: "onboarding.feature.privacy"),
                    color: .purple
                )
            }
            .padding(.bottom, 40)
        }
        .padding()
    }
    
    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("onboarding.privacy.title")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 16) {
                PrivacyPoint(
                    icon: "internaldrive",
                    text: String(localized: "onboarding.privacy.local")
                )
                
                PrivacyPoint(
                    icon: "network.slash",
                    text: String(localized: "onboarding.privacy.noNetwork")
                )
                
                PrivacyPoint(
                    icon: "hand.raised",
                    text: String(localized: "onboarding.privacy.control")
                )
                
                PrivacyPoint(
                    icon: "trash",
                    text: String(localized: "onboarding.privacy.delete")
                )
            }
            .padding(.horizontal, 60)
            
            Spacer()
        }
        .padding()
    }
    
    private var setupPage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if isDiscovering {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                
                Text("onboarding.setup.discovering")
                    .font(.title2)
                
                if discoveredRepos > 0 {
                    Text(String(format: String(localized: "onboarding.setup.found"), discoveredRepos))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            } else {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                
                Text("onboarding.setup.title")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("onboarding.setup.description")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Search paths
                VStack(alignment: .leading, spacing: 8) {
                    Text("onboarding.setup.paths")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ForEach(["~/Developer", "~/Projects", "~/Code", "~/Documents"], id: \.self) { path in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                            Text(path)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func completeOnboarding() {
        isDiscovering = true
        
        Task {
            do {
                let count = try await RepositoryDiscovery.shared.discoverRepositories()
                await MainActor.run {
                    discoveredRepos = count
                }
                
                // Small delay to show the result
                try await Task.sleep(nanoseconds: 1_000_000_000)
                
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    isPresented = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct FeatureItem: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 100)
    }
}

private struct PrivacyPoint: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.green)
                .frame(width: 24)
            
            Text(text)
                .font(.body)
        }
    }
}
