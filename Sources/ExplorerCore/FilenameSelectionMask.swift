import Foundation

/// Bounded, compiled basename masks. No regular expressions, shell evaluation,
/// path traversal or recursive enumeration. Matching uses a two-row automaton
/// rather than potentially exponential wildcard backtracking.
public struct FilenameSelectionMask: Sendable {
    public enum MaskError: LocalizedError, Equatable {
        case empty, tooLong, tooManyPatterns, invalidSeparator
        public var errorDescription: String? {
            switch self {
            case .empty: return "Enter a filename mask, for example *.swift;*.cs."
            case .tooLong: return "Use at most 4,096 characters overall and 256 per mask."
            case .tooManyPatterns: return "Use at most 32 filename masks."
            case .invalidSeparator: return "Use one | to separate included and excluded masks. Masks match names, not paths."
            }
        }
    }
    private let included: [[Character]]
    private let excluded: [[Character]]
    public let caseSensitive: Bool

    public init(_ source: String, caseSensitive: Bool = false) throws {
        guard source.count <= 4096 else { throw MaskError.tooLong }
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw MaskError.empty }
        let sections = source.split(separator: "|", omittingEmptySubsequences: false)
        guard sections.count <= 2, !source.contains("/"), !source.contains("\0") else { throw MaskError.invalidSeparator }
        func parse(_ value: Substring) throws -> [[Character]] {
            try value.split(separator: ";", omittingEmptySubsequences: true).compactMap { part in
                let text = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                guard text.count <= 256 else { throw MaskError.tooLong }
                let characters = Array(Self.normalize(text == "*.*" ? "*" : text, caseSensitive: caseSensitive))
                var result: [Character] = []
                for character in characters where character != "*" || result.last != "*" { result.append(character) }
                return result
            }
        }
        let first = try parse(sections[0])
        included = first.isEmpty ? [["*"]] : first
        excluded = sections.count == 2 ? try parse(sections[1]) : []
        guard included.count + excluded.count <= 32 else { throw MaskError.tooManyPatterns }
        self.caseSensitive = caseSensitive
    }
    public func matches(_ name: String) -> Bool {
        let input = Array(Self.normalize(name, caseSensitive: caseSensitive))
        return included.contains { Self.match($0, input) } && !excluded.contains { Self.match($0, input) }
    }
    private static func normalize(_ value: String, caseSensitive: Bool) -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
        return caseSensitive ? normalized : normalized.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func match(_ pattern: [Character], _ name: [Character]) -> Bool {
        var previous = [Bool](repeating: false, count: pattern.count + 1)
        var next = previous
        previous[0] = true
        for index in pattern.indices { previous[index + 1] = pattern[index] == "*" && previous[index] }
        for character in name {
            next[0] = false
            for index in pattern.indices {
                let token = pattern[index]
                next[index + 1] = token == "*" ? (next[index] || previous[index + 1])
                    : previous[index] && (token == "?" || token == character)
            }
            swap(&previous, &next)
        }
        return previous[pattern.count]
    }
}
