import Foundation
import Combine
import os.log

class NotesManager: ObservableObject {
    static let shared = NotesManager()
    
    @Published var notes: [Note] = []
    @Published var searchText: String = ""
    @Published var filteredNotes: [Note] = []
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Web", category: "NotesManager")
    private let notesKey = "quickNotes_v2"
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupSearchFiltering()
        loadNotes()
    }
    
    private func setupSearchFiltering() {
        Publishers.CombineLatest($notes, $searchText)
            .map { notes, searchText in
                if searchText.isEmpty {
                    return notes.sorted { $0.updatedAt > $1.updatedAt }
                }
                
                return notes.filter { note in
                    note.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                    note.content.localizedCaseInsensitiveContains(searchText)
                }.sorted { $0.updatedAt > $1.updatedAt }
            }
            .assign(to: &$filteredNotes)
    }
    
    func loadNotes() {
        if let data = UserDefaults.standard.data(forKey: notesKey) {
            do {
                notes = try JSONDecoder().decode([Note].self, from: data)
                logger.info("Loaded \(self.notes.count) notes from UserDefaults")
            } catch {
                logger.error("Failed to decode notes: \(error.localizedDescription)")
                migrateOldNote()
            }
        } else {
            migrateOldNote()
        }
        
        if notes.isEmpty {
            createSampleNotes()
        }
    }
    
    private func migrateOldNote() {
        if let oldData = UserDefaults.standard.data(forKey: "quickNotes"),
           let oldContent = String(data: oldData, encoding: .utf8),
           !oldContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            
            let migratedNote = Note(
                title: "Migrated Note",
                content: oldContent
            )
            notes = [migratedNote]
            saveNotes()
            
            UserDefaults.standard.removeObject(forKey: "quickNotes")
            logger.info("Migrated old note to new format")
        }
    }
    
    private func createSampleNotes() {
        notes = Note.sampleNotes
        saveNotes()
        logger.info("Created sample notes")
    }
    
    private func saveNotes() {
        do {
            let data = try JSONEncoder().encode(notes)
            UserDefaults.standard.set(data, forKey: notesKey)
            logger.info("Saved \(self.notes.count) notes to UserDefaults")
        } catch {
            logger.error("Failed to save notes: \(error.localizedDescription)")
        }
    }
    
    func createNote(title: String = "", content: String = "") -> Note {
        let note = Note(title: title, content: content)
        notes.insert(note, at: 0)
        saveNotes()
        logger.info("Created new note: \(note.id)")
        return note
    }
    
    func updateNote(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            notes.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
            saveNotes()
            logger.info("Updated note: \(note.id)")
        }
    }
    
    func deleteNote(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        saveNotes()
        logger.info("Deleted note: \(note.id)")
    }
    
    func deleteNotes(at indexSet: IndexSet) {
        let notesToDelete = indexSet.map { filteredNotes[$0] }
        for note in notesToDelete {
            deleteNote(note)
        }
    }
    
    func duplicateNote(_ note: Note) -> Note {
        let duplicated = Note(
            title: "\(note.title) Copy",
            content: note.content,
            color: note.color
        )
        notes.insert(duplicated, at: 0)
        saveNotes()
        logger.info("Duplicated note: \(note.id) -> \(duplicated.id)")
        return duplicated
    }
    
    func toggleFavorite(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index].toggleFavorite()
            saveNotes()
            logger.info("Toggled favorite for note: \(note.id)")
        }
    }
    
    func moveNote(from source: IndexSet, to destination: Int) {
        var mutableNotes = filteredNotes
        mutableNotes.move(fromOffsets: source, toOffset: destination)
        
        for (index, note) in mutableNotes.enumerated() {
            if let originalIndex = notes.firstIndex(where: { $0.id == note.id }) {
                var updatedNote = notes[originalIndex]
                updatedNote.updatedAt = Date().addingTimeInterval(TimeInterval(mutableNotes.count - index))
                notes[originalIndex] = updatedNote
            }
        }
        
        saveNotes()
        logger.info("Reordered notes")
    }
    
    func exportNotes() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        var export = "# Quick Notes Export\n\n"
        export += "Exported on: \(dateFormatter.string(from: Date()))\n\n"
        export += "---\n\n"
        
        for note in notes.sorted(by: { $0.createdAt < $1.createdAt }) {
            export += "## \(note.displayTitle)\n\n"
            export += "**Created:** \(dateFormatter.string(from: note.createdAt))\n"
            export += "**Updated:** \(dateFormatter.string(from: note.updatedAt))\n"
            if note.isFavorite {
                export += "**Favorite:** ⭐\n"
            }
            export += "\n\(note.content)\n\n"
            export += "---\n\n"
        }
        
        logger.info("Exported \(self.notes.count) notes")
        return export
    }
    
    func clearAllNotes() {
        notes.removeAll()
        saveNotes()
        logger.info("Cleared all notes")
    }
    
    var favoriteNotes: [Note] {
        notes.filter { $0.isFavorite }.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    var recentNotes: [Note] {
        Array(notes.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
    }
}