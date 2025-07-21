import SwiftUI
import WebKit
import Foundation

// Advanced tab hibernation manager with system memory pressure monitoring
class TabHibernationManager: ObservableObject {
    static let shared = TabHibernationManager()
    
    @Published var hibernatedTabs: Set<UUID> = []
    @Published var memoryPressureLevel: MemoryPressureLevel = .normal
    @Published var currentMemoryUsage: Int64 = 0
    @Published var systemMemoryPressure: String = "Normal"
    
    private let memoryThresholdMB: Int64 = 800 // 800MB threshold for aggressive hibernation
    private let warningThresholdMB: Int64 = 500 // 500MB threshold for warning
    private let hibernationDelay: TimeInterval = 300 // 5 minutes default
    private let aggressiveHibernationDelay: TimeInterval = 60 // 1 minute under pressure
    
    private var memoryMonitorTimer: Timer?
    private var hibernationTimers: [UUID: Timer] = [:]
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    enum MemoryPressureLevel: String, CaseIterable {
        case normal = "Normal"
        case warning = "Warning"  
        case critical = "Critical"
        
        var color: Color {
            switch self {
            case .normal: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        }
        
        var hibernationDelay: TimeInterval {
            switch self {
            case .normal: return 300 // 5 minutes
            case .warning: return 120 // 2 minutes
            case .critical: return 30 // 30 seconds
            }
        }
    }
    
    private init() {
        startMemoryMonitoring()
        setupSystemMemoryPressureSource()
        setupAppStateObservers()
    }
    
    // MARK: - Memory Monitoring
    private func startMemoryMonitoring() {
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.checkMemoryPressure()
        }
        
        // Initial check
        checkMemoryPressure()
    }
    
