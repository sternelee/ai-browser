import Foundation

struct Note: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var content: String
    let createdAt: Date
    var updatedAt: Date
    var color: String?
    var isFavorite: Bool
    
    init(title: String = "", content: String = "", color: String? = nil) {
        self.id = UUID()
        self.title = title.isEmpty ? "New Note" : title
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.color = color
        self.isFavorite = false
    }
    
    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "No content"
        }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? ""
        return firstLine.count > 50 ? String(firstLine.prefix(50)) + "..." : firstLine
    }
    
    var displayTitle: String {
        if !title.isEmpty && title != "New Note" {
            return title
        }
        
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Empty Note"
        }
        
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? ""
        let words = firstLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let titleWords = Array(words.prefix(5))
        return titleWords.joined(separator: " ")
    }
    
    mutating func updateContent(_ newContent: String) {
        content = newContent
        updatedAt = Date()
    }
    
    mutating func updateTitle(_ newTitle: String) {
        title = newTitle
        updatedAt = Date()
    }
    
    mutating func toggleFavorite() {
        isFavorite.toggle()
        updatedAt = Date()
    }
    
    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Note {
    static let sampleNotes: [Note] = [
        Note(
            title: "Welcome to Quick Notes",
            content: """
            # Welcome to Quick Notes
            
            This is your personal note-taking space. You can:
            
            - Create multiple notes
            - Edit them with Markdown
            - Search through all your notes
            - Mark favorites with ⭐
            
            **Keyboard Shortcuts:**
            - ⌘N: New note
            - ⌘D: Delete note
            - ⌘F: Search notes
            """
        ),
        Note(
            title: "Ideas",
            content: """
            ## Project Ideas
            
            - Build a next-gen browser ✅
            - Add AI integration
            - Create beautiful animations
            - Implement glass design
            """
        )
    ]
}