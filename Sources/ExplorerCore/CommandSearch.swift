import Foundation

/// Immutable, pre-normalized command index. All query words must match; title
/// prefixes and word boundaries rank above aliases and sparse subsequences.
/// Input is bounded so a pasted document cannot monopolize the UI thread.
public struct CommandSearch: Sendable {
    public struct Item: Sendable, Equatable {
        public let id: String
        public let title: String
        public let category: String
        public let aliases: String
        public init(id: String, title: String, category: String, aliases: String = "") {
            self.id = id; self.title = title; self.category = category; self.aliases = aliases
        }
    }
    private struct Indexed: Sendable {
        let item: Item
        let title: String
        let words: [String]
        let aliases: String
        let order: Int
    }
    private let entries: [Indexed]
    public init(_ items: [Item]) {
        var seen = Set<String>()
        entries = items.enumerated().compactMap { index, item in
            guard seen.insert(item.id).inserted else { return nil }
            let title = Self.normalize(item.title)
            return Indexed(item: item, title: title, words: title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init),
                           aliases: Self.normalize(item.category + " " + item.aliases), order: index)
        }
    }
    public func results(for query: String, limit: Int = 100) -> [Item] {
        let text = Self.normalize(String(query.prefix(256)))
        let words = Array(text.split(whereSeparator: \.isWhitespace).prefix(12)).map(String.init)
        let limit = max(0, min(1000, limit))
        if words.isEmpty { return Array(entries.prefix(limit)).map(\.item) }
        return entries.compactMap { entry -> (Indexed, Int)? in
            var score = entry.title == text ? 1000 : entry.title.hasPrefix(text) ? 300 : 0
            for word in words {
                if entry.title.hasPrefix(word) { score += 120 }
                else if entry.words.contains(where: { $0.hasPrefix(word) }) { score += 90 }
                else if entry.title.contains(word) { score += 60 }
                else if entry.aliases.contains(word) { score += 35 }
                else if let cost = Self.subsequenceCost(word, in: entry.title) { score += max(1, 25 - cost) }
                else { return nil }
            }
            return (entry, score)
        }.sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.0.order < rhs.0.order : lhs.1 > rhs.1 }
            .prefix(limit).map { $0.0.item }
    }
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func subsequenceCost(_ needle: String, in haystack: String) -> Int? {
        guard needle.count >= 2 else { return nil }
        var iterator = needle.makeIterator(), next = iterator.next(), first: Int?, last = 0
        for (index, character) in haystack.enumerated() where character == next {
            if first == nil { first = index }; last = index; next = iterator.next()
            if next == nil { return last - (first ?? 0) + 1 - needle.count }
        }
        return nil
    }
}
