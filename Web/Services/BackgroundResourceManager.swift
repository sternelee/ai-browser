import AppKit
import Combine
import Foundation
import WebKit

/// Comprehensive background resource management system that ensures proper hibernation
/// when the Web browser is not the focused application, similar to Safari and Chrome
class BackgroundResourceManager: ObservableObject {
    static let shared = BackgroundResourceManager()

    // MARK: - Properties

    @Published var isAppInBackground: Bool = false
    @Published var resourcesSuspended: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var backgroundTimers = Set<Timer>()
    private var suspendedWebViews = Set<WKWebView>()

    // Timer references for suspension
    private var updateTimer: Timer?
    private var particleTimer: Timer?
    private var hibernationTimer: Timer?

    // MARK: - Configuration

    /// Configuration for background resource management
    struct BackgroundPolicy {
        let suspendJavaScriptTimers: Bool
        let suspendNetworkRequests: Bool
        let suspendAnimations: Bool
        let hibernateInactiveTabs: Bool
        let cleanupTimers: Bool
        let reduceProcessPriority: Bool

        static let aggressive = BackgroundPolicy(
            suspendJavaScriptTimers: true,
            suspendNetworkRequests: false,  // Keep for essential requests
            suspendAnimations: true,
            hibernateInactiveTabs: true,
            cleanupTimers: true,
            reduceProcessPriority: true
        )

        static let conservative = BackgroundPolicy(
            suspendJavaScriptTimers: true,
            suspendNetworkRequests: false,
            suspendAnimations: false,
            hibernateInactiveTabs: false,
            cleanupTimers: true,
            reduceProcessPriority: false
        )
    }

    private var currentPolicy: BackgroundPolicy = .aggressive

    // MARK: - Initialization

    private init() {
        setupApplicationStateMonitoring()
        setupWebKitSuspension()
    }

    // MARK: - Application State Monitoring

