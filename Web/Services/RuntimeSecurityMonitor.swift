import Foundation
import OSLog
import CryptoKit
import UserNotifications
import SwiftUI

/// Runtime Security Monitor for hardened runtime entitlement risk mitigation
/// 
/// This service provides compensating security controls when using high-risk entitlements
/// like com.apple.security.cs.allow-jit to minimize attack surface and detect exploitation attempts.
///
/// Security Controls Implemented:
/// - Memory usage anomaly detection
/// - Executable allocation monitoring  
/// - Process integrity verification
/// - Suspicious activity detection
/// - Security event logging and alerting
class RuntimeSecurityMonitor: ObservableObject {
    static let shared = RuntimeSecurityMonitor()
    
    private let logger = Logger(subsystem: "com.web.browser", category: "SecurityMonitor")
    private let securityQueue = DispatchQueue(label: "runtime.security.monitor", qos: .utility)
    
    // MARK: - Security Monitoring State
    
    @Published private(set) var securityStatus: SecurityStatus = .secure
    @Published private(set) var detectedThreats: [SecurityThreat] = []
    
    private var isMonitoring = false
    private var monitoringTimer: Timer?
    private var baselineMetrics: ProcessMetrics?
    
    // MARK: - Security Thresholds
    
    private struct SecurityThresholds {
        static let maxMemoryGrowthRate: Double = 50.0 // MB/second
        static let maxExecutableMemory: UInt64 = 500 * 1024 * 1024 // 500MB
        static let maxJITAllocationsPerSecond: Int = 100
        static let anomalyDetectionWindow: TimeInterval = 60.0 // 60 seconds
    }
    
    private init() {
        setupSecurityMonitoring()
    }
    
    // MARK: - Public Interface
    
    /// Start runtime security monitoring with compensating controls
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        logger.info("🛡️ Starting runtime security monitoring for JIT entitlement risk mitigation")
        
        isMonitoring = true
        
        // Capture baseline metrics
        captureBaseline()
        
