import Foundation
import Combine

/// System memory monitoring service that tracks memory pressure and provides alerts
/// for adaptive tab hibernation based on system resources
class MemoryMonitor: ObservableObject {
    static let shared = MemoryMonitor()
    
    // MARK: - Published Properties
    
    @Published var currentMemoryPressure: MemoryPressureLevel = .normal
    @Published var memoryUsageBytes: Int64 = 0
    @Published var isMemoryPressureActive: Bool = false
    
    // MARK: - Configuration
    
    /// Memory pressure thresholds in bytes
    struct MemoryThresholds {
        static let warning: Int64 = 2 * 1024 * 1024 * 1024 // 2GB
        static let critical: Int64 = 4 * 1024 * 1024 * 1024 // 4GB
        static let maxWebViewCount: Int = 8 // Maximum active WebViews before forced hibernation
    }
    
    /// Memory pressure levels for adaptive hibernation
    enum MemoryPressureLevel: String, CaseIterable {
        case normal = "Normal"
        case warning = "Warning"
        case critical = "Critical"
        case urgent = "Urgent"
        
        var shouldHibernateAggressively: Bool {
            switch self {
            case .normal: return false
            case .warning: return false
            case .critical: return true
            case .urgent: return true
            }
        }
        
        var maxActiveWebViews: Int {
            switch self {
            case .normal: return 12
            case .warning: return 8
            case .critical: return 4
            case .urgent: return 2
            }
        }
    }
    
    // MARK: - Private Properties
    
    private var pressureSource: DispatchSourceMemoryPressure?
    private var monitoringTimer: Timer?
    private let queue = DispatchQueue(label: "com.web.memory-monitor", qos: .utility)
    
    // Callbacks for memory pressure events
    private var pressureChangeCallbacks: [(MemoryPressureLevel) -> Void] = []
    
    private init() {
        setupMemoryPressureMonitoring()
        startPeriodicMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Registers a callback for memory pressure level changes
    /// - Parameter callback: Function to call when memory pressure changes
    func onMemoryPressureChange(_ callback: @escaping (MemoryPressureLevel) -> Void) {
        pressureChangeCallbacks.append(callback)
    }
    
    /// Forces immediate memory usage update
    func updateMemoryUsage() {
        queue.async { [weak self] in
            let usage = self?.getCurrentMemoryUsage() ?? 0
            DispatchQueue.main.async {
                self?.memoryUsageBytes = usage
                self?.updateMemoryPressureLevel(usage)
            }
        }
    }
    
    /// Gets current memory usage in a human-readable format
    func getFormattedMemoryUsage() -> String {
        let bytes = memoryUsageBytes
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Checks if the system should trigger hibernation based on current conditions
    func shouldTriggerHibernation() -> Bool {
        return currentMemoryPressure.shouldHibernateAggressively || 
               memoryUsageBytes > MemoryThresholds.warning
    }
    
    /// Gets the maximum number of active WebViews for current memory conditions
    func getMaxActiveWebViews() -> Int {
        return currentMemoryPressure.maxActiveWebViews
    }
    
    // MARK: - Private Methods
    
    private func setupMemoryPressureMonitoring() {
        // Create dispatch source for memory pressure monitoring
        pressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical, .normal])
        
        pressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            let event = self.pressureSource?.mask ?? []
            let newLevel: MemoryPressureLevel
            
            if event.contains(.critical) {
                newLevel = .critical
            } else if event.contains(.warning) {
                newLevel = .warning
            } else {
                newLevel = .normal
            }
            
            DispatchQueue.main.async {
                self.updateMemoryPressureFromSystem(newLevel)
            }
        }
        
        pressureSource?.resume()
    }
    
    private func startPeriodicMonitoring() {
        // Update memory usage every 30 seconds
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateMemoryUsage()
        }
        
        // Initial update
        updateMemoryUsage()
    }
    
    private func stopMonitoring() {
        pressureSource?.cancel()
        pressureSource = nil
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        } else {
            return 0
        }
    }
    
    private func updateMemoryPressureFromSystem(_ level: MemoryPressureLevel) {
        let oldLevel = currentMemoryPressure
        currentMemoryPressure = level
        isMemoryPressureActive = level != .normal
        
        if oldLevel != level {
            // Notify all registered callbacks
            pressureChangeCallbacks.forEach { $0(level) }
        }
    }
    
    private func updateMemoryPressureLevel(_ memoryUsage: Int64) {
        let newLevel: MemoryPressureLevel
        
        if memoryUsage > MemoryThresholds.critical {
            newLevel = .urgent
        } else if memoryUsage > MemoryThresholds.warning {
            newLevel = .critical
        } else if isMemoryPressureActive {
            newLevel = .warning
        } else {
            newLevel = .normal
        }
        
        if currentMemoryPressure != newLevel {
            updateMemoryPressureFromSystem(newLevel)
        }
    }
}

// MARK: - Memory Monitoring Extensions

extension MemoryMonitor {
    /// Provides memory statistics for debugging and monitoring
    struct MemoryStats {
        let currentUsage: Int64
        let pressureLevel: MemoryPressureLevel
        let formattedUsage: String
        let shouldHibernate: Bool
        let maxActiveWebViews: Int
        
        init(monitor: MemoryMonitor) {
            self.currentUsage = monitor.memoryUsageBytes
            self.pressureLevel = monitor.currentMemoryPressure
            self.formattedUsage = monitor.getFormattedMemoryUsage()
            self.shouldHibernate = monitor.shouldTriggerHibernation()
            self.maxActiveWebViews = monitor.getMaxActiveWebViews()
        }
    }
    
    /// Gets comprehensive memory statistics
    func getMemoryStats() -> MemoryStats {
        return MemoryStats(monitor: self)
    }
}