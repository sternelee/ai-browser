import SwiftUI
import Combine

class TabManager: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var activeTab: Tab?
    @Published var recentlyClosedTabs: [Tab] = []
    
    private let maxRecentlyClosedTabs = 10
    private let maxConcurrentTabs = 50
    
    init() {
        // Create initial tab
        createNewTab()
    }
    
    // MARK: - Tab Operations
    @discardableResult
    func createNewTab(url: URL? = nil, isIncognito: Bool = false) -> Tab {
        let tab: Tab
        
        if isIncognito {
            // Create incognito tab through IncognitoSession
            tab = IncognitoSession.shared.createIncognitoTab(url: url)
        } else {
            tab = Tab(url: url, isIncognito: isIncognito)
        }
        
        tabs.append(tab)
        setActiveTab(tab)
        
        // Manage memory by hibernating old tabs
        manageTabMemory()
        
        return tab
    }
    
    @discardableResult
    func createIncognitoTab(url: URL? = nil) -> Tab {
        return createNewTab(url: url, isIncognito: true)
    }
    
    func closeTab(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        
        // Handle incognito tab closure
        if tab.isIncognito {
            IncognitoSession.shared.closeIncognitoTab(tab)
        } else {
            // Add to recently closed (only for regular tabs)
            recentlyClosedTabs.insert(tab, at: 0)
            if recentlyClosedTabs.count > maxRecentlyClosedTabs {
                recentlyClosedTabs.removeLast()
            }
        }
        
        tabs.remove(at: index)
        
        // Select new active tab
        if activeTab?.id == tab.id {
            if index < tabs.count {
                setActiveTab(tabs[index])
            } else if index > 0 {
                setActiveTab(tabs[index - 1])
            } else {
                activeTab = nil
            }
        }
        
        // Create new tab if none remain
        if tabs.isEmpty {
            createNewTab()
        }
    }
    
    func reopenLastClosedTab() -> Tab? {
        guard let lastClosed = recentlyClosedTabs.first else { return nil }
        
        recentlyClosedTabs.removeFirst()
        let newTab = createNewTab(url: lastClosed.url, isIncognito: lastClosed.isIncognito)
        newTab.title = lastClosed.title
        newTab.favicon = lastClosed.favicon
        
        return newTab
    }
    
    func setActiveTab(_ tab: Tab) {
        // Don't do anything if this tab is already active
        guard activeTab?.id != tab.id else { return }
        
        // Deactivate current tab
        activeTab?.isActive = false
        
        // Activate new tab
        activeTab = tab
        tab.isActive = true
        tab.wakeUp() // Wake up if hibernated
        
        // Tab switched successfully
    }
    
    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }
    
    // MARK: - Memory Management
    private func manageTabMemory() {
        // Hibernate old inactive tabs if we have too many
        let inactiveTabs = tabs.filter { !$0.isActive && !$0.isHibernated }
        
        if tabs.count > maxConcurrentTabs {
            // Hibernate oldest inactive tabs
            let oldestInactive = inactiveTabs.sorted { $0.lastAccessed < $1.lastAccessed }
            for tab in oldestInactive.prefix(5) {
                tab.hibernate()
            }
        }
    }
    
    // MARK: - Additional Tab Operations
    func closeOtherTabs(except tab: Tab) {
        let tabsToClose = tabs.filter { $0.id != tab.id }
        for tabToClose in tabsToClose {
            closeTab(tabToClose)
        }
    }
    
    func closeTabsToTheRight(of tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        
        let tabsToClose = Array(tabs.suffix(from: index + 1))
        for tabToClose in tabsToClose {
            closeTab(tabToClose)
        }
    }
    
    // MARK: - Search and Filter
    func searchTabs(query: String) -> [Tab] {
        guard !query.isEmpty else { return tabs }
        
        return tabs.filter { tab in
            tab.title.lowercased().contains(query.lowercased()) ||
            tab.url?.absoluteString.lowercased().contains(query.lowercased()) == true
        }
    }
    
    // MARK: - Tab Navigation
    func selectNextTab() {
        guard let currentTab = activeTab,
              let currentIndex = tabs.firstIndex(where: { $0.id == currentTab.id }) else { return }
        
        let nextIndex = (currentIndex + 1) % tabs.count
        setActiveTab(tabs[nextIndex])
    }
    
    func selectPreviousTab() {
        guard let currentTab = activeTab,
              let currentIndex = tabs.firstIndex(where: { $0.id == currentTab.id }) else { return }
        
        let previousIndex = currentIndex == 0 ? tabs.count - 1 : currentIndex - 1
        setActiveTab(tabs[previousIndex])
    }
    
    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        setActiveTab(tabs[index])
    }
    
    func selectTabByNumber(_ number: Int) {
        let index = number - 1 // Convert 1-based to 0-based index
        selectTab(at: index)
    }
}