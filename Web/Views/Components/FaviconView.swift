import SwiftUI
import AppKit

struct FaviconView: View {
    @ObservedObject var tab: Web.Tab
    let size: CGFloat
    
    var body: some View {
        Group {
            if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else if tab.url == nil || tab.title == "New Tab" {
                // Show Web logo for new tabs
                WebLogo()
                    .frame(width: size, height: size)
            } else {
                // Default globe icon while loading or if no favicon for existing pages
                Image(systemName: "globe")
                    .font(.system(size: size * 0.7, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: size, height: size)
            }
        }
    }
}

#Preview {
    let tab = Web.Tab()
    return FaviconView(tab: tab, size: 24)
}