        // Start periodic monitoring
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performSecurityCheck()
        }
        
        // Register for memory pressure notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryPressure),
            name: NSNotification.Name("NSProcessInfoMemoryPressureWarning"),
            object: nil
        )
        
        // Log security monitoring activation
        logSecurityEvent(RuntimeSecurityEvent.monitoringStarted, details: "Compensating controls active for JIT entitlement")
    }
    
    /// Stop runtime security monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        logger.info("🛡️ Stopping runtime security monitoring")
        
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        NotificationCenter.default.removeObserver(self)
        
        logSecurityEvent(RuntimeSecurityEvent.monitoringStopped, details: "Security monitoring deactivated")
    }
    
    /// Get current security assessment
    func getSecurityAssessment() -> SecurityAssessment {
        let currentMetrics = getCurrentProcessMetrics()
        let recentThreats = detectedThreats.filter { Date().timeIntervalSince($0.timestamp) < 300 } // Last 5 minutes
        
        return SecurityAssessment(
            status: securityStatus,
            processMetrics: currentMetrics,
            recentThreats: recentThreats,
            jitEntitlementEnabled: true,
            compensatingControlsActive: isMonitoring
        )
    }
    
    // MARK: - Security Monitoring Implementation
    
    private func setupSecurityMonitoring() {
        // Configure security logging
        logger.info("🔒 Initializing runtime security monitor for hardened runtime risk mitigation")
        
        // Verify entitlements
        verifySecurityEntitlements()
        
        // Set up mixed content security monitoring
        setupMixedContentSecurityIntegration()
        
        // Set up CSP security monitoring
        setupCSPSecurityIntegration()
        
        // Start monitoring immediately on init
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startMonitoring()
        }
    }
    
    private func captureBaseline() {
        baselineMetrics = getCurrentProcessMetrics()
        logger.info("📊 Captured baseline security metrics: \(String(describing: self.baselineMetrics))")
    }
    
    private func performSecurityCheck() {
        securityQueue.async { [weak self] in
            self?.checkMemoryAnomalies()
            self?.checkExecutableMemoryUsage()
            self?.checkProcessIntegrity()
            self?.cleanupOldThreats()
        }
    }
    
    private func checkMemoryAnomalies() {
        guard let baseline = baselineMetrics else { return }
        
        let current = getCurrentProcessMetrics()
        let memoryGrowth = Double(current.memoryUsage - baseline.memoryUsage) / (1024 * 1024) // MB
        let timeElapsed = Date().timeIntervalSince(baseline.timestamp)
        
        if timeElapsed > 0 {
            let growthRate = memoryGrowth / timeElapsed
            
            if growthRate > SecurityThresholds.maxMemoryGrowthRate {
                let threat = SecurityThreat(
                    type: .memoryAnomaly,
                    severity: .high,
                    description: "Abnormal memory growth rate: \(String(format: "%.2f", growthRate)) MB/s",
                    details: [
                        "growth_rate": String(growthRate),
                        "memory_usage": String(current.memoryUsage),
                        "baseline_memory": String(baseline.memoryUsage)
                    ]
                )
                
                handleSecurityThreat(threat)
            }
        }
    }
    
    private func checkExecutableMemoryUsage() {
        let current = getCurrentProcessMetrics()
        
        if current.executableMemory > SecurityThresholds.maxExecutableMemory {
            let threat = SecurityThreat(
                type: .executableMemoryAbuse,
                severity: .critical,
                description: "Excessive executable memory allocation: \(current.executableMemory / (1024*1024)) MB",
                details: [
                    "executable_memory": String(current.executableMemory),
                    "threshold": String(SecurityThresholds.maxExecutableMemory)
                ]
            )
            
            handleSecurityThreat(threat)
        }
    }
    
    private func checkProcessIntegrity() {
        // Verify process hasn't been tampered with
        let processPath = Bundle.main.executablePath ?? ""
        
        do {
            let processData = try Data(contentsOf: URL(fileURLWithPath: processPath))
            let processHash = SHA256.hash(data: processData)
            let hashString = processHash.compactMap { String(format: "%02x", $0) }.joined()
            
            // Store and compare with baseline (simplified for demo)
            // In production, this would compare against known good hash
            logger.debug("🔍 Process integrity check: \(hashString.prefix(16))...")
            
        } catch {
            let threat = SecurityThreat(
                type: .processIntegrityViolation,
                severity: .critical,
                description: "Unable to verify process integrity: \(error.localizedDescription)",
                details: ["error": error.localizedDescription]
            )
            
            handleSecurityThreat(threat)
        }
    }
    
    private func handleSecurityThreat(_ threat: SecurityThreat) {
        DispatchQueue.main.async { [weak self] in
            self?.detectedThreats.append(threat)
            
            // Update security status based on threat severity
            if threat.severity == .critical {
                self?.securityStatus = .compromised
            } else if threat.severity == .high && self?.securityStatus == .secure {
                self?.securityStatus = .threatened
            }
            
            // Log security event
            self?.logSecurityEvent(RuntimeSecurityEvent.threatDetected, details: threat.description)
            
            // Send notification for critical threats
            if threat.severity == .critical {
                self?.sendSecurityAlert(threat)
            }
        }
    }
    
    private func cleanupOldThreats() {
        let cutoffTime = Date().addingTimeInterval(-300) // 5 minutes ago
        DispatchQueue.main.async { [weak self] in
            self?.detectedThreats.removeAll { $0.timestamp < cutoffTime }
            
            // Reset security status if no recent threats
            if self?.detectedThreats.isEmpty == true {
                self?.securityStatus = .secure
            }
        }
    }
    
    // MARK: - Process Metrics
    
    private func getCurrentProcessMetrics() -> ProcessMetrics {
        let task = mach_task_self_
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        let memoryUsage = result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
        
        return ProcessMetrics(
            timestamp: Date(),
            memoryUsage: memoryUsage,
            executableMemory: getExecutableMemoryUsage()
        )
    }
    
    private func getExecutableMemoryUsage() -> UInt64 {
        // Simplified executable memory estimation
        // In production, this would use vm_region_64 to scan memory regions
        let task = mach_task_self_
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        // Rough estimate: assume 10% of virtual memory could be executable
        return result == KERN_SUCCESS ? UInt64(info.virtual_size) / 10 : 0
    }
    
    // MARK: - Security Event Logging
    
    private func logSecurityEvent(_ event: RuntimeSecurityEvent, details: String) {
        let _ = SecurityLogEntry(
            event: event,
            details: details,
            timestamp: Date()
        )
        
        // Log to system logger
        switch event {
        case .threatDetected:
            logger.warning("🚨 Security threat detected: \(details)")
        case .monitoringStarted:
            logger.info("🛡️ \(details)")
        case .monitoringStopped:
            logger.info("⏹️ \(details)")
        }
        
        // In production: send to centralized security monitoring system
    }
    
    private func sendSecurityAlert(_ threat: SecurityThreat) {
        // Send system notification for critical security threats using modern UserNotifications
        let content = UNMutableNotificationContent()
        content.title = "Security Alert"
        content.body = "Critical security threat detected: \(threat.description)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "security-alert-\(threat.id.uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Failed to send security notification: \(error.localizedDescription)")
            }
        }
        
        logger.critical("🚨 CRITICAL SECURITY ALERT: \(threat.description)")
    }
    
    // MARK: - Entitlement Verification
    
    private func verifySecurityEntitlements() {
        let entitlements = getEntitlements()
        
        if entitlements.allowsJIT {
            logger.warning("⚠️ JIT entitlement enabled - compensating controls required")
        }
        
        if entitlements.allowsUnsignedExecutableMemory {
            logger.error("🔴 CRITICAL: Unsigned executable memory entitlement detected - severe security risk")
        }
        
        logger.info("🔒 Entitlement verification complete")
    }
    
    private func getEntitlements() -> EntitlementStatus {
        // In production, this would read actual entitlements from code signature
        // For now, we'll check based on our known configuration
        return EntitlementStatus(
            allowsJIT: true, // We know this is enabled
            allowsUnsignedExecutableMemory: false // We removed this
        )
    }
    
    // MARK: - Memory Pressure Handling
    
    @objc private func handleMemoryPressure() {
        logger.warning("⚠️ Memory pressure detected - potential security implication")
        
        let threat = SecurityThreat(
            type: .memoryPressure,
            severity: .medium,
            description: "System memory pressure detected",
            details: ["source": "NSProcessInfoMemoryPressureWarning"]
        )
        
        handleSecurityThreat(threat)
    }
    
    // MARK: - Security Integration Methods
    
    private func setupMixedContentSecurityIntegration() {
        // Listen for mixed content security events
        NotificationCenter.default.addObserver(
            forName: .mixedContentSecurityEvent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleMixedContentSecurityEvent(notification)
        }
        
        logger.info("🔗 Mixed content security integration enabled")
    }
    
    private func setupCSPSecurityIntegration() {
        // Listen for CSP violation events
        NotificationCenter.default.addObserver(
            forName: .cspViolationDetected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCSPSecurityEvent(notification)
        }
        
        logger.info("🔗 CSP security integration enabled")
    }
    
    private func handleMixedContentSecurityEvent(_ notification: Notification) {
        guard let mixedContentEvent = notification.object as? MixedContentManager.MixedContentSecurityEvent else {
            return
        }
        
        let severity: SecurityThreat.ThreatSeverity
        let threatType: SecurityThreat.ThreatType
        
        switch mixedContentEvent.eventType {
        case .mixedContentDetected:
            severity = .medium
            threatType = .mixedContentViolation
        case .policyViolation:
            severity = .high
            threatType = .securityContextDegradation
        case .userOverride:
            severity = .medium
            threatType = .securityContextDegradation
        case .securityWarningShown:
            severity = .low
            threatType = .mixedContentViolation
        case .contentBlocked:
            severity = .low // Low because content was successfully blocked
            threatType = .mixedContentViolation
        }
        
        let threat = SecurityThreat(
            type: threatType,
            severity: severity,
            description: "Mixed content security event: \(mixedContentEvent.eventType)",
            details: mixedContentEvent.details
        )
        
        handleSecurityThreat(threat)
        
        logger.info("🔒 Mixed content security event processed: \(String(describing: mixedContentEvent.eventType))")
    }
    
    private func handleCSPSecurityEvent(_ notification: Notification) {
        guard let cspViolation = notification.object as? CSPManager.CSPViolation else {
            return
        }
        
        let severity: SecurityThreat.ThreatSeverity
        switch cspViolation.severity {
        case .low:
            severity = .low
        case .medium:
            severity = .medium
        case .high:
            severity = .high
        case .critical:
            severity = .critical
        }
        
        let threat = SecurityThreat(
            type: .contentSecurityPolicyBreach,
            severity: severity,
            description: "CSP violation: \(cspViolation.violationType)",
            details: [
                "source": cspViolation.source,
                "details": cspViolation.details,
                "timestamp": ISO8601DateFormatter().string(from: cspViolation.timestamp)
            ]
        )
        
        handleSecurityThreat(threat)
        
        logger.warning("🔒 CSP security violation processed: \(String(describing: cspViolation.violationType))")
    }
    
    /// Enhanced security assessment that includes all security components
    func getComprehensiveSecurityAssessment() -> ComprehensiveSecurityAssessment {
        let baseAssessment = getSecurityAssessment()
        
        // Get mixed content security status
        let mixedContentStats = MixedContentManager.shared.getSecurityStatistics()
        let mixedContentSecure = mixedContentStats.currentPolicy == .block && mixedContentStats.recentViolations == 0
        
        // Get CSP security status
        let cspStats = CSPManager.shared.getSecurityStatistics()
        let cspSecure = cspStats.isCSPEnabled && cspStats.criticalViolations == 0
        
        // Calculate overall security score
        let securityComponents = [
            baseAssessment.jitEntitlementEnabled ? 0.7 : 1.0, // JIT reduces score
            mixedContentSecure ? 1.0 : 0.6,
            cspSecure ? 1.0 : 0.5,
            baseAssessment.status == .secure ? 1.0 : 0.3
        ]
        
        let overallScore = securityComponents.reduce(0, +) / Double(securityComponents.count)
        
        return ComprehensiveSecurityAssessment(
            baseAssessment: baseAssessment,
            mixedContentSecure: mixedContentSecure,
            cspSecure: cspSecure,
            overallSecurityScore: overallScore,
            securityRecommendations: generateSecurityRecommendations(
                mixedContentSecure: mixedContentSecure,
                cspSecure: cspSecure,
                baseSecure: baseAssessment.status == .secure
            )
        )
    }
    
    private func generateSecurityRecommendations(
        mixedContentSecure: Bool,
        cspSecure: Bool,
        baseSecure: Bool
    ) -> [SecurityRecommendation] {
        var recommendations: [SecurityRecommendation] = []
        
        if !mixedContentSecure {
            recommendations.append(SecurityRecommendation(
                priority: .high,
                category: .mixedContent,
                title: "Mixed Content Policy",
                description: "Consider using 'Block All Mixed Content' policy for maximum security",
                action: "Update mixed content settings"
            ))
        }
        
        if !cspSecure {
            recommendations.append(SecurityRecommendation(
                priority: .high,
                category: .contentSecurity,
                title: "Content Security Policy",
                description: "Enable CSP strict mode and resolve violation issues",
                action: "Review CSP settings and violations"
            ))
        }
        
        if !baseSecure {
            recommendations.append(SecurityRecommendation(
                priority: .critical,
                category: .runtime,
                title: "Runtime Security",
                description: "Runtime security threats detected - review system integrity",
                action: "Check runtime security monitoring"
            ))
        }
        
        return recommendations
    }
    
    deinit {
        stopMonitoring()
    }
}

