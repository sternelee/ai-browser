import SwiftUI

/**
 * CSPSecuritySettingsView - User interface for Content Security Policy management
 * 
 * Provides users with comprehensive control over CSP settings, violation monitoring,
 * and security event analysis.
 */
struct CSPSecuritySettingsView: View {
    @StateObject private var cspManager = CSPManager.shared
    @State private var showingViolationDetails = false
    @State private var selectedViolation: CSPManager.CSPViolation?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text("Content Security Policy")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Advanced script injection protection and security monitoring")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Security Status
            SecurityStatusSection()
            
            Divider()
            
            // CSP Settings
            CSPSettingsSection()
            
            Divider()
            
            // Security Violations
            SecurityViolationsSection(
                showingDetails: $showingViolationDetails,
                selectedViolation: $selectedViolation
            )
            
            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $showingViolationDetails) {
            if let violation = selectedViolation {
                ViolationDetailsView(violation: violation)
            }
        }
    }
}

// MARK: - Security Status Section

private struct SecurityStatusSection: View {
    @ObservedObject private var cspManager = CSPManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Security Status")
                    .font(.headline)
                
                Spacer()
                
                SecurityStatusIndicator()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 15) {
                SecurityMetricCard(
                    title: "Total Violations",
                    value: "\(cspManager.cspViolations.count)",
                    color: cspManager.cspViolations.isEmpty ? .green : .orange,
                    icon: "exclamationmark.triangle"
                )
                
                SecurityMetricCard(
                    title: "Critical Events",
                    value: "\(cspManager.cspViolations.filter { $0.severity == .critical }.count)",
                    color: cspManager.cspViolations.filter { $0.severity == .critical }.isEmpty ? .green : .red,
                    icon: "exclamationmark.octagon"
                )
                
                SecurityMetricCard(
                    title: "Blocked Attempts",
                    value: "\(cspManager.blockedInjectionAttempts)",
                    color: .blue,
                    icon: "shield.slash"
                )
            }
        }
    }
}

private struct SecurityStatusIndicator: View {
    @ObservedObject private var cspManager = CSPManager.shared
    
    private var statusColor: Color {
        let criticalCount = cspManager.cspViolations.filter { $0.severity == .critical }.count
        
        if !cspManager.isCSPEnabled {
            return .red
        } else if criticalCount > 0 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var statusText: String {
        let criticalCount = cspManager.cspViolations.filter { $0.severity == .critical }.count
        
        if !cspManager.isCSPEnabled {
            return "CSP Disabled"
        } else if criticalCount > 0 {
            return "Security Issues"
        } else {
            return "Protected"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.1))
        .cornerRadius(12)
    }
}

private struct SecurityMetricCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - CSP Settings Section

private struct CSPSettingsSection: View {
    @ObservedObject private var cspManager = CSPManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("CSP Configuration")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Content Security Policy", isOn: $cspManager.isCSPEnabled)
                    .onChange(of: cspManager.isCSPEnabled) {
                        cspManager.saveConfiguration()
                    }
                
                Toggle("Strict Mode", isOn: $cspManager.strictModeEnabled)
                    .disabled(!cspManager.isCSPEnabled)
                    .onChange(of: cspManager.strictModeEnabled) {
                        cspManager.saveConfiguration()
                    }
                
                Toggle("Violation Reporting", isOn: $cspManager.violationReportingEnabled)
                    .disabled(!cspManager.isCSPEnabled)
                    .onChange(of: cspManager.violationReportingEnabled) {
                        cspManager.saveConfiguration()
                    }
                
                Toggle("Script Integrity Checks", isOn: $cspManager.scriptIntegrityChecksEnabled)
                    .disabled(!cspManager.isCSPEnabled)
                    .onChange(of: cspManager.scriptIntegrityChecksEnabled) {
                        cspManager.saveConfiguration()
                    }
            }
            
            // Security Level Description
            if cspManager.isCSPEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Security Level: \(cspManager.strictModeEnabled ? "Strict" : "Standard")")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(cspManager.strictModeEnabled ? 
                         "Maximum protection with strict CSP policies and comprehensive validation." :
                         "Balanced protection with standard CSP policies and input validation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Security Violations Section

private struct SecurityViolationsSection: View {
    @ObservedObject private var cspManager = CSPManager.shared
    @Binding var showingDetails: Bool
    @Binding var selectedViolation: CSPManager.CSPViolation?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Recent Security Events")
                    .font(.headline)
                
                Spacer()
                
                if !cspManager.cspViolations.isEmpty {
                    Button("Clear All") {
                        cspManager.cspViolations.removeAll()
                    }
                    .font(.caption)
                }
            }
            
            if cspManager.cspViolations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    
                    Text("No Security Violations")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Your browser is secure from script injection attacks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(cspManager.cspViolations.prefix(10), id: \.id) { violation in
                            ViolationRowView(violation: violation) {
                                selectedViolation = violation
                                showingDetails = true
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
}

private struct ViolationRowView: View {
    let violation: CSPManager.CSPViolation
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Severity indicator
            Circle()
                .fill(violation.severity.color)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(violationTypeDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(timeAgo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(violation.source)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(violation.details)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onTapGesture {
            onTap()
        }
    }
    
    private var violationTypeDescription: String {
        switch violation.violationType {
        case .scriptTampering: return "Script Tampering"
        case .invalidNonce: return "Invalid Nonce"
        case .unexpectedMessageHandler: return "Unexpected Handler"
        case .potentialXSS: return "Potential XSS"
        case .rateLimitExceeded: return "Rate Limit Exceeded"
        case .integrityFailure: return "Integrity Failure"
        case .unauthorizedScriptExecution: return "Unauthorized Script"
        }
    }
    
    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: violation.timestamp, relativeTo: Date())
    }
}

// MARK: - Violation Details View

private struct ViolationDetailsView: View {
    let violation: CSPManager.CSPViolation
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(violation.severity.color)
                            .frame(width: 12, height: 12)
                        
                        Text(violationTypeDescription)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                    }
                    
                    Text("Severity: \(severityDescription)")
                        .font(.subheadline)
                        .foregroundColor(violation.severity.color)
                }
                
                Divider()
                
                // Details
                VStack(alignment: .leading, spacing: 16) {
                    DetailRow(title: "Source", value: violation.source)
                    DetailRow(title: "Timestamp", value: dateFormatter.string(from: violation.timestamp))
                    DetailRow(title: "Details", value: violation.details)
                    DetailRow(title: "Violation ID", value: violation.id.uuidString)
                }
                
                Spacer()
            }
            .padding(20)
            .navigationTitle("Security Violation")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private var violationTypeDescription: String {
        switch violation.violationType {
        case .scriptTampering: return "Script Tampering Detected"
        case .invalidNonce: return "Invalid Nonce"
        case .unexpectedMessageHandler: return "Unexpected Message Handler"
        case .potentialXSS: return "Potential XSS Attack"
        case .rateLimitExceeded: return "Rate Limit Exceeded"
        case .integrityFailure: return "Script Integrity Failure"
        case .unauthorizedScriptExecution: return "Unauthorized Script Execution"
        }
    }
    
    private var severityDescription: String {
        switch violation.severity {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Preview

struct CSPSecuritySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        CSPSecuritySettingsView()
            .frame(width: 600, height: 500)
    }
}