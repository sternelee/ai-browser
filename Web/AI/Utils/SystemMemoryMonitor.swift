import Foundation
import os

/// System memory monitor for AI operations
/// Provides real-time memory pressure detection and optimization recommendations
class SystemMemoryMonitor {
    
    static let shared = SystemMemoryMonitor()
    
    private let logger = Logger(subsystem: "com.web.ai", category: "memory")
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    // MARK: - Memory Thresholds (in GB)
    
    struct MemoryThresholds {
        static let lowMemoryWarning: Double = 1.0    // < 1GB available
        static let criticalMemory: Double = 0.5      // < 0.5GB available  
        static let aiOptimalMemory: Double = 4.0     // 4GB+ for optimal AI performance
    }
    
    // MARK: - Memory Status
    
    enum MemoryPressureLevel: String, CaseIterable {
        case normal = "Normal"
        case warning = "Warning" 
        case critical = "Critical"
    }
    
    struct MemoryStatus {
        let totalMemory: Double
        let availableMemory: Double
        let usedMemory: Double
        let pressureLevel: MemoryPressureLevel
        let aiRecommendation: AIMemoryRecommendation
    }
    
    enum AIMemoryRecommendation: String {
        case optimal = "Optimal - Full AI capabilities available"
        case reduced = "Reduced - Use lighter model quantization"
        case minimal = "Minimal - Consider disabling AI features"
        case critical = "Critical - AI operations should be suspended"
    }
    
    private init() {
        startMemoryPressureMonitoring()
        logger.info("🧠 System Memory Monitor initialized")
    }
    
    // MARK: - Public Interface
    
    /// Get current memory status
    func getCurrentMemoryStatus() -> MemoryStatus {
        let memInfo = getSystemMemoryInfo()
        let pressureLevel = determinePressureLevel(availableMemory: memInfo.available)
        let aiRecommendation = getAIRecommendation(availableMemory: memInfo.available, pressureLevel: pressureLevel)
        
        return MemoryStatus(
            totalMemory: memInfo.total,
            availableMemory: memInfo.available,
            usedMemory: memInfo.used,
            pressureLevel: pressureLevel,
            aiRecommendation: aiRecommendation
        )
    }
    
    /// Check if AI operations are safe to perform
    func isAISafeToRun() -> Bool {
        let status = getCurrentMemoryStatus()
        return status.pressureLevel != .critical && status.availableMemory > MemoryThresholds.lowMemoryWarning
    }
    
    /// Get recommended model quantization level based on available memory
    func getRecommendedQuantization() -> ModelQuantizationLevel {
        let available = getCurrentMemoryStatus().availableMemory
        
        if available >= MemoryThresholds.aiOptimalMemory {
            return .q8_0  // Full precision for optimal quality
        } else if available >= 2.0 {
            return .q4_k_m  // Balanced quality/memory
        } else if available >= 1.0 {
            return .q4_0  // Minimal memory usage
        } else {
            return .suspended  // Suspend AI operations
        }
    }
    
    // MARK: - Private Methods
    
    private func getSystemMemoryInfo() -> (total: Double, available: Double, used: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else {
            logger.error("Failed to get memory info: \(kerr)")
            return (total: 8.0, available: 4.0, used: 4.0) // Safe fallback values
        }
        
        // Get system memory info
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        
        guard result == KERN_SUCCESS else {
            logger.error("Failed to get VM statistics: \(result)")
            return (total: 8.0, available: 4.0, used: 4.0)
        }
        
        let pageSize = vm_kernel_page_size
        let totalMemory = Double(stats.free_count + stats.active_count + stats.inactive_count + stats.wire_count) * Double(pageSize) / (1024 * 1024 * 1024)
        
        // Available memory includes free + inactive pages (which can be reclaimed)
        // This gives a more accurate picture of what's actually available for new processes
        let availableMemory = Double(stats.free_count + stats.inactive_count) * Double(pageSize) / (1024 * 1024 * 1024)
        let usedMemory = totalMemory - availableMemory
        
        // Safety bounds check - ensure reasonable values
        let boundedTotal = max(totalMemory, 1.0)  // At least 1GB
        let boundedAvailable = max(min(availableMemory, boundedTotal), 0.1)  // Between 0.1GB and total
        let boundedUsed = boundedTotal - boundedAvailable
        
        logger.debug("🧠 Memory calculation: Total=\(String(format: "%.1f", boundedTotal))GB, Available=\(String(format: "%.1f", boundedAvailable))GB, Used=\(String(format: "%.1f", boundedUsed))GB")
        
        return (total: boundedTotal, available: boundedAvailable, used: boundedUsed)
    }
    
