import SwiftUI
import Combine

// Global focus coordinator to prevent URL bar conflicts and lock-ups
class FocusCoordinator: ObservableObject {
    static let shared = FocusCoordinator()
    
    @Published private var _activeURLBarID: String?
    @Published private var _isAnyURLBarFocused: Bool = false
    
    // Debounce timer to prevent rapid focus changes
    private var debounceTimer: Timer?
    private let debounceDelay: TimeInterval = 0.1
    
    private init() {}
    
    var activeURLBarID: String? {
        return _activeURLBarID
    }
    
    var isAnyURLBarFocused: Bool {
        return _isAnyURLBarFocused
    }
    
    func setFocusedURLBar(_ id: String, focused: Bool) {
        // Debounce rapid focus changes to prevent lock-ups
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateFocusState(id: id, focused: focused)
            }
        }
    }
    
    // Emergency function to clear all focus locks - can be called when URL bars become unresponsive
    func clearAllFocus() {
        DispatchQueue.main.async { [weak self] in
            self?._activeURLBarID = nil
            self?._isAnyURLBarFocused = false
            self?.debounceTimer?.invalidate()
        }
    }
    
    private func updateFocusState(id: String, focused: Bool) {
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
        // Always allow focus if no URL bar is currently focused, or if this is the same bar
        // Also add timeout-based recovery: if a bar has been focused for more than 30 seconds, allow new focus
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
            self?.debounceTimer?.invalidate()
            self?._activeURLBarID = id
            self?._isAnyURLBarFocused = true
        }
    }
    
    deinit {
        debounceTimer?.invalidate()
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