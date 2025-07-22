import SwiftUI
import Combine

// Global focus coordinator to prevent URL bar conflicts and lock-ups
class FocusCoordinator: ObservableObject {
    static let shared = FocusCoordinator()
    
    @Published private var _activeURLBarID: String?
    @Published private var _isAnyURLBarFocused: Bool = false
    
    // Panel state tracking to prevent focus conflicts during panel operations
    @Published private var isPanelOpen: Bool = false
    
    // Track individual panel states to prevent conflicts
    private var isAISidebarOpen: Bool = false
    private var isOtherPanelOpen: Bool = false
    
    // Reduced complexity - no debounce timer to prevent conflicts with Google search
    // Timeout after which a locked focus is considered stale (seconds)
    private let focusTimeout: TimeInterval = 1.0 // Reduced from 2s to 1s for faster recovery

    // Tracks the last time focus was updated – used for stale lock detection
    private var lastFocusUpdate: Date?
    
    private init() {
        // Start auto-recovery mechanism
        setupAutoRecovery()
    }
    
    var activeURLBarID: String? {
        return _activeURLBarID
    }
    
    var isAnyURLBarFocused: Bool {
        return _isAnyURLBarFocused
    }
    
    func setFocusedURLBar(_ id: String, focused: Bool) {
        // DEBUG: Track all focus requests
        NSLog("🎯 FOCUS DEBUG: setFocusedURLBar called - ID: \(id), focused: \(focused), currentActive: \(String(describing: _activeURLBarID)), panelOpen: \(isPanelOpen)")
        
        // Direct update without debouncing to prevent conflicts with Google's focus handling
        DispatchQueue.main.async {
            self.updateFocusState(id: id, focused: focused)
        }
    }
    
    // Emergency function to clear all focus locks - can be called when URL bars become unresponsive
    func clearAllFocus() {
        NSLog("🎯 FOCUS DEBUG: clearAllFocus called - clearing all locks")
        DispatchQueue.main.async { [weak self] in
            let hadActiveFocus = self?._activeURLBarID != nil
            self?._activeURLBarID = nil
            self?._isAnyURLBarFocused = false
            self?.lastFocusUpdate = nil
            if hadActiveFocus {
                NSLog("🎯 FOCUS DEBUG: Cleared active focus lock - was: \(self?._activeURLBarID ?? "nil")")
            }
            print("⚗️ Focus coordinator cleared all focus locks")
        }
    }
    
    // EMERGENCY: Force clear all locks and reset state - can be called externally
    func emergencyResetAllFocusState() {
        NSLog("🚨 FOCUS EMERGENCY: Force resetting ALL focus state")
        DispatchQueue.main.async { [weak self] in
            self?._activeURLBarID = nil
            self?._isAnyURLBarFocused = false
            self?.lastFocusUpdate = nil
            self?.isPanelOpen = false
            self?.isAISidebarOpen = false
            self?.isOtherPanelOpen = false
            NSLog("🚨 FOCUS EMERGENCY: All focus state reset")
            print("🚨 Emergency focus reset completed - all inputs should work now")
        }
    }
    
    // Auto-recovery mechanism - runs periodically with much longer timeout to avoid interfering with web content
    private func setupAutoRecovery() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Only clear if focus has been locked for more than 30 seconds (much longer to avoid web content interference)
            if let timestamp = self.lastFocusUpdate, Date().timeIntervalSince(timestamp) > 30.0 {
                NSLog("🚨 FOCUS AUTO-RECOVERY: Detected stuck focus for \(Date().timeIntervalSince(timestamp))s - force clearing")
                self.emergencyResetAllFocusState()
            }
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
        let currentTime = Date()
        let timeSinceLastUpdate = lastFocusUpdate != nil ? currentTime.timeIntervalSince(lastFocusUpdate!) : 0
        
        // DEBUG: Track all focus permission requests
        NSLog("🎯 FOCUS DEBUG: canFocus called - ID: \(id), currentActive: \(String(describing: _activeURLBarID)), panelOpen: \(isPanelOpen), aiSidebar: \(isAISidebarOpen), otherPanel: \(isOtherPanelOpen), timeSinceUpdate: \(timeSinceLastUpdate)")
        
        // If a panel is open, be more restrictive about focus changes to prevent conflicts
        if isPanelOpen {
            let canFocusResult = _activeURLBarID == nil || _activeURLBarID == id
            NSLog("🎯 FOCUS DEBUG: Panel open restriction - canFocus: \(canFocusResult)")
            return canFocusResult
        }
        
        // Only clear focus if it's been locked for much longer to avoid interfering with web content
        if let timestamp = lastFocusUpdate, Date().timeIntervalSince(timestamp) > 10.0 {
            NSLog("🎯 FOCUS DEBUG: Long timeout detected (\(Date().timeIntervalSince(timestamp))s) - clearing focus")
            clearAllFocus()
        }

        // Always allow focus if no URL bar is currently focused, or if this is the same bar
        if _activeURLBarID == nil || _activeURLBarID == id {
            NSLog("🎯 FOCUS DEBUG: Focus allowed - no conflicts")
            return true
        }
        
        // CRITICAL FIX: When denying focus, proactively clear the denied TextField's focus
        // This prevents SwiftUI state inconsistencies since TextField components no longer modify their own state
        NSLog("🎯 FOCUS DEBUG: Focus DENIED - conflict with active: \(_activeURLBarID ?? "nil") - will post notification to clear")
        
        // Post notification to clear the conflicting TextField's focus state
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clearFocusForID, object: nil, userInfo: ["id": id])
        }
        
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
    func setAISidebarOpen(_ isOpen: Bool) {
        NSLog("🎯 FOCUS DEBUG: setAISidebarOpen called - isOpen: \(isOpen)")
        DispatchQueue.main.async { [weak self] in
            self?.isAISidebarOpen = isOpen
            self?.updateOverallPanelState()
            if isOpen {
                // Only clear URL bar focus, don't interfere with web content
                NSLog("🎯 FOCUS DEBUG: AI Sidebar opening - clearing only URL bar focus")
                if let activeID = self?._activeURLBarID {
                    self?._activeURLBarID = nil
                    self?._isAnyURLBarFocused = false
                    NotificationCenter.default.post(name: .clearFocusForID, object: nil, userInfo: ["id": activeID])
                }
                print("⚗️ AI Sidebar opened - cleared only URL bar focus, web content unaffected")
            } else {
                NSLog("🎯 FOCUS DEBUG: AI Sidebar closing")
            }
        }
    }
    
    func setPanelOpen(_ isOpen: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isOtherPanelOpen = isOpen
            self?.updateOverallPanelState()
            if isOpen {
                // Only clear URL bar focus, don't interfere with web content
                if let activeID = self?._activeURLBarID {
                    self?._activeURLBarID = nil
                    self?._isAnyURLBarFocused = false
                    NotificationCenter.default.post(name: .clearFocusForID, object: nil, userInfo: ["id": activeID])
                }
                print("⚗️ Panel opened - cleared only URL bar focus, web content unaffected")
            }
        }
    }
    
    private func updateOverallPanelState() {
        let wasOpen = isPanelOpen
        isPanelOpen = isAISidebarOpen || isOtherPanelOpen
        
        if !wasOpen && isPanelOpen {
            print("⚗️ Panel state changed: now open")
        } else if wasOpen && !isPanelOpen {
            print("⚗️ Panel state changed: now closed")
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