    private func determinePressureLevel(availableMemory: Double) -> MemoryPressureLevel {
        if availableMemory < MemoryThresholds.criticalMemory {
            return .critical
        } else if availableMemory < MemoryThresholds.lowMemoryWarning {
            return .warning
        } else {
            return .normal
        }
    }
    
    private func getAIRecommendation(availableMemory: Double, pressureLevel: MemoryPressureLevel) -> AIMemoryRecommendation {
        switch pressureLevel {
        case .critical:
            return .critical
        case .warning:
            return .minimal
        case .normal:
            if availableMemory >= MemoryThresholds.aiOptimalMemory {
                return .optimal
            } else {
                return .reduced
            }
        }
    }
    
    private func startMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: DispatchQueue.global(qos: .background))
        
        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            let status = self.getCurrentMemoryStatus()
            self.logger.info("🧠 Memory pressure changed: \(status.pressureLevel.rawValue) (\(String(format: "%.1f", status.availableMemory))GB available)")
            
            // Post notification for AI system to adjust behavior
            NotificationCenter.default.post(
                name: .memoryPressureChanged,
                object: nil,
                userInfo: ["status": status]
            )
        }
        
        memoryPressureSource?.resume()
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
}

// MARK: - Supporting Types

enum ModelQuantizationLevel: String, CaseIterable {
    case q8_0 = "Q8_0"      // Full precision (4.5GB)
    case q4_k_m = "Q4_K_M"  // Balanced (2.5GB) 
    case q4_0 = "Q4_0"      // Minimal (2.0GB)
    case suspended = "SUSPENDED" // AI operations suspended
}

// MARK: - Notifications

extension Notification.Name {
    static let memoryPressureChanged = Notification.Name("memoryPressureChanged")
}

// MARK: - Memory Optimization Extensions

extension SystemMemoryMonitor {
    
    /// Log detailed memory status for debugging
    func logMemoryStatus() {
        let status = getCurrentMemoryStatus()
        logger.info("""
        🧠 Memory Status Report:
           Total: \(String(format: "%.1f", status.totalMemory))GB
           Available: \(String(format: "%.1f", status.availableMemory))GB
           Used: \(String(format: "%.1f", status.usedMemory))GB
           Pressure: \(status.pressureLevel.rawValue)
           AI Recommendation: \(status.aiRecommendation.rawValue)
           Recommended Quantization: \(self.getRecommendedQuantization().rawValue)
        """)
    }
    
    /// Check if memory usage is within safe limits for AI operations
    func isMemoryUsageHealthy() -> (healthy: Bool, reason: String) {
        let status = getCurrentMemoryStatus()
        
        if status.pressureLevel == .critical {
            return (false, "Critical memory pressure - suspend AI operations")
        }
        
        if status.availableMemory < MemoryThresholds.lowMemoryWarning {
            return (false, "Low memory available (\(String(format: "%.1f", status.availableMemory))GB)")
        }
        
        if status.usedMemory / status.totalMemory > 0.9 {
            return (false, "High memory usage (\(String(format: "%.0f", (status.usedMemory / status.totalMemory) * 100))%)")
        }
        
        return (true, "Memory usage is healthy")
    }
    
    /// Get memory optimization suggestions
    func getOptimizationSuggestions() -> [String] {
        let status = getCurrentMemoryStatus()
        var suggestions: [String] = []
        
        switch status.pressureLevel {
        case .critical:
            suggestions.append("Suspend AI operations immediately")
            suggestions.append("Close unnecessary browser tabs")
            suggestions.append("Clear AI conversation history")
            
        case .warning:
            suggestions.append("Use lighter model quantization (Q4_0)")
            suggestions.append("Reduce AI context window size")
            suggestions.append("Enable tab hibernation")
            
        case .normal:
            if status.availableMemory < MemoryThresholds.aiOptimalMemory {
                suggestions.append("Consider using Q4_K_M quantization for better performance")
                suggestions.append("Monitor memory usage during AI operations")
            }
        }
        
        return suggestions
    }
}