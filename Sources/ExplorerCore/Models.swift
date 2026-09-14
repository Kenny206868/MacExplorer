import Foundation
import UniformTypeIdentifiers

public enum ExplorerError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let value): return value } }
}

public struct FileEntry: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isSymbolicLink: Bool
    public let isHidden: Bool
    public let isLocked: Bool
    public let size: Int64
    public let modified: Date
    public let created: Date
    public let kind: String
    public let tags: [String]
    public let isCloud: Bool
    public let isDownloaded: Bool
    public var canBrowse: Bool { isDirectory && !isPackage }
    public var isImage: Bool { UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true }
    public var sizeText: String { isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    public var extensionName: String { url.pathExtension.lowercased() }
    public static let resourceKeys: Set<URLResourceKey> = [.nameKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey, .isUserImmutableKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .localizedTypeDescriptionKey, .tagNamesKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]

    public init(url: URL) throws {
        self.url = url.standardizedFileURL
        let v = try url.resourceValues(forKeys: Self.resourceKeys)
        name = v.name ?? url.lastPathComponent
        isDirectory = v.isDirectory ?? false
        isPackage = v.isPackage ?? false
        isSymbolicLink = v.isSymbolicLink ?? false
        isHidden = v.isHidden ?? name.hasPrefix(".")
        isLocked = v.isUserImmutable ?? false
        size = Int64(v.fileSize ?? 0)
        modified = v.contentModificationDate ?? .distantPast
        created = v.creationDate ?? .distantPast
        kind = v.localizedTypeDescription ?? (isDirectory ? "Folder" : "File")
        tags = v.tagNames ?? []
        isCloud = v.isUbiquitousItem ?? false
        isDownloaded = !isCloud || v.ubiquitousItemDownloadingStatus == .current || v.ubiquitousItemDownloadingStatus == .downloaded
    }
}

public enum ViewMode: String, CaseIterable, Codable, Sendable {
    case extraLarge = "Extra large icons", large = "Large icons", medium = "Medium icons", small = "Small icons", list = "List", details = "Details", tiles = "Tiles", content = "Content", gallery = "Gallery"
    public var iconSize: Double { switch self { case .extraLarge: return 128; case .large, .gallery: return 80; case .medium, .tiles: return 48; case .content: return 40; default: return 20 } }
    public var symbol: String { switch self { case .details, .list: return "list.bullet"; case .content: return "list.bullet.rectangle"; case .gallery: return "photo.on.rectangle"; default: return "square.grid.2x2" } }
}
public enum SortField: String, CaseIterable, Codable, Sendable { case name = "Name", modified = "Date modified", created = "Date created", kind = "Kind", size = "Size", tags = "Tags" }
public enum GroupField: String, CaseIterable, Codable, Sendable { case none = "None", kind = "Kind", modified = "Date modified", tags = "Tags" }
public struct FolderOptions: Codable, Sendable {
    public var view: ViewMode = .details
    public var sort: SortField = .name
    public var descending = false
    public var foldersFirst = true
    public var group: GroupField = .none
    public init() {}
    public func sorted(_ entries: [FileEntry]) -> [FileEntry] {
        entries.sorted { a, b in
            if foldersFirst && a.canBrowse != b.canBrowse { return a.canBrowse }
            let result: ComparisonResult
            switch sort {
            case .name: result = a.name.localizedStandardCompare(b.name)
            case .modified: result = a.modified.compare(b.modified)
            case .created: result = a.created.compare(b.created)
            case .kind: result = a.kind.localizedStandardCompare(b.kind)
            case .size: result = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case .tags: result = a.tags.joined().localizedStandardCompare(b.tags.joined())
            }
            if result == .orderedSame { return a.url.path < b.url.path }
            return descending ? result == .orderedDescending : result == .orderedAscending
        }
    }
}

public enum Location: Hashable, Codable, Sendable {
    case home, gallery, computer, network, trash, folder(URL), tag(String)
    public var title: String {
        switch self {
        case .home: return "Home"
        case .gallery: return "Gallery"
        case .computer: return "This Mac"
        case .network: return "Network"
        case .trash: return "Trash"
        case .folder(let url): return url.path == "/" ? "Macintosh HD" : url.lastPathComponent
        case .tag(let value): return value
        }
    }
    public var symbol: String {
        switch self { case .home: return "house"; case .gallery: return "photo.on.rectangle"; case .computer: return "desktopcomputer"; case .network: return "network"; case .trash: return "trash"; case .folder: return "folder"; case .tag: return "tag" }
    }
    public var directory: URL? {
        switch self {
        case .folder(let url): return url
        case .gallery: return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        default: return nil
        }
    }
}

public struct NavigationHistory: Codable, Sendable {
    public private(set) var locations: [Location]
    public private(set) var index: Int
    public var current: Location { locations[index] }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index + 1 < locations.count }
    public init(_ initial: Location = .home) { locations = [initial]; index = 0 }
    public mutating func navigate(_ location: Location) {
        guard location != current else { return }
        locations = Array(locations.prefix(index + 1)); locations.append(location)
        if locations.count > 128 { locations.removeFirst() }
        index = locations.count - 1
    }
    public mutating func back() { if canGoBack { index -= 1 } }
    public mutating func forward() { if canGoForward { index += 1 } }
}

public struct Bookmark: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var path: String
    public var data: Data?
    public init(_ url: URL) {
        id = UUID(); path = url.path
        data = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    public var url: URL {
        if let data { var stale = false; if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) { return url } }
        return URL(fileURLWithPath: path)
    }
}

public enum FileNames {
    public static func validate(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0"), name.utf8.count <= 255 else {
            throw ExplorerError.message("Use a nonempty name of at most 255 UTF-8 bytes, without slash, colon, or NUL.")
        }
    }
    public static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
    public static func unique(_ url: URL) -> URL {
        if !exists(url) { return url }
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) (\(index))" + (ext.isEmpty ? "" : ".\(ext)"))
            if !exists(candidate) { return candidate }; index += 1
        }
    }
    public static func isDescendant(_ child: URL, of parent: URL) -> Bool {
        let a = child.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let b = parent.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return a.count >= b.count && Array(a.prefix(b.count)) == b
    }
    public static func independentRoots(_ urls: [URL]) -> [URL] {
        let unique = Array(Set(urls.map(\.standardizedFileURL))).sorted { $0.pathComponents.count < $1.pathComponents.count }
        var result: [URL] = []
        for url in unique {
            if !result.contains(where: { parent in
                guard (try? parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return false }
                return isDescendant(url, of: parent)
            }) { result.append(url) }
        }
        return result
    }
}
