import SwiftUI
import CoreData

/// Next-generation bookmark view with Arc-inspired design and folder management
/// Features glass morphism, smooth animations, and progressive disclosure
struct BookmarkView: View {
    @ObservedObject private var bookmarkService = BookmarkService.shared
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var searchText = ""
    @State private var selectedFolder: BookmarkFolder?
    @State private var showingNewFolderSheet = false
    @State private var showingEditBookmarkSheet = false
    @State private var editingBookmark: Bookmark?
    @State private var hoveredBookmark: Bookmark?
    @State private var draggedBookmark: Bookmark?
    @State private var showingDeleteAlert = false
    @State private var bookmarkToDelete: Bookmark?
    
    // Animation states
    @State private var contentOpacity = 0.0
    @State private var sidebarOffset = -20.0
    @State private var mainContentOffset = 20.0
    
    private var filteredBookmarks: [Bookmark] {
        let bookmarks = bookmarkService.getBookmarks(in: selectedFolder)
        
        if searchText.isEmpty {
            return bookmarks
        } else {
            return bookmarks.filter { bookmark in
                bookmark.title.localizedCaseInsensitiveContains(searchText) ||
                bookmark.url.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var rootFolders: [BookmarkFolder] {
        bookmarkService.getSubfolders(of: nil)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar with folders
            sidebarView
                .frame(minWidth: 160, maxWidth: 200)
                .offset(x: sidebarOffset)
            
            // Separator
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 0.5)
            
            // Main content area
            mainContentView
                .offset(x: mainContentOffset)
        }
        .background(glassBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                contentOpacity = 1.0
                sidebarOffset = 0
                mainContentOffset = 0
            }
        }
        .opacity(contentOpacity)
        .sheet(isPresented: $showingNewFolderSheet) {
            NewFolderSheet(parentFolder: selectedFolder)
        }
        .sheet(isPresented: $showingEditBookmarkSheet) {
            if let bookmark = editingBookmark {
                EditBookmarkSheet(bookmark: bookmark)
            }
        }
        .alert("Delete Bookmark", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let bookmark = bookmarkToDelete {
                    deleteBookmark(bookmark)
                }
            }
        } message: {
            if let bookmark = bookmarkToDelete {
                Text("Are you sure you want to delete \"\(bookmark.title)\"?")
            }
        }
    }
    
    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 8)
    }
    
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sidebar header
            HStack {
                Text("Bookmarks")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { showingNewFolderSheet = true }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help("New Folder")
                
                Button(action: {
                    // Close bookmark panel
                    KeyboardShortcutHandler.shared.showBookmarksPanel = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .opacity(0.3)
                .padding(.horizontal, 16)
            
            // Folder list
            ScrollView {
                LazyVStack(spacing: 2) {
                    // "All Bookmarks" option
                    folderItem(
                        name: "All Bookmarks",
                        icon: "star.fill",
                        isSelected: selectedFolder == nil,
                        folder: nil
                    )
                    
                    // Root folders
                    ForEach(rootFolders, id: \.id) { folder in
                        folderItem(
                            name: folder.name,
                            icon: "folder.fill",
                            isSelected: selectedFolder?.id == folder.id,
                            folder: folder
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            
            Spacer()
        }
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .opacity(0.2)
        )
    }
    
    private func folderItem(name: String, icon: String, isSelected: Bool, folder: BookmarkFolder?) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedFolder = folder
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 16)
                
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                
                Spacer()
                
                if let folder = folder {
                    Text("\(folder.bookmarksArray.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(.secondary.opacity(0.2))
                        )
                } else {
                    Text("\(bookmarkService.getAllBookmarks().count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(.secondary.opacity(0.2))
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? .blue.opacity(0.15) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? .blue.opacity(0.4) : .clear, lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Main content header
            headerView
            
            Divider()
                .opacity(0.3)
                .padding(.horizontal, 20)
            
            // Bookmarks grid
            bookmarksContent
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            // Title and actions
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedFolder?.name ?? "All Bookmarks")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("\(filteredBookmarks.count) bookmark\(filteredBookmarks.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Add bookmark button
                    Button(action: addCurrentPageBookmark) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                            Text("Add Bookmark")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.blue.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.blue.opacity(0.4), lineWidth: 0.5)
                                )
                        )
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .medium))
                
                TextField("Search bookmarks...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var bookmarksContent: some View {
        ScrollView {
            if filteredBookmarks.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 220), spacing: 12)
                ], spacing: 12) {
                    ForEach(filteredBookmarks, id: \.id) { bookmark in
                        bookmarkCard(bookmark)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .scrollIndicators(.hidden)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedFolder == nil ? "star" : "folder")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)
            
            Text(searchText.isEmpty ? "No Bookmarks" : "No Results")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(searchText.isEmpty ? 
                 "Add bookmarks to access your favorite sites quickly" : 
                 "No bookmarks match your search")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if searchText.isEmpty {
                Button(action: addCurrentPageBookmark) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                        Text("Add Current Page")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.blue.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.blue.opacity(0.4), lineWidth: 0.5)
                            )
                    )
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.top, 60)
    }
    
    private func bookmarkCard(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Favicon and title
            HStack(spacing: 8) {
                // Favicon
                RoundedRectangle(cornerRadius: 6)
                    .fill(.regularMaterial)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Group {
                            if let faviconData = bookmark.faviconData,
                               let nsImage = NSImage(data: faviconData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Image(systemName: "globe")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
                
                Text(bookmark.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Actions on hover
                if hoveredBookmark?.id == bookmark.id {
                    HStack(spacing: 2) {
                        actionButton(icon: "square.and.pencil", action: {
                            editBookmark(bookmark)
                        })
                        
                        actionButton(icon: "trash", destructive: true, action: {
                            confirmDeleteBookmark(bookmark)
                        })
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            
            // URL
            Text(bookmark.url)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            // Creation date
            Text(formatDate(bookmark.creationDate))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(hoveredBookmark?.id == bookmark.id ? .blue.opacity(0.3) : .white.opacity(0.08), lineWidth: 0.5)
                }
        )
        .scaleEffect(hoveredBookmark?.id == bookmark.id ? 1.02 : 1.0)
        .shadow(color: .black.opacity(hoveredBookmark?.id == bookmark.id ? 0.1 : 0.05), radius: hoveredBookmark?.id == bookmark.id ? 8 : 2)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                hoveredBookmark = hovering ? bookmark : nil
            }
        }
        .onTapGesture {
            openBookmark(bookmark)
        }
        .contextMenu {
            Button("Open") { openBookmark(bookmark) }
            Button("Open in New Tab") { openBookmarkInNewTab(bookmark) }
            Divider()
            Button("Edit") { editBookmark(bookmark) }
            Button("Delete", role: .destructive) { confirmDeleteBookmark(bookmark) }
        }
    }
    
    private func actionButton(icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(destructive ? .red : .blue)
                .frame(width: 16, height: 16)
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
    
    private func addCurrentPageBookmark() {
        // Get current tab info and bookmark it
        // This would be implemented with actual tab data
        let sampleURL = "https://example.com"
        let sampleTitle = "Example Site"
        
        bookmarkService.addBookmark(url: sampleURL, title: sampleTitle, folder: selectedFolder)
    }
    
    private func openBookmark(_ bookmark: Bookmark) {
        if let url = URL(string: bookmark.url) {
            NotificationCenter.default.post(name: .navigateCurrentTab, object: url)
            KeyboardShortcutHandler.shared.showBookmarksPanel = false
        }
    }
    
    private func openBookmarkInNewTab(_ bookmark: Bookmark) {
        if let url = URL(string: bookmark.url) {
            NotificationCenter.default.post(name: .createNewTabWithURL, object: url)
        }
    }
    
    private func editBookmark(_ bookmark: Bookmark) {
        editingBookmark = bookmark
        showingEditBookmarkSheet = true
    }
    
    private func confirmDeleteBookmark(_ bookmark: Bookmark) {
        bookmarkToDelete = bookmark
        showingDeleteAlert = true
    }
    
    private func deleteBookmark(_ bookmark: Bookmark) {
        withAnimation(.easeOut(duration: 0.3)) {
            bookmarkService.deleteBookmark(bookmark)
        }
    }
}

// MARK: - Supporting Views

struct NewFolderSheet: View {
    let parentFolder: BookmarkFolder?
    @Environment(\.dismiss) private var dismiss
    @State private var folderName = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New Folder")
                .font(.headline)
            
            TextField("Folder name", text: $folderName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Create") {
                    if !folderName.isEmpty {
                        BookmarkService.shared.createFolder(name: folderName, parentFolder: parentFolder)
                        dismiss()
                    }
                }
                .disabled(folderName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

struct EditBookmarkSheet: View {
    let bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var url: String
    
    init(bookmark: Bookmark) {
        self.bookmark = bookmark
        self._title = State(initialValue: bookmark.title)
        self._url = State(initialValue: bookmark.url)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Bookmark")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.subheadline)
                TextField("Bookmark title", text: $title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(.subheadline)
                TextField("https://", text: $url)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Save") {
                    BookmarkService.shared.updateBookmark(bookmark, title: title, url: url, folder: bookmark.folder)
                    dismiss()
                }
                .disabled(title.isEmpty || url.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

#Preview {
    BookmarkView()
        .frame(width: 720, height: 500)
        .background(.black.opacity(0.3))
}