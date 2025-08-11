import Foundation
import WebKit

/// Drives minimal visual cues in the page via injected JS. M0 scaffold.
@MainActor
public final class AgentOverlayController {
    private weak var webView: WKWebView?

    public init(webView: WKWebView?) { self.webView = webView }

    public func highlightElement(locatorDescription: String) {
        // M0: no-op; hook up to JS overlay later
    }

    public func showActionBanner(_ text: String) {
        // M0: no-op
    }
}