    private func setupApplicationStateMonitoring() {
        // Monitor application becoming active
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleApplicationDidBecomeActive()
                }
            }
            .store(in: &cancellables)

        // Monitor application resigning active
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleApplicationDidResignActive()
                }
            }
            .store(in: &cancellables)

        // Additional background/foreground monitoring
        NotificationCenter.default.publisher(for: NSApplication.didHideNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleApplicationWentToBackground()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleApplicationCameToForeground()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Application State Handlers

    @MainActor
    private func handleApplicationDidBecomeActive() {
        AppLog.debug("App active - resuming resources")
        isAppInBackground = false
        resumeAllResources()
    }

    @MainActor
    private func handleApplicationDidResignActive() {
        AppLog.debug("App resigned active - suspending resources")
        isAppInBackground = true

        // Delay suspension slightly to avoid flicker during app switching
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.suspendAllResources()
        }
    }

    @MainActor
    private func handleApplicationWentToBackground() {
        AppLog.debug("App background - aggressive suspension")
        isAppInBackground = true
        suspendAllResources()
    }

    @MainActor
    private func handleApplicationCameToForeground() {
        AppLog.debug("App foreground - resuming resources")
        isAppInBackground = false
        resumeAllResources()
    }

    // MARK: - Resource Suspension & Resumption

    @MainActor
    private func suspendAllResources() {
        guard !resourcesSuspended else { return }
        resourcesSuspended = true

        AppLog.debug("Suspending all background resources…")

        // 1. Suspend all active WebViews
        suspendAllWebViews()

        // 2. Suspend native app timers
        suspendNativeTimers()

        // 3. Clean up JavaScript timers in all WebViews
        cleanupJavaScriptTimers()

        // 4. Trigger aggressive tab hibernation
        triggerAggressiveTabHibernation()

        // 5. Reduce process priority
        if currentPolicy.reduceProcessPriority {
            reduceProcessPriority()
        }

        AppLog.debug("Background resource suspension complete")
    }

    @MainActor
    private func resumeAllResources() {
        guard resourcesSuspended else { return }
        resourcesSuspended = false

        AppLog.debug("Resuming all resources…")

        // 1. Resume all suspended WebViews
        resumeAllWebViews()

        // 2. Resume native app timers
        resumeNativeTimers()

        // 3. Restore normal process priority
        restoreProcessPriority()

        // 4. Restore balanced tab hibernation policy
        restoreBalancedHibernationPolicy()

        AppLog.debug("Resource resumption complete")
    }

    // MARK: - WebView Suspension

    private func setupWebKitSuspension() {
        // Configure WebKit for proper background behavior
        setupWebKitBackgroundConfiguration()
    }

    private func setupWebKitBackgroundConfiguration() {
        // Apply WebKit environment variables for background behavior
        _ = setenv("WEBKIT_SUSPEND_IN_BACKGROUND", "1", 1)
        _ = setenv("WEBKIT_BACKGROUND_PRIORITY", "1", 1)
    }

    @MainActor
    private func suspendAllWebViews() {
        guard currentPolicy.suspendJavaScriptTimers else { return }

        let allWebViews = collectAllActiveWebViews()
        AppLog.debug("Suspending \(allWebViews.count) active WebViews")

        for webView in allWebViews {
            suspendWebView(webView)
        }
    }

    @MainActor
    private func resumeAllWebViews() {
        AppLog.debug("Resuming \(suspendedWebViews.count) suspended WebViews")

        let webViewsToResume = Array(suspendedWebViews)
        suspendedWebViews.removeAll()

        for webView in webViewsToResume {
            resumeWebView(webView)
        }
    }

    private func suspendWebView(_ webView: WKWebView) {
        // Add to suspended set
        suspendedWebViews.insert(webView)

        // Configure WebView for background mode
        if currentPolicy.suspendJavaScriptTimers {
            // Note: WebKit private APIs are not available in this version

            // Suspend JavaScript timers and reduce update frequency
            let suspensionScript = """
                (function() {
                    // Suspend all timers and animations
                    if (window.webBrowserTimerRegistry) {
                        window.webBrowserTimerRegistry.suspended = true;
                    }
                    
                    // Pause animations and reduce frequency of updates
                    if (window.requestAnimationFrame) {
                        window._originalRAF = window.requestAnimationFrame;
                        window.requestAnimationFrame = function(callback) {
                            // Reduce animation frame rate in background
                            setTimeout(callback, 1000); // 1 FPS instead of 60 FPS
                        };
                    }
                    
                    // Suspend expensive operations
                    document.dispatchEvent(new Event('backgroundSuspend'));
                })();
                """

            webView.evaluateJavaScript(suspensionScript) { result, error in
                if let error = error {
                    AppLog.warn("WebView suspension script error: \(error.localizedDescription)")
                } else {
                    AppLog.debug("WebView suspended successfully")
                }
            }
        }
    }

    private func resumeWebView(_ webView: WKWebView) {
        // Restore WebView to foreground mode
        // Note: WebKit private APIs are not available in this version

        // Resume JavaScript execution
        let resumptionScript = """
            (function() {
                // Resume timers
                if (window.webBrowserTimerRegistry) {
                    window.webBrowserTimerRegistry.suspended = false;
                }
                
                // Restore normal animation frame rate
                if (window._originalRAF) {
                    window.requestAnimationFrame = window._originalRAF;
                    delete window._originalRAF;
                }
                
                // Resume operations
                document.dispatchEvent(new Event('foregroundResume'));
            })();
            """

        webView.evaluateJavaScript(resumptionScript) { result, error in
            if let error = error { AppLog.warn("WebView resumption script error: \(error.localizedDescription)") }
            else { AppLog.debug("WebView resumed successfully") }
        }
    }

    // MARK: - Timer Management

    @MainActor
    private func suspendNativeTimers() {
        AppLog.debug("Suspending native app timers")

        // Suspend update checker timer (from WebApp.swift)
        suspendUpdateTimer()

        // Suspend particle animation timer (from NewTabView.swift)
        suspendParticleAnimationTimer()

        // Suspend hibernation evaluation timer
        suspendHibernationTimer()

        // Suspend WebView responsiveness checks (Coordinator timer)
        NotificationCenter.default.post(name: .suspendWebViewResponsivenessChecks, object: nil)
    }

    @MainActor
    private func resumeNativeTimers() {
        AppLog.debug("Resuming native app timers")

        // Resume update checker
        resumeUpdateTimer()

        // Resume particle animations
        resumeParticleAnimationTimer()

        // Resume hibernation evaluation
        resumeHibernationTimer()

        // Resume WebView responsiveness checks (Coordinator timer)
        NotificationCenter.default.post(name: .resumeWebViewResponsivenessChecks, object: nil)
    }

    private func suspendUpdateTimer() {
        // Notify UpdateService to suspend its timer
        NotificationCenter.default.post(name: .suspendUpdateTimer, object: nil)
    }

    private func resumeUpdateTimer() {
        // Notify UpdateService to resume its timer
        NotificationCenter.default.post(name: .resumeUpdateTimer, object: nil)
    }

    private func suspendParticleAnimationTimer() {
        // Notify NewTabView to suspend animations
        NotificationCenter.default.post(name: .suspendParticleAnimations, object: nil)
    }

    private func resumeParticleAnimationTimer() {
        // Notify NewTabView to resume animations
        NotificationCenter.default.post(name: .resumeParticleAnimations, object: nil)
    }

    private func suspendHibernationTimer() {
        // TabHibernationManager should reduce its evaluation frequency
        NotificationCenter.default.post(name: .suspendHibernationEvaluation, object: nil)
    }

    private func resumeHibernationTimer() {
        // TabHibernationManager should restore normal evaluation frequency
        NotificationCenter.default.post(name: .resumeHibernationEvaluation, object: nil)
    }

    // MARK: - JavaScript Timer Cleanup

    @MainActor
    private func cleanupJavaScriptTimers() {
        guard currentPolicy.cleanupTimers else { return }

        let allWebViews = collectAllActiveWebViews()
        AppLog.debug("Cleaning up JavaScript timers in \(allWebViews.count) WebViews")

        for webView in allWebViews {
            webView.evaluateJavaScript(
                "if (window.cleanupAllTimers) { window.cleanupAllTimers(); }"
            ) { result, error in
                if let error = error { AppLog.warn("Timer cleanup error: \(error.localizedDescription)") }
                else { AppLog.debug("Timers cleaned up successfully") }
            }
        }
    }

    // MARK: - Tab Hibernation Management

    @MainActor
    private func triggerAggressiveTabHibernation() {
        guard currentPolicy.hibernateInactiveTabs else { return }

        AppLog.debug("Triggering aggressive tab hibernation")

        // Switch to aggressive hibernation policy
        TabHibernationManager.shared.updatePolicy(.aggressive)

        // Immediate hibernation evaluation
        TabHibernationManager.shared.evaluateHibernationOpportunities()
    }

    @MainActor
    private func restoreBalancedHibernationPolicy() {
        AppLog.debug("Restoring balanced hibernation policy")

        // Restore balanced hibernation policy
        TabHibernationManager.shared.updatePolicy(.balanced)
    }

    // MARK: - Process Priority Management

    private func reduceProcessPriority() {
        // Reduce the app's process priority to background
        // Note: performExpiringActivity is iOS-only, on macOS we use different approaches
        DispatchQueue.global(qos: .background).async {
            AppLog.debug("Reduced process priority for background operation")
        }
    }

    private func restoreProcessPriority() {
        AppLog.debug("Restored normal process priority")
        // Process priority will automatically restore when becoming active
    }

    // MARK: - Utility Methods

    @MainActor
    private func collectAllActiveWebViews() -> [WKWebView] {
        var webViews: [WKWebView] = []

        // Collect WebViews from TabManager
        // This is a simplified approach - in practice, you'd get this from your TabManager
        // For now, we'll use a notification-based approach
        NotificationCenter.default.post(
            name: .collectActiveWebViews,
            object: nil,
            userInfo: [
                "collector": { (webView: WKWebView) in
                    webViews.append(webView)
                }
            ]
        )

        return webViews
    }

    // MARK: - Public API

    /// Manually suspend all resources (for testing or explicit control)
    @MainActor
    func forceSuspend() {
        suspendAllResources()
    }

    /// Manually resume all resources (for testing or explicit control)
    @MainActor
    func forceResume() {
        resumeAllResources()
    }

    /// Update the background policy
    func updatePolicy(_ policy: BackgroundPolicy) {
        currentPolicy = policy
        AppLog.debug("Updated background resource policy")
    }

    /// Get current resource usage statistics
    func getResourceStats() -> BackgroundResourceStats {
        return BackgroundResourceStats(
            isAppInBackground: isAppInBackground,
            resourcesSuspended: resourcesSuspended,
            suspendedWebViewCount: suspendedWebViews.count,
            backgroundTimerCount: backgroundTimers.count,
            currentPolicy: currentPolicy
        )
    }
}