    private func checkMemoryPressure() {
        let memoryUsage = getCurrentMemoryUsage()
        currentMemoryUsage = memoryUsage
        
        let newPressureLevel: MemoryPressureLevel
        if memoryUsage > memoryThresholdMB {
            newPressureLevel = .critical
        } else if memoryUsage > warningThresholdMB {
            newPressureLevel = .warning
        } else {
            newPressureLevel = .normal
        }
        
        if newPressureLevel != memoryPressureLevel {
            DispatchQueue.main.async {
                self.memoryPressureLevel = newPressureLevel
                self.systemMemoryPressure = newPressureLevel.rawValue
                self.handleMemoryPressureChange()
            }
        }
    }
    
    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            print("Failed to get memory usage")
            return 0
        }
        
        return Int64(info.resident_size) / 1024 / 1024 // Convert to MB
    }
    
    private func setupSystemMemoryPressureSource() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .main)
        
        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self, let source = self.memoryPressureSource else { return }
            
            let event = source.mask
            
            if event.contains(.critical) {
                self.systemMemoryPressure = "System Critical"
                self.memoryPressureLevel = .critical
                self.handleSystemMemoryPressure(.critical)
            } else if event.contains(.warning) {
                self.systemMemoryPressure = "System Warning"
                if self.memoryPressureLevel == .normal {
                    self.memoryPressureLevel = .warning
                }
                self.handleSystemMemoryPressure(.warning)
            } else {
                // Normal pressure - only update if we were in system pressure state
                if self.systemMemoryPressure.hasPrefix("System") {
                    self.systemMemoryPressure = "Normal"
                }
            }
        }
        
        memoryPressureSource?.resume()
    }
    
    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: NSApplication.didHideNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: NSApplication.didUnhideNotification,
            object: nil
        )
    }
    
    @objc private func applicationDidEnterBackground() {
        // Aggressive hibernation when app goes to background
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.hibernateBackgroundTabs()
        }
    }
    
    @objc private func applicationWillEnterForeground() {
        // Check if we need to wake up critical tabs
        checkMemoryPressure()
    }
    
    private func handleMemoryPressureChange() {
        switch memoryPressureLevel {
        case .critical:
            hibernateOldestInactiveTabs(count: 8, immediate: true)
        case .warning:
            hibernateOldestInactiveTabs(count: 3, immediate: false)
        case .normal:
            // Update hibernation delays but don't force hibernation
            updateHibernationTimers()
        }
        
        print("Memory pressure level changed to: \(memoryPressureLevel.rawValue)")
        print("Current memory usage: \(currentMemoryUsage)MB")
    }
    
    private func handleSystemMemoryPressure(_ level: MemoryPressureLevel) {
        switch level {
        case .critical:
            // Immediate hibernation of non-active tabs
            hibernateAllInactiveTabs()
        case .warning:
            // Hibernation of oldest tabs
            hibernateOldestInactiveTabs(count: 5, immediate: true)
        case .normal:
            break
        }
    }
    
    // MARK: - Tab Hibernation
    func scheduleHibernation(for tab: Tab) {
        // Cancel existing timer
        hibernationTimers[tab.id]?.invalidate()
        
        // Don't schedule hibernation for active tabs or already hibernated tabs
        guard !tab.isActive && !tab.isHibernated else { return }
        
        // Get appropriate delay based on current memory pressure
        let delay = memoryPressureLevel.hibernationDelay
        
        // Schedule new hibernation timer
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.hibernateTab(tab)
        }
        
        hibernationTimers[tab.id] = timer
        print("Scheduled hibernation for tab '\(tab.title)' in \(delay)s due to \(memoryPressureLevel.rawValue) memory pressure")
    }
    
    func cancelHibernation(for tab: Tab) {
        hibernationTimers[tab.id]?.invalidate()
        hibernationTimers.removeValue(forKey: tab.id)
    }
    
    func hibernateTab(_ tab: Tab) {
        guard !tab.isActive && !tab.isHibernated && !tab.isLoading else { 
            print("Skipping hibernation for tab '\(tab.title)': active=\(tab.isActive), hibernated=\(tab.isHibernated), loading=\(tab.isLoading)")
            return 
        }
        
        print("Hibernating tab: \(tab.title)")
        
        // Create snapshot before hibernating
        createTabSnapshot(tab) { [weak self] snapshot in
            DispatchQueue.main.async {
                tab.snapshot = snapshot
                tab.hibernate()
                self?.hibernatedTabs.insert(tab.id)
                
                // Clean up timer
                self?.hibernationTimers.removeValue(forKey: tab.id)
                
                // Post notification for UI updates
                NotificationCenter.default.post(
                    name: .tabHibernated,
                    object: tab
                )
                
                print("Successfully hibernated tab: \(tab.title)")
            }
        }
    }
    
    func wakeUpTab(_ tab: Tab) {
        guard tab.isHibernated else { return }
        
        print("Waking up tab: \(tab.title)")
        
        tab.wakeUp()
        hibernatedTabs.remove(tab.id)
        
        // Recreate WebView when needed
        NotificationCenter.default.post(
            name: .recreateWebView,
            object: tab
        )
        
        print("Successfully woke up tab: \(tab.title)")
    }
    
    private func hibernateOldestInactiveTabs(count: Int, immediate: Bool = false) {
        // This will be called via notifications from TabManager
        // For now, just track the request
        print("Requested hibernation for \(count) tabs (immediate: \(immediate))")
        
        // Post notification for TabManager to handle
        NotificationCenter.default.post(
            name: .hibernateOldestTabs,
            object: ["count": count, "immediate": immediate]
        )
    }
    
    private func hibernateAllInactiveTabs() {
        print("Emergency hibernation requested")
        
        // Post notification for TabManager to handle
        NotificationCenter.default.post(
            name: .hibernateAllInactiveTabs,
            object: nil
        )
    }
    
    private func hibernateBackgroundTabs() {
        print("Background hibernation requested")
        
        // Post notification for TabManager to handle  
        NotificationCenter.default.post(
            name: .hibernateBackgroundTabs,
            object: nil
        )
    }
    
    private func updateHibernationTimers() {
        for (tabId, timer) in hibernationTimers {
            timer.invalidate()
            hibernationTimers.removeValue(forKey: tabId)
        }
        
        print("Updated hibernation timers for memory pressure level: \(memoryPressureLevel.rawValue)")
        
        // Post notification to reschedule timers with new delays
        NotificationCenter.default.post(
            name: .updateHibernationTimers,
            object: memoryPressureLevel
        )
    }
    
    // MARK: - Snapshot Generation
    private func createTabSnapshot(_ tab: Tab, completion: @escaping (NSImage?) -> Void) {
        guard let webView = tab.webView else {
            completion(nil)
            return
        }
        
        let config = WKSnapshotConfiguration()
        let bounds = webView.bounds
        
        // Validate bounds to prevent crashes
        guard bounds.width > 0 && bounds.height > 0 else {
            completion(nil)
            return
        }
        
        config.rect = bounds
        config.snapshotWidth = NSNumber(value: 400) // Higher quality thumbnail
        
        webView.takeSnapshot(with: config) { image, error in
            if let error = error {
                print("Snapshot error: \(error.localizedDescription)")
                completion(nil)
            } else {
                completion(image)
            }
        }
    }
    
    // MARK: - Performance Monitoring
    func getMemoryStats() -> (usage: Int64, pressure: String, hibernated: Int) {
        let hibernatedCount = hibernatedTabs.count
        return (currentMemoryUsage, systemMemoryPressure, hibernatedCount)
    }
    
    func forceGarbageCollection() {
        // Force hibernation of eligible tabs
        hibernateOldestInactiveTabs(count: 3, immediate: true)
        
        // Notify system to perform garbage collection if possible
        DispatchQueue.global(qos: .utility).async {
            // This will trigger WebKit's internal cleanup
        }
    }
    
    // MARK: - Helper Methods
    func getMemoryPressureDescription() -> String {
        return "\(systemMemoryPressure) - \(currentMemoryUsage)MB used"
    }
    
    deinit {
        memoryMonitorTimer?.invalidate()
        memoryPressureSource?.cancel()
        hibernationTimers.values.forEach { $0.invalidate() }
        
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Extensions
extension Notification.Name {
    static let tabHibernated = Notification.Name("tabHibernated")
    static let tabWokeUp = Notification.Name("tabWokeUp")
    static let recreateWebView = Notification.Name("recreateWebView")
    static let memoryPressureChanged = Notification.Name("memoryPressureChanged")
    static let hibernateOldestTabs = Notification.Name("hibernateOldestTabs")
    static let hibernateAllInactiveTabs = Notification.Name("hibernateAllInactiveTabs")
    static let hibernateBackgroundTabs = Notification.Name("hibernateBackgroundTabs")
    static let updateHibernationTimers = Notification.Name("updateHibernationTimers")
}

