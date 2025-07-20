import SwiftUI
import WebKit

struct BrowserView: View {
    @StateObject private var tabManager = TabManager()
    
    var body: some View {
        TabDisplayView(tabManager: tabManager)
            .onAppear {
                // Initialize with a default URL if needed
                if let firstTab = tabManager.tabs.first, firstTab.url == nil {
                    firstTab.navigate(to: URL(string: "https://google.com")!)
                }
            }
    }
}

#Preview {
    BrowserView()
        .frame(width: 1200, height: 800)
}