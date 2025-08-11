import Foundation

/// Resolves natural-language-ish locators into deterministic strategies. M0 stub.
public struct SmartLocator {
    public static func serialize(_ input: LocatorInput) -> String {
        var parts: [String] = []
        if let role = input.role {
            parts.append("role=")
            parts.append(role)
        }
        if let name = input.name {
            parts.append("name=")
            parts.append(name)
        }
        if let text = input.text {
            parts.append("text=")
            parts.append(text)
        }
        if let css = input.css {
            parts.append("css=")
            parts.append(css)
        }
        if let xpath = input.xpath {
            parts.append("xpath=")
            parts.append(xpath)
        }
        if let near = input.near {
            parts.append("near=")
            parts.append(near)
        }
        if let nth = input.nth {
            parts.append("nth=")
            parts.append(String(nth))
        }
        return parts.joined(separator: " ")
    }
}