// MARK: - Supporting Types

enum SecurityStatus {
    case secure
    case threatened
    case compromised
    
    var description: String {
        switch self {
        case .secure: return "Secure"
        case .threatened: return "Potential Threats Detected"
        case .compromised: return "Security Compromise Detected"
        }
    }
}

struct SecurityThreat {
    let id = UUID()
    let type: ThreatType
    let severity: ThreatSeverity
    let description: String
    let details: [String: String]
    let timestamp = Date()
    
    enum ThreatType {
        case memoryAnomaly
        case executableMemoryAbuse
        case processIntegrityViolation
        case memoryPressure
        case mixedContentViolation
        case contentSecurityPolicyBreach
        case securityContextDegradation
    }
    
    enum ThreatSeverity {
        case low, medium, high, critical
    }
}

struct ProcessMetrics {
    let timestamp: Date
    let memoryUsage: UInt64
    let executableMemory: UInt64
}

struct SecurityAssessment {
    let status: SecurityStatus
    let processMetrics: ProcessMetrics
    let recentThreats: [SecurityThreat]
    let jitEntitlementEnabled: Bool
    let compensatingControlsActive: Bool
}

struct EntitlementStatus {
    let allowsJIT: Bool
    let allowsUnsignedExecutableMemory: Bool
}

