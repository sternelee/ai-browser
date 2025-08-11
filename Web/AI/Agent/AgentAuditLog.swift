import Foundation

/// Lightweight local audit log for agent actions (M2 baseline)
@MainActor
final class AgentAuditLog {
    static let shared = AgentAuditLog()

    struct Entry: Codable, Identifiable {
        let id: UUID
        let timestamp: Date
        let host: String?
        let action: String
        let parameters: [String: String]?
        let policyAllowed: Bool
        let policyReason: String?
        let requestedConsent: Bool
        let userConsented: Bool?
        let outcomeSuccess: Bool?
        let outcomeMessage: String?
    }

    private var entries: [Entry] = []
    private let fileURL: URL

    private init() {
        let fm = FileManager.default
        let appSupport =
            (try? fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("WebAgent", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("agent_audit_log.json")
        load()
    }

    func append(
        host: String?,
        action: String,
        parameters: [String: String]?,
        policyAllowed: Bool,
        policyReason: String?,
        requestedConsent: Bool,
        userConsented: Bool?,
        outcomeSuccess: Bool?,
        outcomeMessage: String?
    ) {
        let entry = Entry(
            id: UUID(),
            timestamp: Date(),
            host: host,
            action: action,
            parameters: parameters,
            policyAllowed: policyAllowed,
            policyReason: policyReason,
            requestedConsent: requestedConsent,
            userConsented: userConsented,
            outcomeSuccess: outcomeSuccess,
            outcomeMessage: outcomeMessage
        )
        entries.append(entry)
        persist()
    }

    func all() -> [Entry] { entries }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Entry].self, from: data) { entries = decoded }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
