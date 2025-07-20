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
                if let url = tab.url {
                    SimpleWebView(url: url)
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