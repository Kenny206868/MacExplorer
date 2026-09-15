import Foundation
import CryptoKit

public struct SearchExpression: Sendable {
    private static let tokenizer = try! NSRegularExpression(pattern: #"(?:[^\s\"]|\"[^\"]*\")+"#)
    private let modifiedCutoff: Date?
    public let text: String
    public let words: [String]
    public let filters: [String: String]
    public init(_ text: String) {
        self.text = text
        let regex = Self.tokenizer
        var words: [String] = [], filters: [String: String] = [:]
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let token = String(text[range]).replacingOccurrences(of: "\"", with: "")
            if let colon = token.firstIndex(of: ":"), ["name", "ext", "kind", "tag", "size", "modified", "content"].contains(String(token[..<colon]).lowercased()) {
                filters[String(token[..<colon]).lowercased()] = String(token[token.index(after: colon)...])
            } else { words.append(token) }
        }
        self.words = words; self.filters = filters
        if let value = filters["modified"] {
            let now = Date(), calendar = Calendar.current
            switch value.lowercased() {
            case "today": modifiedCutoff = calendar.startOfDay(for: now)
            case "week": modifiedCutoff = calendar.date(byAdding: .day, value: -7, to: now)
            case "month": modifiedCutoff = calendar.date(byAdding: .month, value: -1, to: now)
            default: modifiedCutoff = ISO8601DateFormatter().date(from: value + "T00:00:00Z") ?? .distantPast
            }
        } else { modifiedCutoff = nil }
    }
    public func matches(_ file: FileEntry) -> Bool {
        guard words.allSatisfy({ file.name.localizedCaseInsensitiveContains($0) }) else { return false }
        for (key, value) in filters {
            switch key {
            case "name": if !file.name.localizedCaseInsensitiveContains(value) { return false }
            case "ext": if file.extensionName != value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) { return false }
            case "kind": if value.lowercased() == "folder" ? !file.canBrowse : !file.kind.localizedCaseInsensitiveContains(value) { return false }
            case "tag": if !file.tags.contains(where: { $0.localizedCaseInsensitiveContains(value) }) { return false }
            case "size":
                let greater = !value.hasPrefix("<")
                let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "<>=")).uppercased()
                let number = Double(cleaned.prefix { $0.isNumber || $0 == "." }) ?? 0
                let factor: Double = cleaned.hasSuffix("GB") ? 1_000_000_000 : cleaned.hasSuffix("MB") ? 1_000_000 : cleaned.hasSuffix("KB") ? 1_000 : 1
                if greater ? Double(file.size) < number * factor : Double(file.size) > number * factor { return false }
            case "modified": if let modifiedCutoff, file.modified < modifiedCutoff { return false }
            default: break
            }
        }
        return true
    }
    public var spotlightPredicate: NSPredicate {
        var predicates: [NSPredicate] = []
        for word in words { predicates.append(NSPredicate(format: "%K CONTAINS[cd] %@", "kMDItemFSName", word)) }
        if let content = filters["content"] { predicates.append(NSPredicate(format: "%K CONTAINS[cd] %@", "kMDItemTextContent", content)) }
        if let tag = filters["tag"] { predicates.append(NSPredicate(format: "%K CONTAINS[cd] %@", "kMDItemUserTags", tag)) }
        return predicates.isEmpty ? NSPredicate(value: true) : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}
