import SwiftUI
import UniformTypeIdentifiers

struct QuickNotesView: View {
    @StateObject private var notesManager = NotesManager.shared
    @State private var selectedNote: Note?
    @State private var isEditing = false
    @State private var showingSearch = false
    @State private var editingContent = ""
    @State private var editingTitle = ""
    @FocusState private var isEditorFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            if showingSearch {
                searchSection
            }
            
            if selectedNote != nil {
                editorSection
            } else {
                notesGridSection
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.primary.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: 800)
        .onAppear {
            if notesManager.notes.isEmpty {
                notesManager.loadNotes()
            }
            setupKeyboardShortcuts()
        }
        .onDisappear {
            removeKeyboardShortcuts()
        }
    }
    
    private var headerSection: some View {
        HStack {
            Label("Quick Notes", systemImage: "note.text")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            HStack(spacing: 8) {
                if selectedNote != nil {
                    Button(action: backToGrid) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                
                Button(action: toggleSearch) {
                    Image(systemName: showingSearch ? "xmark" : "magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                
                Menu {
                    Button("Export All Notes") {
                        exportNotes()
                    }
                    
                    Button("Clear All Notes") {
                        clearAllNotes()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                
                Button(action: createNewNote) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
    
    private var searchSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search notes...", text: $notesManager.searchText)
                .textFieldStyle(.plain)
            
            if !notesManager.searchText.isEmpty {
                Button(action: { notesManager.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private var notesGridSection: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 250, maximum: 300), spacing: 12)
            ], spacing: 12) {
                ForEach(notesManager.filteredNotes) { note in
                    NoteCardView(note: note) {
                        selectNote(note)
                    }
                    .onDrag {
                        NSItemProvider(object: note.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: NoteDropDelegate(
                        note: note,
                        notesManager: notesManager,
                        filteredNotes: notesManager.filteredNotes
                    ))
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 400)
    }
    
    private var editorSection: some View {
        VStack(spacing: 0) {
            if selectedNote != nil {
                titleEditorSection
                contentEditorSection
                editorToolbar
            }
        }
    }
    
    private var titleEditorSection: some View {
        VStack(spacing: 8) {
            HStack {
                if isEditing {
                    TextField("Note title", text: $editingTitle)
                        .font(.title2.bold())
                        .textFieldStyle(.plain)
                } else {
                    Text(selectedNote?.displayTitle ?? "")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
                
                Button(action: toggleFavorite) {
                    Image(systemName: selectedNote?.isFavorite == true ? "star.fill" : "star")
                        .foregroundStyle(selectedNote?.isFavorite == true ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            HStack {
                Text("Updated \(timeAgoString(from: selectedNote?.updatedAt ?? Date()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !isEditing {
                    Button("Edit") {
                        startEditing()
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }
    
    private var contentEditorSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isEditing {
                    TextEditor(text: $editingContent)
                        .font(.system(.body, design: .monospaced))
                        .focused($isEditorFocused)
                        .background(.clear)
                        .scrollContentBackground(.hidden)
                } else {
                    Text(selectedNote?.content ?? "")
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 300)
    }
    
    private var editorToolbar: some View {
        HStack {
            if isEditing {
                Button("Cancel") {
                    cancelEditing()
                }
                .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("Save") {
                    saveNote()
                }
                .foregroundStyle(.blue)
                .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button(action: duplicateNote) {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: deleteNote) {
                    Label("Delete", systemImage: "trash")
                }
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .font(.caption)
    }
    
    private func selectNote(_ note: Note) {
        selectedNote = note
        editingTitle = note.title
        editingContent = note.content
    }
    
    private func backToGrid() {
        if isEditing {
            saveNote()
        }
        selectedNote = nil
        isEditing = false
    }
    
    private func createNewNote() {
        let newNote = notesManager.createNote()
        selectedNote = newNote
        editingTitle = newNote.title
        editingContent = newNote.content
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isEditorFocused = true
        }
    }
    
    private func startEditing() {
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isEditorFocused = true
        }
    }
    
    private func saveNote() {
        guard var note = selectedNote else { return }
        
        note.updateTitle(editingTitle)
        note.updateContent(editingContent)
        notesManager.updateNote(note)
        selectedNote = note
        isEditing = false
    }
    
    private func cancelEditing() {
        if let note = selectedNote {
            editingTitle = note.title
            editingContent = note.content
        }
        isEditing = false
    }
    
    private func deleteNote() {
        guard let note = selectedNote else { return }
        notesManager.deleteNote(note)
        selectedNote = nil
        isEditing = false
    }
    
    private func duplicateNote() {
        guard let note = selectedNote else { return }
        let duplicated = notesManager.duplicateNote(note)
        selectedNote = duplicated
        editingTitle = duplicated.title
        editingContent = duplicated.content
    }
    
    private func toggleFavorite() {
        guard let note = selectedNote else { return }
        notesManager.toggleFavorite(note)
        selectedNote = notesManager.notes.first { $0.id == note.id }
    }
    
    private func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showingSearch.toggle()
            if !showingSearch {
                notesManager.searchText = ""
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Keyboard Shortcuts
    private func setupKeyboardShortcuts() {
        NotificationCenter.default.addObserver(
            forName: .newNoteRequested,
            object: nil,
            queue: .main
        ) { _ in
            createNewNote()
        }
        
        NotificationCenter.default.addObserver(
            forName: .deleteNoteRequested,
            object: nil,
            queue: .main
        ) { _ in
            if selectedNote != nil {
                deleteNote()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .searchNotesRequested,
            object: nil,
            queue: .main
        ) { _ in
            if selectedNote == nil {
                showingSearch = true
            }
        }
    }
    
    private func removeKeyboardShortcuts() {
        NotificationCenter.default.removeObserver(self, name: .newNoteRequested, object: nil)
        NotificationCenter.default.removeObserver(self, name: .deleteNoteRequested, object: nil)
        NotificationCenter.default.removeObserver(self, name: .searchNotesRequested, object: nil)
    }
    
    // MARK: - Export/Import Functions
    private func exportNotes() {
        let exportContent = notesManager.exportNotes()
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "QuickNotes_\(Date().formatted(.iso8601.year().month().day())).md"
        savePanel.title = "Export Notes"
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                do {
                    try exportContent.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Export failed: \(error)")
                }
            }
        }
    }
    
    private func clearAllNotes() {
        let alert = NSAlert()
        alert.messageText = "Clear All Notes"
        alert.informativeText = "Are you sure you want to delete all notes? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            notesManager.clearAllNotes()
        }
    }
}

struct NoteCardView: View {
    let note: Note
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(note.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if note.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }
                
                if !note.content.isEmpty {
                    Text(note.preview)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Empty note")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
                
                Text(timeAgoString(from: note.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12)
            .frame(height: 120)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0)
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                // Subtle hover effect handled by macOS
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct NoteDropDelegate: DropDelegate {
    let note: Note
    let notesManager: NotesManager
    let filteredNotes: [Note]
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedNoteId = info.itemProviders(for: [.text]).first?.registeredTypeIdentifiers.first,
              let uuid = UUID(uuidString: draggedNoteId.components(separatedBy: ".").last ?? ""),
              let draggedNote = notesManager.notes.first(where: { $0.id == uuid }),
              draggedNote.id != note.id else {
            return false
        }
        
        // Find indices in the filtered notes array
        guard let fromIndex = filteredNotes.firstIndex(where: { $0.id == draggedNote.id }),
              let toIndex = filteredNotes.firstIndex(where: { $0.id == note.id }) else {
            return false
        }
        
        // Perform the reorder
        notesManager.moveNote(from: IndexSet(integer: fromIndex), to: toIndex > fromIndex ? toIndex + 1 : toIndex)
        
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func dropEntered(info: DropInfo) {
        // Visual feedback could be added here
    }
    
    func dropExited(info: DropInfo) {
        // Reset visual feedback
    }
}

#Preview {
    QuickNotesView()
        .frame(width: 800, height: 600)
        .padding()
}