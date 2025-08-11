import Foundation

@MainActor
struct ScrapeTool: AgentTool {
    let id: String = "scrape"
    let name: String = "Scrape Page"

    private let contextManager = ContextManager.shared
    private let tabManager: TabManager

    init(tabManager: TabManager) { self.tabManager = tabManager }

    func run(parameters: [String: Any]) async throws -> [String: Any] {
        guard let context = await contextManager.extractCurrentPageContext(from: tabManager) else {
            return ["title": "", "headings": [], "links": [], "snippet": ""]
        }
        let snippet = String(context.text.prefix(800))
        return [
            "title": context.title,
            "headings": context.headings,
            "links": context.links,
            "snippet": snippet,
        ]
    }
}
