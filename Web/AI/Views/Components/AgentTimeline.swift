import SwiftUI

struct AgentTimelineRow: View {
    let index: Int
    let step: AgentStep

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack(alignment: .top) {
                // Continuous connector line that spans card height
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                statusIcon
                    .background(Color.clear)
                    .offset(x: -0.5)  // center over line
            }
            .frame(width: 16)

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
        .background(
            ZStack(alignment: .leading) {
                // Soft gradient background to reduce harsh failure look
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                // Left accent bar reflecting state
                Rectangle()
                    .fill(accentColorForState(step.state))
                    .frame(width: 2)
                    .opacity(0.8)
            }
        )
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                .font(.system(size: 12))
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
            // When used as first pseudo-step, show the raw instruction
            if let t = action.text, !t.isEmpty { return t }
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

    private func accentColorForState(_ state: AgentStepState) -> Color {
        switch state {
        case .planned: return .secondary.opacity(0.3)
        case .running: return .blue.opacity(0.8)
        case .success: return .green.opacity(0.8)
        case .failure: return .orange.opacity(0.8)
        }
    }
}
