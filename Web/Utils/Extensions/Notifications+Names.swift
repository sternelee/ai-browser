import Foundation

extension Notification.Name {
    static let aISidebarStateChanged = Notification.Name("AISidebarStateChanged")
    static let toggleAISidebar = Notification.Name("ToggleAISidebar")
    static let focusAIInput = Notification.Name("FocusAIInput")
    static let pageNavigationCompleted = Notification.Name("PageNavigationCompleted")

    static let openUsageBilling = Notification.Name("OpenUsageBilling")

    // Command Palette and Assistant actions
    static let showCommandPaletteRequested = Notification.Name("showCommandPaletteRequested")
    static let hideCommandPaletteRequested = Notification.Name("hideCommandPaletteRequested")
    static let performTLDRRequested = Notification.Name("performTLDRRequested")
    static let performAskRequested = Notification.Name("performAskRequested")
}
