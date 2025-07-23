import SwiftUI
import CoreData

/// Next-generation history view with glass morphism and minimal design
/// Inspired by Arc Browser and Raycast aesthetics
struct HistoryView: View {
    @ObservedObject private var historyService = HistoryService.shared
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var searchText = ""
    @State private var selectedTimeRange: HistoryTimeRange = .today
    @State private var isSearchFocused = false
    @State private var hoveredItem: HistoryItem?
    
    // Animation states
    @State private var contentOpacity = 0.0
    @State private var searchBarOffset = -20.0
    
    
    private var filteredHistory: [HistoryItem] {
        let baseHistory: [HistoryItem]
        
        if searchText.isEmpty {
            baseHistory = historyService.recentHistory
        } else {
            baseHistory = historyService.searchHistory(query: searchText)
        }
        
        return filterByTimeRange(baseHistory)
    }
    
    private var groupedHistory: [(String, [HistoryItem])] {
        let items = filteredHistory
        let grouped = Dictionary(grouping: items) { item in
            if Calendar.current.isDateInToday(item.lastVisitDate) {
                return "Today"
            } else if Calendar.current.isDateInYesterday(item.lastVisitDate) {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: item.lastVisitDate)
            }
        }
        
        return grouped.sorted { first, second in
            if first.key == "Today" { return true }
            if second.key == "Today" { return false }
            if first.key == "Yesterday" { return true }
            if second.key == "Yesterday" { return false }
            return first.key > second.key
        }
    }
    
    var body: some View {
        ZStack {
            // Simplified glass background
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
            
            VStack(spacing: 0) {
                // Header with search and time range selector
                headerView
                
                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 20)
                
                // Content area
                contentView
            }
            .opacity(contentOpacity)
        }
        // Frame will be set by PanelManager for responsive sizing
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                contentOpacity = 1.0
                searchBarOffset = 0
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            // Title and close button
            HStack {
                Text("History")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    // Close history panel
                    KeyboardShortcutHandler.shared.showHistoryPanel = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        // Subtle hover effect
                    }
                }
            }
            
            // Search bar with glass effect
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .medium))
                
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                    .onTapGesture {
                        isSearchFocused = true
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .offset(y: searchBarOffset)
            
            // Time range selector with subtle pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HistoryTimeRange.allCases, id: \.self) { range in
                        timeRangePill(range)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    
    private func timeRangePill(_ range: HistoryTimeRange) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedTimeRange = range
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: range.icon)
                    .font(.system(size: 11, weight: .medium))
                
                Text(range.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedTimeRange == range ? .blue.opacity(0.2) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                selectedTimeRange == range ? .blue.opacity(0.6) : .secondary.opacity(0.3),
                                lineWidth: 0.5
                            )
                    )
            )
            .foregroundColor(selectedTimeRange == range ? .blue : .secondary)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if groupedHistory.isEmpty {
                    emptyStateView
                } else {
                    ForEach(groupedHistory, id: \.0) { section, items in
                        historySection(title: section, items: items)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)
            
            Text("No History Found")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(searchText.isEmpty ? "Start browsing to build your history" : "No results match your search")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
    
    private func historySection(title: String, items: [HistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(items.count) \(items.count == 1 ? "item" : "items")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, items == groupedHistory.first?.1 ? 0 : 16)
            
            // History items
            ForEach(items, id: \.id) { item in
                historyItemRow(item)
            }
        }
    }
    
    private func historyItemRow(_ item: HistoryItem) -> some View {
        HStack(spacing: 12) {
            // Favicon or fallback icon
            RoundedRectangle(cornerRadius: 6)
                .fill(.regularMaterial)
                .frame(width: 24, height: 24)
                .overlay(
                    Group {
                        if let faviconData = item.faviconData,
                           let nsImage = NSImage(data: faviconData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "globe")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(item.url)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        if item.visitCount > 1 {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            
                            Text("\(item.visitCount)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(formatRelativeTime(item.lastVisitDate))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Action buttons on hover
            if hoveredItem?.id == item.id {
                HStack(spacing: 4) {
                    actionButton(icon: "arrow.up.right", action: {
                        openInCurrentTab(item)
                    })
                    
                    actionButton(icon: "plus", action: {
                        openInNewTab(item)
                    })
                    
                    actionButton(icon: "trash", destructive: true, action: {
                        deleteHistoryItem(item)
                    })
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredItem?.id == item.id ? .white.opacity(0.03) : .clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                hoveredItem = hovering ? item : nil
            }
        }
        .onTapGesture {
            openInCurrentTab(item)
        }
    }
    
    private func actionButton(icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(destructive ? .red : .blue)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(destructive ? .red.opacity(0.3) : .blue.opacity(0.3), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Methods
    
    private func filterByTimeRange(_ items: [HistoryItem]) -> [HistoryItem] {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimeRange {
        case .today:
            return items.filter { calendar.isDateInToday($0.lastVisitDate) }
        case .yesterday:
            return items.filter { calendar.isDateInYesterday($0.lastVisitDate) }
        case .thisWeek:
            let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return items.filter { $0.lastVisitDate >= weekAgo }
        case .thisMonth:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return items.filter { $0.lastVisitDate >= monthAgo }
        case .all:
            return items
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func openInCurrentTab(_ item: HistoryItem) {
        if let url = URL(string: item.url) {
            NotificationCenter.default.post(
                name: .navigateCurrentTab,
                object: url
            )
            KeyboardShortcutHandler.shared.showHistoryPanel = false
        }
    }
    
    private func openInNewTab(_ item: HistoryItem) {
        if let url = URL(string: item.url) {
            NotificationCenter.default.post(
                name: .createNewTabWithURL,
                object: url
            )
            KeyboardShortcutHandler.shared.showHistoryPanel = false
        }
    }
    
    private func deleteHistoryItem(_ item: HistoryItem) {
        // Apply smooth animation for UI feedback
        withAnimation(.easeOut(duration: 0.25)) {
            hoveredItem = nil // Clear hover state
        }
        
        // Service handles immediate UI feedback and persistence
        historyService.deleteHistoryItem(item)
    }
}

#Preview {
    HistoryView()
        .frame(width: 480, height: 600)
        .background(.black.opacity(0.3))
}