import SwiftUI
import Combine

// Global focus coordinator to prevent URL bar conflicts and lock-ups
class FocusCoordinator: ObservableObject {
    static let shared = FocusCoordinator()
    
    @Published private var _activeURLBarID: String?
    @Published private var _isAnyURLBarFocused: Bool = false
    
    // Panel state tracking to prevent focus conflicts during panel operations
    @Published private var isPanelOpen: Bool = false
    
    // Reduced complexity - no debounce timer to prevent conflicts with Google search
    // Timeout after which a locked focus is considered stale (seconds)
    private let focusTimeout: TimeInterval = 1.0 // Reduced from 2s to 1s for faster recovery

    // Tracks the last time focus was updated – used for stale lock detection
    private var lastFocusUpdate: Date?
    
    private init() {}
    
    var activeURLBarID: String? {
        return _activeURLBarID
    }
    
    var isAnyURLBarFocused: Bool {
        return _isAnyURLBarFocused
    }
    
    func setFocusedURLBar(_ id: String, focused: Bool) {
        // Direct update without debouncing to prevent conflicts with Google's focus handling
        DispatchQueue.main.async {
            self.updateFocusState(id: id, focused: focused)
        }
    }
    
    // Emergency function to clear all focus locks - can be called when URL bars become unresponsive
    func clearAllFocus() {
        DispatchQueue.main.async { [weak self] in
            self?._activeURLBarID = nil
            self?._isAnyURLBarFocused = false
            self?.lastFocusUpdate = nil
            print("⚗️ Focus coordinator cleared all focus locks")
        }
    }
    
    private func updateFocusState(id: String, focused: Bool) {
        // Record timestamp for every focus state mutation
        lastFocusUpdate = Date()
        if focused {
            // Only one URL bar can be focused at a time
            if _activeURLBarID != id {
                _activeURLBarID = id
                _isAnyURLBarFocused = true
            }
        } else {
            // Only clear focus if this was the active URL bar
            if _activeURLBarID == id {
                _activeURLBarID = nil
                _isAnyURLBarFocused = false
            }
        }
    }
    
    func canFocus(_ id: String) -> Bool {
        // If a panel is open, be more restrictive about focus changes to prevent conflicts
        if isPanelOpen {
            // Only allow focus if no URL bar is currently focused, or if this is the same bar
            return _activeURLBarID == nil || _activeURLBarID == id
        }
        
        // If the current focus lock has been active for longer than the timeout, clear it automatically.
        if let timestamp = lastFocusUpdate, Date().timeIntervalSince(timestamp) > focusTimeout {
            clearAllFocus()
        }

        // Always allow focus if no URL bar is currently focused, or if this is the same bar
        if _activeURLBarID == nil || _activeURLBarID == id {
            return true
        }
        
        // Emergency recovery: if focus has been stuck for too long, clear it
        // This prevents permanent lock-outs
        return false
    }
    
    // Force focus on a specific URL bar, clearing any existing locks
    func forceFocus(_ id: String) {
        DispatchQueue.main.async { [weak self] in
            self?._activeURLBarID = id
            self?._isAnyURLBarFocused = true
            self?.lastFocusUpdate = Date()
            print("⚗️ Force focus applied to URL bar: \(id)")
        }
    }
    
    // Special handling for Google.com - minimal intervention approach
    func handleGoogleNavigation() {
        // Only clear stale focus locks, don't interfere with Google's natural focus management
        if let timestamp = lastFocusUpdate, Date().timeIntervalSince(timestamp) > 2.0 {
            clearAllFocus()
            print("⚗️ Google navigation detected - cleared only stale focus locks")
        }
    }
    
    // Panel state management methods
    func setPanelOpen(_ isOpen: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPanelOpen = isOpen
            if isOpen {
                // When a panel opens, clear any existing focus to prevent conflicts
                self?.clearAllFocus()
                print("⚗️ Panel opened - cleared URL bar focus to prevent conflicts")
            }
        }
    }
    
    deinit {
        // No timers to clean up since we removed debounce timer
    }
}

// FocusState wrapper that coordinates with global focus manager
struct CoordinatedFocusState {
    private let id: String
    private let coordinator = FocusCoordinator.shared
    @FocusState private var internalFocus: Bool
    
    init(_ id: String) {
        self.id = id
    }
    
    var wrappedValue: Bool {
        get { internalFocus && coordinator.activeURLBarID == id }
        nonmutating set {
            if newValue && coordinator.canFocus(id) {
                coordinator.setFocusedURLBar(id, focused: true)
                internalFocus = true
            } else if !newValue {
                coordinator.setFocusedURLBar(id, focused: false)
                internalFocus = false
            }
        }
    }
    
    var projectedValue: FocusState<Bool>.Binding {
        return $internalFocus
    }
}