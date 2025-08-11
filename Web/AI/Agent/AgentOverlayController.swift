import Foundation
import WebKit

/// Drives minimal visual cues in the page via injected JS. M0 scaffold.
@MainActor
public final class AgentOverlayController {
    private weak var webView: WKWebView?

    public init(webView: WKWebView?) { self.webView = webView }

    public func showConsentPill(_ text: String) {
        guard let webView else { return }
        let escaped = Self.escapeForJavaScriptString(text)
        let script =
            "(() => JSON.stringify(window.__agent && window.__agent.banner ? window.__agent.banner(JSON.parse('\"\(escaped)\"'), 1800) : { ok: false }))();"
        webView.evaluateJavaScript(script) { _, _ in }
    }

    public func highlightElement(locatorDescription: String) {
        guard let webView else { return }
        let escaped = Self.escapeForJavaScriptString(locatorDescription)
        let script =
            "(() => JSON.stringify(window.__agent && window.__agent.overlayHighlightByCss ? window.__agent.overlayHighlightByCss(JSON.parse('\"\(escaped)\"'), 900) : { ok: false }))();"
        webView.evaluateJavaScript(script) { _, _ in }
    }

    public func showActionBanner(_ text: String) {
        guard let webView else { return }
        let escaped = Self.escapeForJavaScriptString(text)
        let script =
            "(() => JSON.stringify(window.__agent && window.__agent.banner ? window.__agent.banner(JSON.parse('\"\(escaped)\"'), 1400) : { ok: false }))();"
        webView.evaluateJavaScript(script) { _, _ in }
    }

    private static func escapeForJavaScriptString(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: "\\", with: "\\\\")
        s = s.replacingOccurrences(of: "'", with: "\\\'")
        s = s.replacingOccurrences(of: "\"", with: "\\\"")
        s = s.replacingOccurrences(of: "\n", with: "\\n")
        s = s.replacingOccurrences(of: "\r", with: "\\r")
        s = s.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        s = s.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return s
    }
}
