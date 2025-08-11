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

    // M2: simple domain policies for sensitive categories
    private let sensitiveDomains: Set<String> = [
        "accounts.google.com", "appleid.apple.com", "login.microsoftonline.com",
        "bankofamerica.com", "chase.com", "paypal.com",
    ]
    private let highRiskPaths: [String] = [
        "/login", "/signin", "/checkout", "/billing", "/account",
    ]

    public func evaluate(intent: PageActionType, urlHost: String?) -> Decision {
        // M2: stricter defaults with allowlist-like approach for destructive/semi-destructive actions
        let isSensitiveDomain =
            urlHost.map { host in
                sensitiveDomains.contains(host)
                    || sensitiveDomains.contains(where: { host.hasSuffix($0) })
            } ?? false

        switch intent {
        case .findElements, .waitFor, .scroll, .extract:
            return Decision(allowed: true)
        case .navigate, .switchTab:
            return Decision(allowed: true)
        case .select, .click:
            // Allow clicks generally; on sensitive domains require confirmation via ask_user
            if isSensitiveDomain {
                return Decision(allowed: false, reason: "Confirmation required on sensitive domain")
            }
            return Decision(allowed: true)
        case .typeText:
            if isSensitiveDomain {
                return Decision(
                    allowed: false, reason: "Typing blocked on sensitive domain without consent")
            }
            return Decision(allowed: true)
        case .askUser:
            return Decision(allowed: true)
        }
    }
}
