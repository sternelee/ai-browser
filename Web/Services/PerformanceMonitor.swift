import SwiftUI
import Combine
import Foundation

// Advanced performance monitoring system with system integration
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published var currentMetrics: PerformanceMetrics = PerformanceMetrics()
    @Published var performanceLevel: PerformanceLevel = .optimal
    @Published var alerts: [PerformanceAlert] = []
    @Published var isMonitoringEnabled: Bool = true
    
    private var metricsTimer: Timer!
    private let alertThresholds = AlertThresholds()
    private var cancellables = Set<AnyCancellable>()
    
    enum PerformanceLevel: String, CaseIterable {
        case optimal = "Optimal"
        case good = "Good" 
        case warning = "Warning"
        case critical = "Critical"
        
        var color: Color {
            switch self {
            case .optimal: return .green
            case .good: return .mint
            case .warning: return .orange
            case .critical: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .optimal: return "checkmark.circle"
            case .good: return "checkmark.circle"
            case .warning: return "exclamationmark.triangle"
            case .critical: return "exclamationmark.octagon"
            }
        }
    }
    
    struct PerformanceMetrics {
        var memoryUsage: Int64 = 0 // MB
        var cpuUsage: Double = 0.0 // Percentage
        var diskUsage: Int64 = 0 // MB
        var networkActivity: NetworkActivity = NetworkActivity()
        var tabCount: Int = 0
        var hibernatedTabCount: Int = 0
        var webViewCount: Int = 0
        var lastUpdated: Date = Date()
        
        struct NetworkActivity {
            var bytesReceived: Int64 = 0
            var bytesSent: Int64 = 0
            var activeConnections: Int = 0
        }
    }
    
    struct PerformanceAlert: Identifiable, Equatable {
        let id = UUID()
        let type: AlertType
        let severity: AlertSeverity
        let message: String
        let timestamp: Date
        let suggestedAction: String?
        
        enum AlertType {
            case memoryHigh, cpuHigh, diskFull, networkSlow, tabsExcessive
        }
        
        enum AlertSeverity {
            case info, warning, critical
            
            var color: Color {
                switch self {
                case .info: return .blue
                case .warning: return .orange
                case .critical: return .red
                }
            }
        }
    }
    
    struct AlertThresholds {
        let memoryWarning: Int64 = 1024 // 1GB
        let memoryCritical: Int64 = 2048 // 2GB
        let cpuWarning: Double = 70.0 // 70%
        let cpuCritical: Double = 90.0 // 90%
        let diskWarning: Int64 = 500 // 500MB
        let diskCritical: Int64 = 1024 // 1GB
        let tabWarning: Int = 20
        let tabCritical: Int = 50
    }
    
    private init() {
        // Start performance monitoring timer
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
        
        // Subscribe to hibernation manager updates
        TabHibernationManager.shared.$currentMemoryUsage
            .sink { [weak self] memoryUsage in
                self?.currentMetrics.memoryUsage = memoryUsage
                self?.evaluatePerformance()
            }
            .store(in: &cancellables)
        
        TabHibernationManager.shared.$memoryPressureLevel
            .sink { [weak self] pressureLevel in
                self?.handleMemoryPressureChange(pressureLevel)
            }
            .store(in: &cancellables)
        
        // Initial metrics update
        updateMetrics()
    }
    
    // MARK: - Performance Monitoring
    private func updateMetrics() {
        guard isMonitoringEnabled else { return }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            var newMetrics = PerformanceMetrics()
            
            // Update memory usage
            newMetrics.memoryUsage = getCurrentMemoryUsage()
            
            // Update CPU usage
            newMetrics.cpuUsage = getCurrentCPUUsage()
            
            // Update disk usage
            newMetrics.diskUsage = getCurrentDiskUsage()
            
            // Update network activity
            newMetrics.networkActivity = getCurrentNetworkActivity()
            
            // Update tab metrics
            (newMetrics.tabCount, newMetrics.hibernatedTabCount, newMetrics.webViewCount) = getTabMetrics()
            
            newMetrics.lastUpdated = Date()
            
            DispatchQueue.main.async {
                self.currentMetrics = newMetrics
                self.evaluatePerformance()
                self.checkForAlerts()
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
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) / 1024 / 1024 : 0
    }
    
    private func getCurrentCPUUsage() -> Double {
        var info: processor_info_array_t? = nil
        var count: mach_msg_type_number_t = 0
        var host = mach_host_self()
        
        defer {
            info?.deallocate()
        }
        
        var infoCount = count
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        
        if result == KERN_SUCCESS, let info = info {
            let cpuInfo = info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: 1) { $0.pointee }
            
            let user = Double(cpuInfo.cpu_ticks.0)
            let system = Double(cpuInfo.cpu_ticks.1) 
            let idle = Double(cpuInfo.cpu_ticks.2)
            let nice = Double(cpuInfo.cpu_ticks.3)
            
            let total = user + system + idle + nice
            
            return total > 0 ? ((user + system + nice) / total) * 100.0 : 0.0
        }
        
        return 0.0
    }
    
    private func getCurrentDiskUsage() -> Int64 {
        // Get app's document directory usage
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return 0
        }
        
        do {
            let resourceValues = try documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let availableCapacity = resourceValues.volumeAvailableCapacity {
                // Return used space in MB (simplified calculation)
                return Int64(availableCapacity) / 1024 / 1024
            }
        } catch {
            print("Error getting disk usage: \(error)")
        }
        
        return 0
    }
    
    private func getCurrentNetworkActivity() -> PerformanceMetrics.NetworkActivity {
        // This is a simplified implementation
        // In a real app, you would track network usage through URLSession metrics
        return PerformanceMetrics.NetworkActivity(
            bytesReceived: 0,
            bytesSent: 0,
            activeConnections: 0
        )
    }
    
    private func getTabMetrics() -> (total: Int, hibernated: Int, webViews: Int) {
        let hibernatedCount = TabHibernationManager.shared.hibernatedTabs.count
        
        // These would be retrieved from TabManager in a real implementation
        // For now, return placeholder values
        return (total: 8, hibernated: hibernatedCount, webViews: 8 - hibernatedCount)
    }
    
    // MARK: - Performance Evaluation
    private func evaluatePerformance() {
        let metrics = currentMetrics
        var score = 100.0
        
        // Memory impact (30% weight)
        if metrics.memoryUsage > alertThresholds.memoryCritical {
            score -= 40
        } else if metrics.memoryUsage > alertThresholds.memoryWarning {
            score -= 20
        }
        
        // CPU impact (25% weight)  
        if metrics.cpuUsage > alertThresholds.cpuCritical {
            score -= 35
        } else if metrics.cpuUsage > alertThresholds.cpuWarning {
            score -= 15
        }
        
        // Tab count impact (25% weight)
        if metrics.tabCount > alertThresholds.tabCritical {
            score -= 30
        } else if metrics.tabCount > alertThresholds.tabWarning {
            score -= 15
        }
        
        // Disk usage impact (20% weight)
        if metrics.diskUsage > alertThresholds.diskCritical {
            score -= 25
        } else if metrics.diskUsage > alertThresholds.diskWarning {
            score -= 10
        }
        
        // Determine performance level
        let newLevel: PerformanceLevel
        switch score {
        case 80...100:
            newLevel = .optimal
        case 60..<80:
            newLevel = .good
        case 40..<60:
            newLevel = .warning
        default:
            newLevel = .critical
        }
        
        if newLevel != performanceLevel {
            performanceLevel = newLevel
            handlePerformanceLevelChange(newLevel)
        }
    }
    
    private func checkForAlerts() {
        let metrics = currentMetrics
        var newAlerts: [PerformanceAlert] = []
        
        // Memory alerts
        if metrics.memoryUsage > alertThresholds.memoryCritical {
            newAlerts.append(PerformanceAlert(
                type: .memoryHigh,
                severity: .critical,
                message: "Memory usage is critically high (\(metrics.memoryUsage)MB)",
                timestamp: Date(),
                suggestedAction: "Close unused tabs or restart the application"
            ))
        } else if metrics.memoryUsage > alertThresholds.memoryWarning {
            newAlerts.append(PerformanceAlert(
                type: .memoryHigh,
                severity: .warning,
                message: "Memory usage is high (\(metrics.memoryUsage)MB)",
                timestamp: Date(),
                suggestedAction: "Consider closing some tabs to free memory"
            ))
        }
        
        // CPU alerts
        if metrics.cpuUsage > alertThresholds.cpuCritical {
            newAlerts.append(PerformanceAlert(
                type: .cpuHigh,
                severity: .critical,
                message: "CPU usage is critically high (\(String(format: "%.1f", metrics.cpuUsage))%)",
                timestamp: Date(),
                suggestedAction: "Check for intensive web pages or close unnecessary tabs"
            ))
        } else if metrics.cpuUsage > alertThresholds.cpuWarning {
            newAlerts.append(PerformanceAlert(
                type: .cpuHigh,
                severity: .warning,
                message: "CPU usage is elevated (\(String(format: "%.1f", metrics.cpuUsage))%)",
                timestamp: Date(),
                suggestedAction: "Monitor for resource-intensive web pages"
            ))
        }
        
        // Tab count alerts
        if metrics.tabCount > alertThresholds.tabCritical {
            newAlerts.append(PerformanceAlert(
                type: .tabsExcessive,
                severity: .critical,
                message: "Too many tabs open (\(metrics.tabCount))",
                timestamp: Date(),
                suggestedAction: "Close unused tabs to improve performance"
            ))
        } else if metrics.tabCount > alertThresholds.tabWarning {
            newAlerts.append(PerformanceAlert(
                type: .tabsExcessive,
                severity: .warning,
                message: "Many tabs are open (\(metrics.tabCount))",
                timestamp: Date(),
                suggestedAction: "Consider hibernating inactive tabs"
            ))
        }
        
        // Update alerts (keep only recent ones)
        alerts = newAlerts + alerts.filter { Date().timeIntervalSince($0.timestamp) < 300 } // Keep for 5 minutes
        
        // Limit alert count
        if alerts.count > 10 {
            alerts = Array(alerts.prefix(10))
        }
    }
    
    // MARK: - Event Handlers
    private func handleMemoryPressureChange(_ pressureLevel: TabHibernationManager.MemoryPressureLevel) {
        switch pressureLevel {
        case .critical:
            addAlert(PerformanceAlert(
                type: .memoryHigh,
                severity: .critical,
                message: "System memory pressure is critical",
                timestamp: Date(),
                suggestedAction: "Tabs will be hibernated automatically"
            ))
            
        case .warning:
            addAlert(PerformanceAlert(
                type: .memoryHigh,
                severity: .warning,
                message: "System memory pressure detected",
                timestamp: Date(),
                suggestedAction: "Close unnecessary applications"
            ))
            
        case .normal:
            // Remove memory pressure alerts when returning to normal
            alerts.removeAll { alert in
                alert.type == .memoryHigh && Date().timeIntervalSince(alert.timestamp) < 60
            }
        }
    }
    
    private func handlePerformanceLevelChange(_ newLevel: PerformanceLevel) {
        print("Performance level changed to: \(newLevel.rawValue)")
        
        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .performanceLevelChanged,
            object: newLevel
        )
        
        // Take automatic actions based on performance level
        switch newLevel {
        case .critical:
            // Force aggressive hibernation
            TabHibernationManager.shared.forceGarbageCollection()
            
        case .warning:
            // Suggest hibernation
            addAlert(PerformanceAlert(
                type: .memoryHigh,
                severity: .info,
                message: "Performance optimization recommended",
                timestamp: Date(),
                suggestedAction: "Some tabs will be hibernated to improve performance"
            ))
            
        case .good, .optimal:
            break
        }
    }
    
    // MARK: - Public Methods
    func addAlert(_ alert: PerformanceAlert) {
        alerts.insert(alert, at: 0)
    }
    
    func dismissAlert(_ alert: PerformanceAlert) {
        alerts.removeAll { $0.id == alert.id }
    }
    
    func clearAllAlerts() {
        alerts.removeAll()
    }
    
    func getPerformanceReport() -> String {
        let metrics = currentMetrics
        return """
        Performance Report - \(Date().formatted())
        
        System Metrics:
        • Memory Usage: \(metrics.memoryUsage)MB
        • CPU Usage: \(String(format: "%.1f", metrics.cpuUsage))%
        • Performance Level: \(performanceLevel.rawValue)
        
        Tab Management:
        • Total Tabs: \(metrics.tabCount)
        • Hibernated: \(metrics.hibernatedTabCount)
        • Active WebViews: \(metrics.webViewCount)
        
        Alerts: \(alerts.count) active
        """
    }
    
    func exportMetricsCSV() -> String {
        let metrics = currentMetrics
        let timestamp = Date().timeIntervalSince1970
        
        return """
        timestamp,memory_mb,cpu_percent,tabs_total,tabs_hibernated,performance_level
        \(timestamp),\(metrics.memoryUsage),\(metrics.cpuUsage),\(metrics.tabCount),\(metrics.hibernatedTabCount),\(performanceLevel.rawValue)
        """
    }
    
    func toggleMonitoring() {
        isMonitoringEnabled.toggle()
        
        if !isMonitoringEnabled {
            // Clear metrics when disabled
            currentMetrics = PerformanceMetrics()
            performanceLevel = .optimal
            alerts.removeAll()
        }
    }
    
    deinit {
        metricsTimer.invalidate()
        cancellables.removeAll()
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let performanceLevelChanged = Notification.Name("performanceLevelChanged")
    static let performanceAlertAdded = Notification.Name("performanceAlertAdded")
}