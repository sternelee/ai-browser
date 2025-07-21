import SwiftUI
import os.log

@main
struct WebApp: App {
    init() {
        configureLogging()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(WindowConfigurator())
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
        .commands {
            BrowserCommands()
        }
    }
    
    private func configureLogging() {
        // Set environment variables to reduce WebKit verbosity
        // These help suppress the RBSService and ViewBridge logs
        setenv("WEBKIT_DISABLE_VERBOSE_LOGGING", "1", 1)
        setenv("WEBKIT_SUPPRESS_PROCESS_LOGS", "1", 1)
        setenv("OS_ACTIVITY_MODE", "disable", 1)
        
        // Reduce logging for specific subsystems
        let logger = Logger(subsystem: "com.example.Web", category: "App")
        logger.info("Web browser started with reduced WebKit logging")
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
            
            Button("Toggle Tab Display") {
                NotificationCenter.default.post(name: .toggleTabDisplay, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)
            
            Button("Toggle Edge-to-Edge Mode") {
                NotificationCenter.default.post(name: .toggleEdgeToEdge, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            
            Button("Toggle Top Bar") {
                NotificationCenter.default.post(name: .toggleTopBar, object: nil)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            
            Button("Next Tab") {
                NotificationCenter.default.post(name: .nextTabRequested, object: nil)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            
            Button("Previous Tab") {
                NotificationCenter.default.post(name: .previousTabRequested, object: nil)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            
            Button("Next Tab (Arrow)") {
                NotificationCenter.default.post(name: .nextTabRequested, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            
            Button("Previous Tab (Arrow)") {
                NotificationCenter.default.post(name: .previousTabRequested, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
        }
        
        // Tab selection shortcuts (Cmd+1 through Cmd+9)
        CommandGroup(after: .windowArrangement) {
            ForEach(1...9, id: \.self) { number in
                Button("Go to Tab \(number)") {
                    NotificationCenter.default.post(name: .selectTabByNumber, object: number)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
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
    
    // Phase 2: Next-Gen UI shortcuts
    static let toggleTabDisplay = Notification.Name("toggleTabDisplay")
    static let toggleEdgeToEdge = Notification.Name("toggleEdgeToEdge")
    static let navigateBack = Notification.Name("navigateBack")
    static let navigateForward = Notification.Name("navigateForward")
    
    // Tab navigation shortcuts
    static let nextTabRequested = Notification.Name("nextTabRequested")
    static let previousTabRequested = Notification.Name("previousTabRequested")
    static let selectTabByNumber = Notification.Name("selectTabByNumber")
    static let navigateCurrentTab = Notification.Name("navigateCurrentTab")
    static let toggleTopBar = Notification.Name("toggleTopBar")
    static let createNewTabWithURL = Notification.Name("createNewTabWithURL")
}
