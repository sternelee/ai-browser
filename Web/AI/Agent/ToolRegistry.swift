import AppKit
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
        case observe
        case click
        case typeText
        case scroll
        case select
        case waitFor
        case extract
        case switchTab
        case askUser
        case snapshot
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

    /// Execute a tool call against the current page/webview. M2 adds ask_user and extract; M3 adds snapshot.
    func executeTool(_ call: ToolCall, webView: WKWebView?) async -> ToolObservation {
        guard let name = ToolName(rawValue: call.name) else {
            return ToolObservation(name: call.name, ok: false, data: nil, message: "unknown tool")
        }
        let pageAgent = PageAgent(webView: webView)
        do {
            switch name {
            case .navigate:
                if let urlStr = call.arguments["url"]?.value as? String,
                    let url = URL(string: urlStr)
                {
                    await pageAgent.navigate(
                        url, newTab: (call.arguments["newTab"]?.value as? Bool) ?? false)
                    return ToolObservation(name: name.rawValue, ok: true, data: nil, message: nil)
                }
                return ToolObservation(
                    name: name.rawValue, ok: false, data: nil, message: "invalid url")
            case .findElements:
                // Allow missing locator to enumerate interactive elements generically
                let providedLocator = try locatorFromArgs(call.arguments)
                let locator = providedLocator ?? LocatorInput()
                let elements = await pageAgent.requestElements(matching: locator)
                // Provide a slightly larger sample to help the model choose deterministically by nth
                let sampleLimit = 12
                let sample = elements.prefix(sampleLimit).enumerated().map {
                    (idx, el) -> [String: AnyCodable] in
                    var item: [String: AnyCodable] = [
                        "i": AnyCodable(idx),
                        "id": AnyCodable(el.id),
                        "role": AnyCodable(el.role ?? ""),
                        "name": AnyCodable(el.name ?? ""),
                        "text": AnyCodable((el.text ?? "").prefix(120)),
                    ]
                    if let hint = el.locatorHint { item["hint"] = AnyCodable(hint) }
                    return item
                }
                // Echo back the normalized locator so the model can repeat role/nth consistently
                var echo: [String: AnyCodable] = [:]
                if let r = locator.role { echo["role"] = AnyCodable(r) }
                if let n = locator.name { echo["name"] = AnyCodable(n) }
                if let t = locator.text { echo["text"] = AnyCodable(t) }
                if let nth = locator.nth { echo["nth"] = AnyCodable(nth) }
                let boxed: [String: AnyCodable] = [
                    "count": AnyCodable(elements.count),
                    "elements": AnyCodable(sample),
                    "locator": AnyCodable(echo),
                ]
                return ToolObservation(name: name.rawValue, ok: true, data: boxed, message: nil)
            case .observe:
                // Page-agnostic observation helper that returns curated element lists
                let kinds =
                    (call.arguments["kinds"]?.value as? [String])?.map { $0.lowercased() } ?? [
                        "interactive", "articles", "textboxes",
                    ]
                let limit = (call.arguments["limit"]?.value as? Int) ?? 12

                func sample(_ elems: [ElementSummary]) -> [[String: AnyCodable]] {
                    return elems.prefix(limit).enumerated().map { (idx, el) in
                        var item: [String: AnyCodable] = [
                            "i": AnyCodable(idx),
                            "role": AnyCodable(el.role ?? ""),
                            "name": AnyCodable(el.name ?? ""),
                            "text": AnyCodable((el.text ?? "").prefix(120)),
                        ]
                        if let hint = el.locatorHint { item["hint"] = AnyCodable(hint) }
                        return item
                    }
                }

                var blocks: [[String: AnyCodable]] = []
                if kinds.contains("articles") {
                    let els = await pageAgent.requestElements(
                        matching: LocatorInput(role: "article"))
                    blocks.append([
                        "kind": AnyCodable("articles"),
                        "count": AnyCodable(els.count),
                        "elements": AnyCodable(sample(els)),
                    ])
                }
                if kinds.contains("textboxes") {
                    let els = await pageAgent.requestElements(
                        matching: LocatorInput(role: "textbox"))
                    blocks.append([
                        "kind": AnyCodable("textboxes"),
                        "count": AnyCodable(els.count),
                        "elements": AnyCodable(sample(els)),
                    ])
                }
                if kinds.contains("interactive") {
                    var all: [ElementSummary] = []
                    let roles = ["button", "link", "textbox", "input", "select"]
                    for r in roles {
                        let els = await pageAgent.requestElements(matching: LocatorInput(role: r))
                        all.append(contentsOf: els)
                    }
                    blocks.append([
                        "kind": AnyCodable("interactive"),
                        "count": AnyCodable(all.count),
                        "elements": AnyCodable(sample(all)),
                    ])
                }

                let boxed: [String: AnyCodable] = [
                    "blocks": AnyCodable(blocks),
                    "kinds": AnyCodable(kinds),
                ]
                return ToolObservation(name: name.rawValue, ok: true, data: boxed, message: nil)
            case .click:
                if let locator = try locatorFromArgs(call.arguments) {
                    let ok = await pageAgent.click(locator: locator)
                    return ToolObservation(name: name.rawValue, ok: ok, data: nil, message: nil)
                }
                return ToolObservation(
                    name: name.rawValue, ok: false, data: nil, message: "missing locator")
            case .typeText:
                let text = call.arguments["text"]?.value as? String
                guard let text else {
                    return ToolObservation(
                        name: name.rawValue, ok: false, data: nil, message: "missing text")
                }
                var locator = try locatorFromArgs(call.arguments)
                // Page-agnostic fallback: if no semantic locator provided, choose a textbox automatically
                func isSemantic(_ loc: LocatorInput) -> Bool {
                    return (loc.role != nil) || (loc.name != nil) || (loc.text != nil)
                        || (loc.nth != nil)
                }
                if locator == nil || !(isSemantic(locator!)) {
                    let inputs = await pageAgent.requestElements(
                        matching: LocatorInput(role: "textbox"))
                    if !inputs.isEmpty {
                        locator = LocatorInput(role: "textbox", nth: 0)
                    } else {
                        // Try generic input role
                        let fallbacks = await pageAgent.requestElements(
                            matching: LocatorInput(role: "input"))
                        if !fallbacks.isEmpty { locator = LocatorInput(role: "input", nth: 0) }
                    }
                }
                if let resolved = locator {
                    let submit = (call.arguments["submit"]?.value as? Bool) ?? false
                    let ok = await pageAgent.typeText(locator: resolved, text: text, submit: submit)
                    return ToolObservation(name: name.rawValue, ok: ok, data: nil, message: nil)
                } else {
                    return ToolObservation(
                        name: name.rawValue, ok: false, data: nil, message: "no input found")
                }
            case .select:
                if let locator = try locatorFromArgs(call.arguments),
                    let value = call.arguments["value"]?.value as? String
                {
                    let ok = await pageAgent.select(locator: locator, value: value)
                    return ToolObservation(name: name.rawValue, ok: ok, data: nil, message: nil)
                }
                return ToolObservation(
                    name: name.rawValue, ok: false, data: nil, message: "missing locator or value")
            case .scroll:
                let locator = try locatorFromArgs(call.arguments)
                let direction = call.arguments["direction"]?.value as? String
                let amount = call.arguments["amountPx"]?.value as? Int
                let ok = await pageAgent.scroll(
                    target: locator, direction: direction, amountPx: amount)
                return ToolObservation(name: name.rawValue, ok: ok, data: nil, message: nil)
            case .waitFor:
                var action = PageAction(type: .waitFor)
                if let sel = call.arguments["selector"]?.value as? String { action.text = sel }
                if let mode = call.arguments["readyState"]?.value as? String {
                    action.direction = mode == "complete" ? "ready" : mode
                }
                if let delay = call.arguments["delayMs"]?.value as? Int { action.amountPx = delay }
                let ok = await pageAgent.waitFor(
                    predicate: action, timeoutMs: call.arguments["timeoutMs"]?.value as? Int)
                return ToolObservation(name: name.rawValue, ok: ok, data: nil, message: nil)
            case .extract:
                let mode = (call.arguments["readMode"]?.value as? String) ?? "selection"
                let selector = call.arguments["selector"]?.value as? String
                let text = await pageAgent.extract(readMode: mode, selector: selector)
                let boxed: [String: AnyCodable] = [
                    "text": AnyCodable(text)
                ]
                return ToolObservation(
                    name: name.rawValue, ok: !text.isEmpty, data: boxed, message: nil)
            case .askUser:
                let prompt = (call.arguments["prompt"]?.value as? String) ?? ""
                let choices = call.arguments["choices"]?.value as? [String]
                let defaultIndex = call.arguments["default"]?.value as? Int
                let timeoutMs = call.arguments["timeoutMs"]?.value as? Int
                let result = await presentConsentPrompt(
                    prompt: prompt, choices: choices, defaultIndex: defaultIndex,
                    timeoutMs: timeoutMs)
                var boxed: [String: AnyCodable] = [
                    "answer": AnyCodable(result.answer ?? ""),
                    "consent": AnyCodable(result.consent),
                ]
                if let idx = result.choiceIndex { boxed["choiceIndex"] = AnyCodable(idx) }
                return ToolObservation(
                    name: name.rawValue, ok: result.consent, data: boxed, message: nil)
            case .switchTab:
                return ToolObservation(
                    name: name.rawValue, ok: false, data: nil, message: "not implemented")
            case .snapshot:
                let base64 = await pageAgent.takeSnapshotBase64(
                    locator: try locatorFromArgs(call.arguments),
                    cropToElement: (call.arguments["cropToElement"]?.value as? Bool) ?? false)
                let ok = base64 != nil
                let boxed: [String: AnyCodable]? = ok ? ["image_base64": AnyCodable(base64!)] : nil
                return ToolObservation(
                    name: name.rawValue, ok: ok, data: boxed, message: ok ? nil : "snapshot failed")
            }
        } catch {
            return ToolObservation(
                name: name.rawValue, ok: false, data: nil, message: "invalid arguments")
        }
    }

    // MARK: - Helpers
    private func locatorFromArgs(_ args: [String: AnyCodable]) throws -> LocatorInput? {
        guard let value = args["locator"] else { return nil }
        let decode: (Data) throws -> LocatorInput = { data in
            var loc = try JSONDecoder().decode(LocatorInput.self, from: data)
            // Page-agnostic safety: avoid raw selector crafting from model
            loc.css = nil
            loc.xpath = nil
            return loc
        }
        // Accept either dictionary or JSON string
        if let dict = value.value as? [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: dict)
            return try decode(data)
        }
        if let json = value.value as? String, let data = json.data(using: .utf8) {
            return try decode(data)
        }
        let data = try JSONEncoder().encode(value)
        return try decode(data)
    }

    // MARK: - Consent Prompt
    private func presentConsentPrompt(
        prompt: String,
        choices: [String]?,
        defaultIndex: Int?,
        timeoutMs: Int?
    ) async -> (answer: String?, choiceIndex: Int?, consent: Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = prompt.isEmpty ? "Proceed?" : prompt
                alert.alertStyle = .warning

                var choiceButtons: [NSButton] = []
                if let choices, !choices.isEmpty {
                    for (idx, title) in choices.enumerated() {
                        let button = alert.addButton(withTitle: title)
                        button.tag = idx
                        choiceButtons.append(button)
                    }
                } else {
                    _ = alert.addButton(withTitle: "Allow")
                    _ = alert.addButton(withTitle: "Cancel")
                }

                // Timeout handling (optional)
                var timedOut = false
                var timer: Timer?
                if let timeoutMs, timeoutMs >= 1000 {
                    timer = Timer.scheduledTimer(
                        withTimeInterval: TimeInterval(timeoutMs) / 1000.0, repeats: false
                    ) { _ in
                        timedOut = true
                        continuation.resume(
                            returning: (answer: nil, choiceIndex: nil, consent: false))
                    }
                }

                let response = alert.runModal()
                timer?.invalidate()
                if timedOut {
                    return
                }

                if let choices, !choices.isEmpty {
                    // Map response to index (first button returns .alertFirstButtonReturn)
                    let index =
                        response.rawValue
                        - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                    let safeIndex = max(0, min(index, choices.count - 1))
                    continuation.resume(
                        returning: (
                            answer: choices[safeIndex], choiceIndex: safeIndex, consent: true
                        ))
                } else {
                    // Two-button Allow/Cancel
                    let consent = (response == .alertFirstButtonReturn)
                    continuation.resume(
                        returning: (
                            answer: consent ? "allow" : "cancel", choiceIndex: consent ? 0 : 1,
                            consent: consent
                        ))
                }
            }
        }
    }
}
