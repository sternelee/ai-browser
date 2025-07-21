import SwiftUI

struct AutofillSuggestionRow: View {
    let suggestion: AutofillSuggestion
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Group {
                    if let favicon = suggestion.favicon {
                        Image(nsImage: favicon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: suggestion.sourceType.iconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                }
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.webBody)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Text(cleanDisplayURL(suggestion.url))
                        .font(.webCaption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
                
                if suggestion.sourceType != .history {
                    Text(suggestion.sourceType.displayName)
                        .font(.webCaption2)
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(suggestionBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    @ViewBuilder
    private var suggestionBackground: some View {
        if isSelected || isHovering {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentBeam.opacity(isSelected ? 0.12 : 0.08),
                            Color.accentBeam.opacity(isSelected ? 0.08 : 0.04),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            Color.accentBeam.opacity(isSelected ? 0.3 : 0.2),
                            lineWidth: 0.5
                        )
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
    
    private func cleanDisplayURL(_ url: String) -> String {
        var cleanURL = url
        
        if cleanURL.hasPrefix("https://") {
            cleanURL = String(cleanURL.dropFirst(8))
        } else if cleanURL.hasPrefix("http://") {
            cleanURL = String(cleanURL.dropFirst(7))
        }
        
        if cleanURL.hasPrefix("www.") {
            cleanURL = String(cleanURL.dropFirst(4))
        }
        
        if cleanURL.hasSuffix("/") {
            cleanURL = String(cleanURL.dropLast())
        }
        
        return cleanURL
    }
}

struct AutofillSuggestionsView: View {
    let suggestions: [AutofillSuggestion]
    let selectedIndex: Int
    let onSelect: (AutofillSuggestion) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                AutofillSuggestionRow(
                    suggestion: suggestion,
                    isSelected: index == selectedIndex
                ) {
                    onSelect(suggestion)
                }
                
                if index < suggestions.count - 1 {
                    Divider()
                        .background(Color.borderSubtle)
                        .padding(.horizontal, 12)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
        ))
    }
}

struct AutofillLoadingView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .progressViewStyle(.circular)
            
            Text("Loading suggestions...")
                .font(.webCaption)
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

struct AutofillEmptyView: View {
    let query: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)
            
            Text("No suggestions for \"\(query)\"")
                .font(.webCaption)
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

#Preview {
    VStack(spacing: 20) {
        AutofillSuggestionsView(
            suggestions: [
                AutofillSuggestion(
                    url: "https://github.com",
                    title: "GitHub",
                    score: 0.95,
                    sourceType: .bookmark,
                    visitCount: 25,
                    lastVisited: Date()
                ),
                AutofillSuggestion(
                    url: "https://apple.com",
                    title: "Apple",
                    score: 0.88,
                    sourceType: .history,
                    visitCount: 18,
                    lastVisited: Date().addingTimeInterval(-3600)
                )
            ],
            selectedIndex: 1,
            onSelect: { _ in },
            onDismiss: { }
        )
        .frame(width: 300)
        
        AutofillLoadingView()
            .frame(width: 300)
        
        AutofillEmptyView(query: "test")
            .frame(width: 300)
    }
    .padding(20)
    .background(.ultraThinMaterial)
}