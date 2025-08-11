import Foundation

enum ResearchError: Error {
    case emptyContext
}

@MainActor
final class ResearchSynthesis {
    static func buildCitations(from context: WebpageContext, limit: Int = 3) -> [ResearchQuote] {
        let text = context.text
        let title = context.title
        let url = context.url

        // Naive approach: take first N headings and first sentences as quotes
        var quotes: [ResearchQuote] = []
        let sentences = text.split(separator: ".").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for s in sentences.prefix(limit) {
            if let range = text.range(of: s) {
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                let end = text.distance(from: text.startIndex, to: range.upperBound)
                quotes.append(
                    ResearchQuote(
                        url: url, title: title, quote: s + ".", context: title, startIndex: start,
                        endIndex: end))
            }
        }
        return quotes
    }
}
