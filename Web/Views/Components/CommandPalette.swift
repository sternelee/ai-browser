import SwiftUI

struct CommandPalette: View {
    @ObservedObject private var keyboardHandler = KeyboardShortcutHandler.shared
    @ObservedObject private var providerManager = AIProviderManager.shared
    @State private var query: String = ""
    @State private var selectionIndex: Int = 0

    private var items: [PaletteItem] {
        let base: [PaletteItem] = [
            .action(title: "TL;DR this page", icon: "text.alignleft") {
                NotificationCenter.default.post(name: .performTLDRRequested, object: nil)
            },
            .action(title: "Ask about this page…", icon: "questionmark.bubble") {
                NotificationCenter.default.post(name: .performAskRequested, object: nil)
            },
            .action(title: "Toggle AI Sidebar", icon: "sidebar.right") {
                NotificationCenter.default.post(name: .toggleAISidebar, object: nil)
            },
            .action(title: "Focus Address Bar", icon: "magnifyingglass") {
                NotificationCenter.default.post(name: .focusAddressBarRequested, object: nil)
            },
            .action(title: "New Tab", icon: "plus") {
                NotificationCenter.default.post(name: .newTabRequested, object: nil)
            },
            .action(title: "Preferences", icon: "gear") {
                NotificationCenter.default.post(name: .showSettingsRequested, object: nil)
            },
            .action(title: "Usage & Billing", icon: "chart.bar") {
                NotificationCenter.default.post(name: .showSettingsRequested, object: nil)
                NotificationCenter.default.post(name: .openUsageBilling, object: nil)
            },
        ]

        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return base
        }

        let lower = query.lowercased()
        return base.filter { $0.title.lowercased().contains(lower) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundColor(.secondary)
                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit(executeSelected)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(
                            .white.opacity(0.12), lineWidth: 0.5))
            )

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Button(action: {
                            item.handler()
                            hide()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .foregroundColor(index == selectionIndex ? .blue : .secondary)
                                Text(item.title)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        index == selectionIndex
                                            ? Color.blue.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .frame(maxHeight: 240)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.14), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
        )
        .frame(minWidth: 520, maxWidth: 680)
        .frame(maxHeight: 360)
        .fixedSize(horizontal: false, vertical: true)
        .onExitCommand { hide() }
        .onAppear { selectionIndex = 0 }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPaletteRequested)) { _ in
            selectionIndex = 0
        }
        .onKeyPress(.downArrow) {
            incrementSelection()
            return .handled
        }
        .onKeyPress(.upArrow) {
            decrementSelection()
            return .handled
        }
        .onKeyPress(.return) {
            executeSelected()
            return .handled
        }
    }

    private func hide() {
        NotificationCenter.default.post(name: .hideCommandPaletteRequested, object: nil)
    }

    private func incrementSelection() {
        selectionIndex = min(selectionIndex + 1, max(items.count - 1, 0))
    }

    private func decrementSelection() {
        selectionIndex = max(selectionIndex - 1, 0)
    }

    private func executeSelected() {
        guard !items.isEmpty else { return }
        items[selectionIndex].handler()
        hide()
    }
}

private enum PaletteItem {
    case action(title: String, icon: String, handler: () -> Void)

    var title: String {
        switch self {
        case let .action(title, _, _): return title
        }
    }

    var icon: String {
        switch self {
        case let .action(_, icon, _): return icon
        }
    }

    var handler: () -> Void {
        switch self {
        case let .action(_, _, handler): return handler
        }
    }
}
