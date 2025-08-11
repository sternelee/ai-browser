import SwiftUI

struct AgentTimelineRow: View {
    let index: Int
    let step: AgentStep

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                statusIcon
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(stepTitle(step.action))
                    .font(.system(size: 12, weight: .semibold))
                if let loc = step.action.locator {
                    Text(locatorSummary(loc))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if let msg = step.message, !msg.isEmpty {
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
    }

    @ViewBuilder private var statusIcon: some View {
        switch step.state {
        case .planned:
            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
        case .running:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(
                .system(size: 12))
        case .failure:
            Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.system(size: 12))
        }
    }

    private func stepTitle(_ action: PageAction) -> String {
        switch action.type {
        case .navigate:
            return "Navigate to \(action.url ?? "")"
        case .click:
            return "Click"
        case .typeText:
            return "Type \(action.text ?? "")"
        case .select:
            return "Select \(action.value ?? "")"
        case .scroll:
            return "Scroll \(action.direction ?? "down")"
        case .waitFor:
            return "Wait"
        case .findElements:
            return "Find elements"
        case .extract:
            return "Extract"
        case .switchTab:
            return "Switch tab"
        case .askUser:
            return "Ask user"
        }
    }

    private func locatorSummary(_ loc: LocatorInput) -> String {
        var parts: [String] = []
        if let r = loc.role { parts.append("role=\(r)") }
        if let n = loc.name { parts.append("name=\(n)") }
        if let t = loc.text { parts.append("text=\(t)") }
        if let css = loc.css { parts.append("css=\(css)") }
        if let nth = loc.nth { parts.append("nth=\(nth)") }
        return parts.joined(separator: " · ")
    }
}