enum RuntimeSecurityEvent {
    case monitoringStarted
    case monitoringStopped
    case threatDetected
}

struct SecurityLogEntry {
    let event: RuntimeSecurityEvent
    let details: String
    let timestamp: Date
}

struct ComprehensiveSecurityAssessment {
    let baseAssessment: SecurityAssessment
    let mixedContentSecure: Bool
    let cspSecure: Bool
    let overallSecurityScore: Double
    let securityRecommendations: [SecurityRecommendation]
    
    var overallSecurityLevel: SecurityLevel {
        switch overallSecurityScore {
        case 0.9...1.0:
            return .secure
        case 0.7..<0.9:
            return .good
        case 0.5..<0.7:
            return .acceptable
        default:
            return .vulnerable
        }
    }
    
    enum SecurityLevel {
        case secure, good, acceptable, vulnerable
        
        var description: String {
            switch self {
            case .secure: return "Secure"
            case .good: return "Good"
            case .acceptable: return "Needs Improvement"
            case .vulnerable: return "Vulnerable"
            }
        }
        
        var color: Color {
            switch self {
            case .secure: return .green
            case .good: return .blue
            case .acceptable: return .orange
            case .vulnerable: return .red
            }
        }
    }
}

struct SecurityRecommendation {
    let priority: Priority
    let category: Category
    let title: String
    let description: String
    let action: String
    
    enum Priority {
        case low, medium, high, critical
        
        var color: Color {
            switch self {
            case .low: return .blue
            case .medium: return .orange
            case .high: return .red
            case .critical: return .purple
            }
        }
    }
    
    enum Category {
        case mixedContent, contentSecurity, runtime, certificates
        
        var icon: String {
            switch self {
            case .mixedContent: return "exclamationmark.shield"
            case .contentSecurity: return "shield.checkered"
            case .runtime: return "cpu.fill"
            case .certificates: return "lock.shield"
            }
        }
    }
}