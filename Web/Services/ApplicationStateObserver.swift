import Foundation
import AppKit
import Combine

/// Observes the application’s active/inactive state and applies more
/// aggressive resource-saving strategies when the browser is in the background.
///
/// – When the app resigns active (goes to the background) we switch the
///   `TabHibernationManager` policy to `.aggressive` and immediately evaluate
///   hibernation opportunities.
/// – When the app becomes active again we restore the previous (balanced)
///   policy so the user regains full performance.
///
/// If the AI assistant is running, it can override this behaviour by temporarily
/// setting its own policy, but that logic lives inside the AI service.
final class ApplicationStateObserver {
    static let shared = ApplicationStateObserver()
    
    // MARK: ‑ Private
    private var cancellables = Set<AnyCancellable>()
    private let defaultForegroundPolicy: TabHibernationManager.HibernationPolicy = .balanced
    private let backgroundPolicy: TabHibernationManager.HibernationPolicy = .aggressive
    
    private init() {
        // Listen to app state changes.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleDidBecomeActive()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleDidResignActive()
            }
            .store(in: &cancellables)
    }
    
    // MARK: ‑ Handlers
    private func handleDidBecomeActive() {
        // Restore foreground performance settings.
        TabHibernationManager.shared.updatePolicy(defaultForegroundPolicy)
    }
    
    private func handleDidResignActive() {
        // Apply aggressive resource-saving policy and evaluate immediately.
        TabHibernationManager.shared.updatePolicy(backgroundPolicy)
        // Evaluate after a short delay so `NSApplication.shared.isActive` is updated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            TabHibernationManager.shared.evaluateHibernationOpportunities()
        }
    }
} 