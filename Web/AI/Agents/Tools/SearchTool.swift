import Foundation

@MainActor
struct SearchTool: AgentTool {
    let id: String = "search"
    let name: String = "Search"

    func run(parameters: [String: Any]) async throws -> [String: Any] {
        guard let query = parameters["query"] as? String else { return [:] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            NotificationCenter.default.post(name: .createNewTabWithURL, object: url)
        }
        return ["opened": true]
    }
}
