import Foundation

@MainActor
final class ResearchPlanner {
    static let shared = ResearchPlanner()

    func plan(question: String) -> [String] {
        // Stub: return sub-questions in the future; keep minimal for M1
        return [question]
    }
}
