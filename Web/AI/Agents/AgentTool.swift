import Foundation

protocol AgentTool {
    var id: String { get }
    var name: String { get }
    func run(parameters: [String: Any]) async throws -> [String: Any]
}
