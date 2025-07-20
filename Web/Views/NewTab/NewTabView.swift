import SwiftUI

// Enhanced new tab view with Web logo and next-gen design
struct NewTabView: View {
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Logo section
            VStack(spacing: 20) {
                WebLogo()
                    .frame(width: 80, height: 80)
                
                VStack(spacing: 8) {
                    Text("Web")
                        .font(.system(.largeTitle, design: .rounded, weight: .light))
                        .foregroundColor(.primary)
                    
                    Text("A next-generation browser")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Search bar
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16, weight: .medium))
                    
                    TextField("Search Google or enter website", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(.body, weight: .regular))
                        .focused($isSearchFocused)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: { 
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isSearchFocused ? .blue.opacity(0.5) : .primary.opacity(0.1), 
                                    lineWidth: 1
                                )
                        )
                )
                .frame(maxWidth: 500)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                
                // Quick action suggestions
                HStack(spacing: 16) {
                    QuickActionButton(
                        icon: "clock.arrow.circlepath",
                        title: "Recently Closed",
                        action: { /* TODO: Show recently closed */ }
                    )
                    
                    QuickActionButton(
                        icon: "star",
                        title: "Bookmarks",
                        action: { /* TODO: Show bookmarks */ }
                    )
                    
                    QuickActionButton(
                        icon: "arrow.down.circle",
                        title: "Downloads",
                        action: { /* TODO: Show downloads */ }
                    )
                    
                    QuickActionButton(
                        icon: "gearshape",
                        title: "Settings",
                        action: { /* TODO: Show settings */ }
                    )
                }
                .opacity(0.8)
            }
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            // Auto-focus search bar when new tab opens
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        // This would integrate with the TabManager to navigate
        // For now, just clear the search text
        searchText = ""
        isSearchFocused = false
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .opacity(isHovered ? 1.0 : 0.0)
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    NewTabView()
        .frame(width: 1200, height: 800)
}