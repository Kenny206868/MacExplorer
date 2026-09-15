import Foundation

/// Immutable listing projection, constructed once per directory/options revision
/// instead of for every tile, menu validation or pointer-selection update.
public struct FilePresentation: Sendable {
    public struct Group: Sendable {
        public let title: String
        public let entries: [FileEntry]
    }
    public let sorted: [FileEntry]
    public let groups: [Group]
    public let ordered: [FileEntry]
    private let positions: [URL: Int]
    public init(entries: [FileEntry], options: FolderOptions, calendar: Calendar = .current, now: Date = Date()) {
        try! self.init(entries: entries, options: options, calendar: calendar, now: now, checkingCancellation: {})
    }
    public init(entries: [FileEntry], options: FolderOptions, calendar: Calendar = .current, now: Date = Date(), checkingCancellation: () throws -> Void) throws {
        sorted = try options.sorted(entries, checkingCancellation: checkingCancellation)
        try checkingCancellation()
        if options.group == .none {
            groups = [Group(title: "", entries: sorted)]; ordered = sorted
        } else {
            var buckets: [String: [FileEntry]] = [:]
            var dates: [String: Date] = [:]
            let formatter = DateFormatter()
            formatter.calendar = calendar; formatter.locale = calendar.locale ?? .current
            formatter.timeZone = calendar.timeZone; formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            let today = calendar.startOfDay(for: now)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            for (index, entry) in sorted.enumerated() {
                if index & 255 == 0 { try checkingCancellation() }
                let title: String
                switch options.group {
                case .none: title = ""
                case .kind: title = entry.kind
                case .tags: title = entry.tags.first ?? "Untagged"
                case .modified:
                    if entry.modified >= tomorrow { title = "Future"; dates[title] = .distantFuture }
                    else if entry.modified >= today { title = "Today"; dates[title] = today }
                    else if entry.modified >= yesterday { title = "Yesterday"; dates[title] = yesterday }
                    else { title = formatter.string(from: entry.modified); dates[title] = calendar.dateInterval(of: .month, for: entry.modified)?.start ?? entry.modified }
                }
                buckets[title, default: []].append(entry)
            }
            let titles = buckets.keys.sorted { a, b in
                if options.group == .modified, let first = dates[a], let second = dates[b], first != second { return first > second }
                let order = a.localizedStandardCompare(b)
                return order == .orderedSame ? a < b : order == .orderedAscending
            }
            groups = titles.map { Group(title: $0, entries: buckets[$0] ?? []) }; ordered = groups.flatMap(\.entries)
        }
        try checkingCancellation()
        positions = Dictionary(ordered.enumerated().map { ($0.element.url, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }
    public func contains(_ url: URL) -> Bool { positions[url] != nil }
    public func selected(_ selection: Set<URL>) -> [FileEntry] {
        if selection.count >= max(1, ordered.count / 4) { return ordered.filter { selection.contains($0.url) } }
        return selection.compactMap { positions[$0] }.sorted().map { ordered[$0] }
    }
}
