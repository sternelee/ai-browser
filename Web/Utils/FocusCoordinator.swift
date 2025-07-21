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
        return _activeURLBarID == nil || _activeURLBarID == id
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