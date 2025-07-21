import SwiftUI

// Web content view for displaying individual tabs
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
                if tab.url != nil {
                    WebView(
                        url: Binding(
                            get: { tab.url },
                            set: { tab.url = $0 }
                        ),
                        canGoBack: Binding(
                            get: { tab.canGoBack },
                            set: { tab.canGoBack = $0 }
                        ),
                        canGoForward: Binding(
                            get: { tab.canGoForward },
                            set: { tab.canGoForward = $0 }
                        ),
                        isLoading: Binding(
                            get: { tab.isLoading },
                            set: { tab.isLoading = $0 }
                        ),
                        estimatedProgress: Binding(
                            get: { tab.estimatedProgress },
                            set: { tab.estimatedProgress = $0 }
                        ),
                        title: Binding(
                            get: { tab.title },
                            set: { tab.title = $0 ?? "New Tab" }
                        ),
                        favicon: Binding(
                            get: { tab.favicon },
                            set: { tab.favicon = $0 }
                        ),
                        tab: tab,
                        onNavigationAction: nil,
                        onDownloadRequest: nil
                    )
                    .onChange(of: tab.url) { _, newURL in
                        if let url = newURL {
                            urlString = url.absoluteString
                        }
                    }
                } else {
                    NewTabView()
                }
            }
            
            // Loading progress bar
            if tab.isLoading {
                VStack {
                    ProgressView(value: SafeNumericConversions.safeProgress(tab.estimatedProgress))
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(height: 2)
                    Spacer()
                }
            }
        }
    }
}