import SwiftUI

@main
struct WebApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            BrowserCommands()
        }
    }
}

struct BrowserCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                // TODO: Implement new tab shortcut
                NotificationCenter.default.post(name: .newTabRequested, object: nil)
            }
            .keyboardShortcut("t", modifiers: .command)
            
            Button("Close Tab") {
                // TODO: Implement close tab shortcut
                NotificationCenter.default.post(name: .closeTabRequested, object: nil)
            }
            .keyboardShortcut("w", modifiers: .command)
            
            Button("Reopen Closed Tab") {
                // TODO: Implement reopen closed tab shortcut
                NotificationCenter.default.post(name: .reopenTabRequested, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        
        CommandGroup(after: .toolbar) {
            Button("Reload") {
                NotificationCenter.default.post(name: .reloadRequested, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
            
            Button("Focus Address Bar") {
                NotificationCenter.default.post(name: .focusAddressBarRequested, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)
        }
        
        CommandGroup(after: .textEditing) {
            Button("Find in Page") {
                NotificationCenter.default.post(name: .findInPageRequested, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        
        CommandGroup(after: .windowArrangement) {
            Button("Downloads") {
                NotificationCenter.default.post(name: .showDownloadsRequested, object: nil)
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
            
            Button("Developer Tools") {
                NotificationCenter.default.post(name: .showDeveloperToolsRequested, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

// Notification names for keyboard shortcuts
extension Notification.Name {
    static let newTabRequested = Notification.Name("newTabRequested")
    static let closeTabRequested = Notification.Name("closeTabRequested")
    static let reopenTabRequested = Notification.Name("reopenTabRequested")
    static let reloadRequested = Notification.Name("reloadRequested")
    static let focusAddressBarRequested = Notification.Name("focusAddressBarRequested")
    static let findInPageRequested = Notification.Name("findInPageRequested")
    static let showDownloadsRequested = Notification.Name("showDownloadsRequested")
    static let showDeveloperToolsRequested = Notification.Name("showDeveloperToolsRequested")
}
