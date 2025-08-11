import SwiftUI

struct AgentModeTogglePill: View {
    @Binding var isAgent: Bool

    var body: some View {
        HStack(spacing: 4) {
            pill(icon: "text.bubble", active: !isAgent) { isAgent = false }
            pill(icon: "wand.and.sparkles", active: isAgent) { isAgent = true }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.quaternary, lineWidth: 0.5))
        .help(isAgent ? "Agent mode" : "Ask mode")
    }

    private func pill(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.secondary)
                .frame(width: 22, height: 22)
                .background(active ? Color.accentColor : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
