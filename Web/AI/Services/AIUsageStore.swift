import Foundation

/// Persisted usage event for AI requests
struct AIUsageEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let providerId: String
    let modelId: String
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let estimatedCostUSD: Double?
    let success: Bool
    let latencyMs: Int
    let contextIncluded: Bool
}

/// Aggregated usage totals
struct AIUsageTotals: Codable {
    let providerId: String
    let modelId: String
    let requestCount: Int
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let estimatedCostUSD: Double
}

/// On-device usage event store with basic aggregation and CSV export
@MainActor
final class AIUsageStore: ObservableObject {
    static let shared = AIUsageStore()

    @Published private(set) var events: [AIUsageEvent] = []

    private let fileManager = FileManager.default
    private let storageURL: URL
    private let ioQueue = DispatchQueue(label: "ai.usagestore.io")

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let dir = appSupport.appendingPathComponent("Web/AI/Usage", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("usage_events.json")
        load()
    }

    func appendEvent(_ event: AIUsageEvent) {
        events.append(event)
        persistAsync()
    }

    func append(
        providerId: String,
        modelId: String,
        promptTokens: Int,
        completionTokens: Int,
        estimatedCostUSD: Double?,
        success: Bool,
        latencyMs: Int,
        contextIncluded: Bool
    ) {
        let total = promptTokens + completionTokens
        let event = AIUsageEvent(
            id: UUID(),
            timestamp: Date(),
            providerId: providerId,
            modelId: modelId,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: total,
            estimatedCostUSD: estimatedCostUSD,
            success: success,
            latencyMs: latencyMs,
            contextIncluded: contextIncluded
        )
        appendEvent(event)
    }

    func events(in range: ClosedRange<Date>) -> [AIUsageEvent] {
        events.filter { range.contains($0.timestamp) }
    }

    func aggregate(byProviderOnly: Bool = false, in range: ClosedRange<Date>? = nil)
        -> [AIUsageTotals]
    {
        let filtered = range == nil ? events : events(in: range!)
        var map: [String: (Int, Int, Int, Int, Double)] = [:]  // key -> (requests, prompt, completion, total, cost)
        for e in filtered {
            let key = byProviderOnly ? e.providerId : (e.providerId + "::" + e.modelId)
            let current = map[key] ?? (0, 0, 0, 0, 0)
            map[key] = (
                current.0 + 1,
                current.1 + e.promptTokens,
                current.2 + e.completionTokens,
                current.3 + e.totalTokens,
                current.4 + (e.estimatedCostUSD ?? 0)
            )
        }
        return map.map { key, v in
            // Robustly extract provider and model by splitting on the "::" delimiter we used above
            let providerId: String
            let modelId: String
            if byProviderOnly {
                providerId = key
                modelId = "*"
            } else if let range = key.range(of: "::") {
                providerId = String(key[..<range.lowerBound])
                modelId = String(key[range.upperBound...])
            } else {
                providerId = key
                modelId = "*"
            }
            return AIUsageTotals(
                providerId: providerId,
                modelId: modelId,
                requestCount: v.0,
                promptTokens: v.1,
                completionTokens: v.2,
                totalTokens: v.3,
                estimatedCostUSD: v.4
            )
        }
    }

    func exportCSV(in range: ClosedRange<Date>? = nil) -> String {
        let df = ISO8601DateFormatter()
        let rows =
            [
                "timestamp,provider,model,promptTokens,completionTokens,totalTokens,estimatedCostUSD,success,latencyMs,contextIncluded"
            ]
            + (range == nil ? events : events(in: range!)).map { e in
                let ts = df.string(from: e.timestamp)
                let cost = e.estimatedCostUSD.map { String(format: "%.6f", $0) } ?? ""
                return
                    "\(ts),\(e.providerId),\(e.modelId),\(e.promptTokens),\(e.completionTokens),\(e.totalTokens),\(cost),\(e.success),\(e.latencyMs),\(e.contextIncluded)"
            }
        return rows.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func persistAsync() {
        let snapshot = events
        ioQueue.async { [storageURL] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try data.write(to: storageURL, options: .atomic)
            } catch {
                AppLog.warn("Failed to persist AI usage events: \(error.localizedDescription)")
            }
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let items = try decoder.decode([AIUsageEvent].self, from: data)
            self.events = items
        } catch {
            AppLog.warn("Failed to load AI usage events: \(error.localizedDescription)")
            self.events = []
        }
    }
}
