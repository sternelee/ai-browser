import Foundation

@MainActor
final class ResearchOrchestrator {
    static let shared = ResearchOrchestrator()

    func synthesizeTLDR(from text: String, with assistant: AIAssistant) async throws -> String {
        // For M1, defer to AIAssistant TL;DR
        return try await assistant.generatePageTLDR()
    }
}
