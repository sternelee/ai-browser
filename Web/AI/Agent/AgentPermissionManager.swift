import Foundation

/// Evaluates automation intents and domain policies. M0 scaffold.
public final class AgentPermissionManager {
    public struct Decision {
        public let allowed: Bool
        public let reason: String?
        public init(allowed: Bool, reason: String? = nil) {
            self.allowed = allowed
            self.reason = reason
        }
    }

    public static let shared = AgentPermissionManager()
    private init() {}

    public func evaluate(intent: PageActionType, urlHost: String?) -> Decision {
        // Default permissive for non-destructive actions in M0
        switch intent {
        case .navigate, .findElements, .scroll, .waitFor, .extract, .switchTab:
            return Decision(allowed: true)
        default:
            return Decision(allowed: false, reason: "Not permitted in M0")
        }
    }
}
