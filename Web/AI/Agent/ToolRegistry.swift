import Foundation
import WebKit

/// Registry of tools the LLM can call. For M0 this is scaffolded only.
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()

    private init() {}

    enum ToolName: String, CaseIterable {
        case navigate
        case findElements
        case click
        case typeText
        case scroll
        case select
        case waitFor
        case extract
        case switchTab
        case askUser
    }

    struct ToolCall: Codable {
        let name: String
        let arguments: [String: AnyCodable]
    }

    struct ToolObservation: Codable {
        let name: String
        let ok: Bool
        let data: [String: AnyCodable]?
        let message: String?
    }

    /// Execute a tool call against the current page/webview. For M0, returns not-implemented.
    func executeTool(_ call: ToolCall, webView: WKWebView?) async -> ToolObservation {
        guard let name = ToolName(rawValue: call.name) else {
            return ToolObservation(name: call.name, ok: false, data: nil, message: "unknown tool")
        }
        // M0 stub
        return ToolObservation(
            name: name.rawValue, ok: false, data: nil, message: "not implemented")
    }
}
