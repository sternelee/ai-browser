import Foundation
import WebKit

/// Coordinates per-tab agent actions and bridge communication. M0 scaffold.
@MainActor
public final class PageAgent: NSObject {
    public enum Mode { case headed, headless }

    public private(set) var mode: Mode = .headed
    private weak var webView: WKWebView?

    public init(webView: WKWebView?) {
        self.webView = webView
    }

    public func setMode(headless: Bool) {
        mode = headless ? .headless : .headed
    }

    public func navigate(_ url: URL, newTab: Bool) async {
        guard !newTab, let webView else { return }
        await MainActor.run { webView.load(URLRequest(url: url)) }
    }

    public func requestElements(matching locator: LocatorInput) async -> [ElementSummary] {
        // M0: return empty; will integrate with JS runtime later
        return []
    }

    public func execute(plan: [PageAction]) async -> [ActionResult] {
        var results: [ActionResult] = []
        for step in plan {
            switch step.type {
            case .navigate:
                if let urlString = step.url, let url = URL(string: urlString) {
                    await navigate(url, newTab: step.newTab ?? false)
                    results.append(ActionResult(actionId: step.id, success: true))
                } else {
                    results.append(
                        ActionResult(actionId: step.id, success: false, message: "invalid url"))
                }
            default:
                results.append(
                    ActionResult(actionId: step.id, success: false, message: "not implemented"))
            }
        }
        return results
    }
}
