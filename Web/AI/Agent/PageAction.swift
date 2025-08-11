import Foundation

/// The set of supported page actions for the agent planning loop
public enum PageActionType: String, Codable {
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

/// A semantic locator input that favors role/name/text before CSS/XPath
public struct LocatorInput: Codable, Hashable {
    public var role: String?
    public var name: String?
    public var text: String?
    public var css: String?
    public var xpath: String?
    public var near: String?
    public var nth: Int?

    public init(
        role: String? = nil,
        name: String? = nil,
        text: String? = nil,
        css: String? = nil,
        xpath: String? = nil,
        near: String? = nil,
        nth: Int? = nil
    ) {
        self.role = role
        self.name = name
        self.text = text
        self.css = css
        self.xpath = xpath
        self.near = near
        self.nth = nth
    }
}

/// A single planned action for the page agent to execute
public struct PageAction: Codable, Identifiable {
    public let id: UUID
    public let type: PageActionType
    public var locator: LocatorInput?
    public var text: String?
    public var url: String?
    public var newTab: Bool?
    public var direction: String?
    public var amountPx: Int?
    public var submit: Bool?
    public var value: String?
    public var timeoutMs: Int?

    public init(
        id: UUID = UUID(),
        type: PageActionType,
        locator: LocatorInput? = nil,
        text: String? = nil,
        url: String? = nil,
        newTab: Bool? = nil,
        direction: String? = nil,
        amountPx: Int? = nil,
        submit: Bool? = nil,
        value: String? = nil,
        timeoutMs: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.locator = locator
        self.text = text
        self.url = url
        self.newTab = newTab
        self.direction = direction
        self.amountPx = amountPx
        self.submit = submit
        self.value = value
        self.timeoutMs = timeoutMs
    }
}

/// The result of executing a single page action
public struct ActionResult: Codable {
    public let actionId: UUID
    public let success: Bool
    public let message: String?

    public init(actionId: UUID, success: Bool, message: String? = nil) {
        self.actionId = actionId
        self.success = success
        self.message = message
    }
}

/// Minimal element summary for listing and selection
public struct ElementSummary: Codable, Identifiable, Hashable {
    public let id: String
    public let role: String?
    public let name: String?
    public let text: String?
    public let isVisible: Bool
    public let boundingBox: BoundingBox?
    public let locatorHint: String?

    public init(
        id: String,
        role: String? = nil,
        name: String? = nil,
        text: String? = nil,
        isVisible: Bool = true,
        boundingBox: BoundingBox? = nil,
        locatorHint: String? = nil
    ) {
        self.id = id
        self.role = role
        self.name = name
        self.text = text
        self.isVisible = isVisible
        self.boundingBox = boundingBox
        self.locatorHint = locatorHint
    }
}

public struct BoundingBox: Codable, Hashable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
