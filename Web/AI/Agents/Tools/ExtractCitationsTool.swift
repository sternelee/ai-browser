import Foundation

@MainActor
struct ExtractCitationsTool: AgentTool {
    let id: String = "extract_citations"
    let name: String = "Extract Citations"

    private let contextManager = ContextManager.shared
    private let tabManager: TabManager

    init(tabManager: TabManager) { self.tabManager = tabManager }

    func run(parameters: [String: Any]) async throws -> [String: Any] {
        guard let context = await contextManager.extractCurrentPageContext(from: tabManager) else {
            return ["quotes": []]
        }
        let quotes = ResearchSynthesis.buildCitations(from: context, limit: 3)
        let payload = quotes.map {
            [
                "url": $0.url,
                "title": $0.title,
                "quote": $0.quote,
                "startIndex": $0.startIndex,
                "endIndex": $0.endIndex,
            ]
        }
        return ["quotes": payload]
    }
}
