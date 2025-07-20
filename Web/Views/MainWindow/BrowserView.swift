import SwiftUI
import WebKit

struct BrowserView: View {
    @StateObject private var tabManager = TabManager()
    @State private var urlString: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            HStack(spacing: 12) {
                // Navigation controls
                if let activeTab = tabManager.activeTab {
                    NavigationControls(tab: activeTab)
                }
                
                // URL bar
                URLBar(urlString: $urlString, onSubmit: navigateToURL)
                    .frame(maxWidth: .infinity)
                
                // Menu button
                Button(action: showMenu) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
                .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            // Tab bar
            TabBarView(tabManager: tabManager)
            
            // Web content
            if let activeTab = tabManager.activeTab {
                WebContentView(tab: activeTab, urlString: $urlString)
            } else {
                NewTabView()
            }
        }
        .onAppear {
            // Initialize with a default URL if needed
            if let firstTab = tabManager.tabs.first, firstTab.url == nil {
                urlString = "https://www.google.com"
                navigateToURL(urlString)
            }
        }
    }
    
    private func navigateToURL(_ url: String) {
        guard let activeTab = tabManager.activeTab,
              let validURL = URL(string: url) else { return }
        
        activeTab.navigate(to: validURL)
        urlString = url
    }
    
    private func showMenu() {
        // TODO: Implement menu functionality
        print("Menu button tapped")
    }
}

// Tab bar view
struct TabBarView: View {
    @ObservedObject var tabManager: TabManager
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabManager.tabs) { tab in
                    TabView(tab: tab, isActive: tabManager.activeTab?.id == tab.id, tabManager: tabManager)
                        .onTapGesture {
                            tabManager.setActiveTab(tab)
                        }
                }
                
                // New tab button
                Button(action: { tabManager.createNewTab() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(Color.clear)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 40)
        .background(.ultraThinMaterial)
    }
}

// Individual tab view
struct TabView: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let tabManager: TabManager
    
    var body: some View {
        HStack(spacing: 8) {
            // Favicon or loading indicator
            Group {
                if tab.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                } else if let favicon = tab.favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            
            // Title
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: 120)
            
            // Close button
            Button(action: closeTab) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isActive)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? .blue : .clear, lineWidth: 1)
        )
    }
    
    private func closeTab() {
        tabManager.closeTab(tab)
    }
}

// Web content view
struct WebContentView: View {
    @ObservedObject var tab: Tab
    @Binding var urlString: String
    
    var body: some View {
        ZStack {
            if tab.isHibernated, let snapshot = tab.snapshot {
                // Show snapshot for hibernated tabs
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay(
                        VStack {
                            Text("Tab Hibernated")
                                .font(.headline)
                            Text("Click to reload")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    )
                    .onTapGesture {
                        tab.wakeUp()
                    }
            } else {
                // Active web view
                WebView(
                    url: $tab.url,
                    canGoBack: $tab.canGoBack,
                    canGoForward: $tab.canGoForward,
                    isLoading: $tab.isLoading,
                    estimatedProgress: $tab.estimatedProgress,
                    title: Binding(
                        get: { tab.title },
                        set: { tab.title = $0 ?? "New Tab" }
                    ),
                    favicon: $tab.favicon,
                    onNavigationAction: nil,
                    onDownloadRequest: { url, filename in
                        // TODO: Handle downloads
                        print("Download requested: \(url)")
                    }
                )
                .onChange(of: tab.url) { _, newURL in
                    if let url = newURL {
                        urlString = url.absoluteString
                    }
                }
            }
            
            // Loading progress bar
            if tab.isLoading {
                VStack {
                    ProgressView(value: min(max(tab.estimatedProgress, 0.0), 1.0))
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(height: 2)
                    Spacer()
                }
            }
        }
    }
}

// Placeholder new tab view
struct NewTabView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Web")
                .font(.largeTitle)
                .fontWeight(.thin)
            
            Text("A next-generation browser")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    BrowserView()
        .frame(width: 1200, height: 800)
}