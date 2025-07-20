import SwiftUI
import AppKit

// Shared tab context menu for right-click actions
struct TabContextMenu: View {
    let tab: Tab
    let tabManager: TabManager
    
    var body: some View {
        Button("Close Tab") {
            tabManager.closeTab(tab)
        }
        
        Button("Close Other Tabs") {
            tabManager.closeOtherTabs(except: tab)
        }
        
        Divider()
        
        Button("Duplicate Tab") {
            if let url = tab.url {
                _ = tabManager.createNewTab(url: url, isIncognito: tab.isIncognito)
            }
        }
        
        if let url = tab.url {
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
    }
}