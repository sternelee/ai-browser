import SwiftUI

// Simplified dummy FocusCoordinator - no longer needed with native SwiftUI focus
// Kept only to prevent compilation errors during transition
class FocusCoordinator: ObservableObject {
    static let shared = FocusCoordinator()
    private init() {}
    
    // Dummy methods that do nothing - all focus is now handled by native SwiftUI
    func setAISidebarOpen(_ isOpen: Bool) { }
    func setPanelOpen(_ isOpen: Bool) { }
}