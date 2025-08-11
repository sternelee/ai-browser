import Foundation

struct ResearchQuote: Identifiable, Codable {
    let id: UUID
    let url: String
    let title: String
    let quote: String
    let context: String
    let startIndex: Int
    let endIndex: Int

    init(url: String, title: String, quote: String, context: String, startIndex: Int, endIndex: Int)
    {
        self.id = UUID()
        self.url = url
        self.title = title
        self.quote = quote
        self.context = context
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}

struct ResearchResult: Identifiable, Codable {
    let id: UUID
    let question: String
    let summary: String
    let quotes: [ResearchQuote]
    let generatedAt: Date

    init(question: String, summary: String, quotes: [ResearchQuote]) {
        self.id = UUID()
        self.question = question
        self.summary = summary
        self.quotes = quotes
        self.generatedAt = Date()
    }
}