public struct DirectorySnapshot: Sendable {
    public var entries: [FileEntry]
    public var warnings: [String]
    public var truncated: Bool
    public init(entries: [FileEntry] = [], warnings: [String] = [], truncated: Bool = false) { self.entries = entries; self.warnings = warnings; self.truncated = truncated }
}
public actor FileService {
    public init() {}
    public nonisolated func list(_ url: URL, showHidden: Bool) async throws -> DirectorySnapshot {
        try await FileReadExecutor.browsing.run { try FileSystemReader(cancellation: $0).list(url, showHidden: showHidden) }
    }
    public nonisolated func entries(_ urls: [URL]) async throws -> DirectorySnapshot {
        try await FileReadExecutor.browsing.run { try FileSystemReader(cancellation: $0).entries(urls) }
    }
    public nonisolated func recentEntries(_ bookmarks: [Bookmark]) async throws -> DirectorySnapshot {
        try await FileReadExecutor.browsing.run { cancellation in
            var urls: [URL] = []; urls.reserveCapacity(bookmarks.count)
            for bookmark in bookmarks { try cancellation.check(); let url = bookmark.url; if FileNames.exists(url) { urls.append(url) } }
            return try FileSystemReader(cancellation: cancellation).entries(urls)
        }
    }
    public nonisolated func search(_ roots: [URL], expression: SearchExpression, showHidden: Bool, imagesOnly: Bool = false, limit: Int = 25_000) async throws -> DirectorySnapshot {
        try await FileReadExecutor.bulk.run { try FileSystemReader(cancellation: $0).search(roots, expression: expression, showHidden: showHidden, imagesOnly: imagesOnly, limit: limit) }
    }
    public nonisolated func inspect(_ url: URL) async throws -> [String: String] {
        try await FileReadExecutor.metadata.run { try FileSystemReader(cancellation: $0).inspect(url) }
    }
    public nonisolated func allocatedSize(_ url: URL) async throws -> (Int64, Int) {
        try await FileReadExecutor.bulk.run { try FileSystemReader(cancellation: $0).allocatedSize(url) }
    }
    public nonisolated func checksum(_ url: URL) async throws -> String {
        try await FileReadExecutor.bulk.run { try FileSystemReader(cancellation: $0).checksum(url) }
    }
    public func setMetadata(_ urls: [URL], tags: [String]?, locked: Bool?, permissions: Int?) throws {
        for var url in urls {
            try Task.checkCancellation()
            var values = URLResourceValues()
            if let tags { try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey) }
            if let locked { values.isUserImmutable = locked }
            try url.setResourceValues(values)
            if let permissions { try FileManager.default.setAttributes([.posixPermissions: permissions & 0o777], ofItemAtPath: url.path) }
        }
    }
    public func requestDownload(_ urls: [URL]) throws { for url in urls { try FileManager.default.startDownloadingUbiquitousItem(at: url) } }
    public func evict(_ urls: [URL]) throws { for url in urls { try FileManager.default.evictUbiquitousItem(at: url) } }
}
private struct FileSystemReader {
    let cancellation: FileReadCancellation
    func list(_ url: URL, showHidden: Bool) throws -> DirectorySnapshot {
        try cancellation.check()
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(FileEntry.resourceKeys), options: showHidden ? [] : [.skipsHiddenFiles])
        return try entries(urls)
    }
    func entries(_ urls: [URL]) throws -> DirectorySnapshot {
        var result = DirectorySnapshot(); result.entries.reserveCapacity(urls.count)
        for url in urls {
            try cancellation.check()
            do { result.entries.append(try FileEntry(url: url)) }
            catch { if result.warnings.count < 20 { result.warnings.append("\(url.lastPathComponent): \(error.localizedDescription)") } }
        }
        return result
    }
    func search(_ roots: [URL], expression: SearchExpression, showHidden: Bool, imagesOnly: Bool = false, limit: Int = 25_000) throws -> DirectorySnapshot {
        var result = DirectorySnapshot()
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [.skipsPackageDescendants] : [.skipsPackageDescendants, .skipsHiddenFiles]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(FileEntry.resourceKeys), options: options, errorHandler: { url, error in
                if result.warnings.count < 20 { result.warnings.append("\(url.path): \(error.localizedDescription)") }; return !cancellation.isCancelled
            }) else { continue }
            for case let url as URL in enumerator {
                try cancellation.check()
                do {
                    let item = try FileEntry(url: url)
                    if item.isSymbolicLink { enumerator.skipDescendants() }
                    if (!imagesOnly || item.isImage) && expression.matches(item) { result.entries.append(item) }
                    if result.entries.count >= limit { result.truncated = true; return result }
                } catch { if result.warnings.count < 20 { result.warnings.append(error.localizedDescription) } }
            }
        }
        return result
    }
    func inspect(_ url: URL) throws -> [String: String] {
        let a = try FileManager.default.attributesOfItem(atPath: url.path), entry = try FileEntry(url: url)
        let values = try url.resourceValues(forKeys: [.volumeNameKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .isReadableKey, .isWritableKey, .isExecutableKey])
        return ["Name": entry.name, "Kind": entry.kind, "Location": url.deletingLastPathComponent().path, "Size": ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file), "Created": entry.created.formatted(), "Modified": entry.modified.formatted(), "Owner": a[.ownerAccountName] as? String ?? "—", "Group": a[.groupOwnerAccountName] as? String ?? "—", "Permissions": String(format: "%03o", (a[.posixPermissions] as? NSNumber)?.intValue ?? 0), "Volume": values.volumeName ?? "—", "Available": ByteCountFormatter.string(fromByteCount: Int64(values.volumeAvailableCapacity ?? 0), countStyle: .file), "Tags": entry.tags.joined(separator: ", "), "Symbolic link": entry.isSymbolicLink ? ((try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? "Yes") : "No", "Read access": values.isReadable == true ? "Yes" : "No", "Write access": values.isWritable == true ? "Yes" : "No", "Cloud": entry.isCloud ? (entry.isDownloaded ? "Downloaded" : "Online only") : "Local"]
    }
    func allocatedSize(_ url: URL) throws -> (Int64, Int) {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey, .isDirectoryKey]
        let root = try url.resourceValues(forKeys: keys)
        if root.isDirectory != true { return (Int64(root.totalFileAllocatedSize ?? root.fileAllocatedSize ?? 0), 1) }
        var bytes: Int64 = 0, count = 0
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return (0, 0) }
        for case let child as URL in enumerator {
            try cancellation.check()
            let values = try child.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { enumerator.skipDescendants() }
            let (sum, overflow) = bytes.addingReportingOverflow(Int64(max(0, values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)))
            bytes = overflow ? .max : sum; count += 1
        }
        return (bytes, count)
    }
    func checksum(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { try cancellation.check(); hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