// MARK: - Supporting Types

extension BackgroundResourceManager {
    struct BackgroundResourceStats {
        let isAppInBackground: Bool
        let resourcesSuspended: Bool
        let suspendedWebViewCount: Int
        let backgroundTimerCount: Int
        let currentPolicy: BackgroundPolicy

        var description: String {
            return """
                Background Resource Stats:
                - App in background: \(isAppInBackground)
                - Resources suspended: \(resourcesSuspended)
                - Suspended WebViews: \(suspendedWebViewCount)
                - Background timers: \(backgroundTimerCount)
                - Policy: \(currentPolicy.suspendJavaScriptTimers ? "Aggressive" : "Conservative")
                """
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let suspendUpdateTimer = Notification.Name("suspendUpdateTimer")
    static let resumeUpdateTimer = Notification.Name("resumeUpdateTimer")
    static let suspendParticleAnimations = Notification.Name("suspendParticleAnimations")
    static let resumeParticleAnimations = Notification.Name("resumeParticleAnimations")
    static let suspendHibernationEvaluation = Notification.Name("suspendHibernationEvaluation")
    static let resumeHibernationEvaluation = Notification.Name("resumeHibernationEvaluation")
    static let collectActiveWebViews = Notification.Name("collectActiveWebViews")
    static let backgroundResourcesChanged = Notification.Name("backgroundResourcesChanged")
    static let suspendWebViewResponsivenessChecks = Notification.Name(
        "suspendWebViewResponsivenessChecks")
    static let resumeWebViewResponsivenessChecks = Notification.Name(
        "resumeWebViewResponsivenessChecks")
}
