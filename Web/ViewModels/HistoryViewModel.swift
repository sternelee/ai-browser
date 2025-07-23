import SwiftUI
import Combine
import CoreData
import os.log

/// ViewModel for managing history view state and interactions
/// Provides reactive updates and smooth data handling for the next-gen history UI
class HistoryViewModel: ObservableObject {
    // Published properties for UI binding
    @Published var searchText = ""
    @Published var selectedTimeRange: HistoryTimeRange = .today
    @Published var isLoading = false
    @Published var filteredHistory: [HistoryItem] = []
    @Published var groupedHistory: [(String, [HistoryItem])] = []
    
    // Services
    private let historyService = HistoryService.shared
    private let logger = Logger(subsystem: "com.example.Web", category: "HistoryViewModel")
    
    // Combine cancellables
    private var cancellables = Set<AnyCancellable>()
    private var searchDebounceTimer: AnyCancellable?
    
    init() {
        setupPublishers()
        loadInitialData()
    }
    
    private func setupPublishers() {
        // Reactive search with debouncing
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                self?.performSearch(searchText)
            }
            .store(in: &cancellables)
        
        // React to time range changes
        $selectedTimeRange
            .sink { [weak self] (timeRange: HistoryTimeRange) in
                self?.updateFilteredHistory()
            }
            .store(in: &cancellables)
        
        // Listen to history service updates
        historyService.$recentHistory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFilteredHistory()
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialData() {
        isLoading = true
        
        // Load history data
        updateFilteredHistory()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isLoading = false
        }
    }
    
    private func performSearch(_ query: String) {
        isLoading = true
        
        DispatchQueue.global(qos: .userInteractive).async {
            let results: [HistoryItem]
            
            if query.isEmpty {
                results = self.historyService.recentHistory
            } else {
                results = self.historyService.searchHistory(query: query)
                self.logger.debug("Search completed for '\(query)': \(results.count) results")
            }
            
            DispatchQueue.main.async {
                self.filteredHistory = self.filterByTimeRange(results)
                self.updateGroupedHistory()
                self.isLoading = false
            }
        }
    }
    
    private func updateFilteredHistory() {
        let baseHistory = searchText.isEmpty ? historyService.recentHistory : historyService.searchHistory(query: searchText)
        filteredHistory = filterByTimeRange(baseHistory)
        updateGroupedHistory()
    }
    
    private func updateGroupedHistory() {
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
        
        groupedHistory = grouped.sorted { first, second in
            if first.key == "Today" { return true }
            if second.key == "Today" { return false }
            if first.key == "Yesterday" { return true }
            if second.key == "Yesterday" { return false }
            return first.key > second.key
        }
    }
    
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
    
    // MARK: - Public Methods
    
    func deleteHistoryItem(_ item: HistoryItem) {
        // Service handles immediate UI feedback, just call it
        historyService.deleteHistoryItem(item)
        logger.info("Deleted history item: \(item.displayTitle)")
    }
    
    func clearHistoryForTimeRange() {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimeRange {
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            historyService.deleteHistory(from: startOfDay)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let startOfYesterday = calendar.startOfDay(for: yesterday)
            historyService.deleteHistory(from: startOfYesterday)
        case .all:
            historyService.clearAllHistory()
        default:
            break
        }
        
        logger.info("Cleared history for time range: \(self.selectedTimeRange.rawValue)")
        // Service handles immediate UI feedback, no need to manually update
    }
    
    func openInCurrentTab(_ item: HistoryItem) {
        guard let url = URL(string: item.url) else { return }
        
        NotificationCenter.default.post(
            name: .navigateCurrentTab,
            object: url
        )
        
        logger.debug("Opening in current tab: \(item.displayTitle)")
    }
    
    func openInNewTab(_ item: HistoryItem) {
        guard let url = URL(string: item.url) else { return }
        
        NotificationCenter.default.post(
            name: .createNewTabWithURL,
            object: url
        )
        
        logger.debug("Opening in new tab: \(item.displayTitle)")
    }
    
    func refreshHistory() {
        isLoading = true
        updateFilteredHistory()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isLoading = false
        }
    }
    
    // MARK: - Helper Methods
    
    func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    func getHistoryStats() -> (totalVisits: Int, uniqueSites: Int, todayVisits: Int) {
        let allHistory = historyService.recentHistory
        let totalVisits = allHistory.reduce(0) { $0 + Int($1.visitCount) }
        let uniqueSites = allHistory.count
        let todayVisits = allHistory.filter { Calendar.current.isDateInToday($0.lastVisitDate) }.count
        
        return (totalVisits, uniqueSites, todayVisits)
    }
}

// MARK: - TimeRange Definition

enum HistoryTimeRange: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case all = "All History"
    
    var icon: String {
        switch self {
        case .today: return "clock"
        case .yesterday: return "clock.arrow.circlepath"
        case .thisWeek: return "calendar.day.timeline.leading"
        case .thisMonth: return "calendar"
        case .all: return "clock.arrow.2.circlepath"
        }
    }
    
    var description: String {
        switch self {
        case .today: return "Sites visited today"
        case .yesterday: return "Sites visited yesterday"
        case .thisWeek: return "Sites visited this week"
        case .thisMonth: return "Sites visited this month"
        case .all: return "All browsing history"
        }
    }
}