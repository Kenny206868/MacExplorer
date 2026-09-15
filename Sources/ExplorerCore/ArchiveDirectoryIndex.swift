import Foundation

/// Immutable immediate-child listings. Construct once on a read/presentation
/// executor; selection, scrolling and unfiltered folder navigation are lookups.
public struct ArchiveDirectoryIndex: Sendable {
    private let folders: [String: ArchiveDirectoryListing]
    public let entryCount: Int
    public let hasEncryption: Bool
    public let hasUnsupportedMembers: Bool

    public init(members: [ArchiveMember], maximumNodes: Int = 200_000, checkingCancellation: () throws -> Void = {}) throws {
        try checkingCancellation()
        guard maximumNodes >= members.count else { throw ExplorerError.message("Archive namespace exceeds the index memory budget.") }
        var nodes: [String: ArchiveMember] = [:]
        nodes.reserveCapacity(members.count)
        var encrypted = false, unsupported = false
        for (offset, member) in members.enumerated() {
            if offset & 255 == 0 { try checkingCancellation() }
            guard nodes.updateValue(member, forKey: member.path) == nil else {
                throw ExplorerError.message("Duplicate archive member: " + member.path)
            }
            encrypted = encrypted || member.encrypted
            unsupported = unsupported || member.unsupportedReason != nil
        }
        // Install implicit ancestors once; a known ancestor already owns its
        // entire ancestor chain. Explicit metadata always wins over synthesis.
        var visited = Set<String>()
        for (offset, member) in members.enumerated() {
            if offset & 255 == 0 { try checkingCancellation() }
            var parent = Self.parent(of: member.path)
            while !parent.isEmpty && visited.insert(parent).inserted {
                if let node = nodes[parent] {
                    guard node.isDirectory else { throw ExplorerError.message("An archive file is also a parent folder: " + parent) }
                } else {
                    guard nodes.count < maximumNodes else { throw ExplorerError.message("Archive namespace exceeds the index memory budget.") }
                    nodes[parent] = ArchiveMember(path: parent, isDirectory: true, size: 0,
                        encrypted: false, modified: nil, unsupportedReason: nil)
                }
                parent = Self.parent(of: parent)
            }
        }
        var grouped: [String: [ArchiveMember]] = ["": []]
        for (offset, member) in nodes.values.enumerated() {
            if offset & 255 == 0 { try checkingCancellation() }
            grouped[Self.parent(of: member.path), default: []].append(member)
            if member.isDirectory && grouped[member.path] == nil { grouped[member.path] = [] }
        }
        var folders: [String: ArchiveDirectoryListing] = [:]
        folders.reserveCapacity(grouped.count)
        for (folder, children) in grouped {
            try checkingCancellation()
            var comparisons = 0
            let ordered = try children.sorted { a, b in
                comparisons += 1
                if comparisons & 511 == 0 { try checkingCancellation() }
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                let order = a.name.localizedStandardCompare(b.name)
                return order == .orderedSame ? a.path < b.path : order == .orderedAscending
            }
            folders[folder] = try ArchiveDirectoryListing(entries: ordered, checkingCancellation: checkingCancellation)
        }
        self.folders = folders; entryCount = nodes.count
        hasEncryption = encrypted; hasUnsupportedMembers = unsupported
    }

    public func listing(in folder: String) -> ArchiveDirectoryListing { folders[folder] ?? .empty }
    public func containsFolder(_ folder: String) -> Bool { folders[folder] != nil }
    private static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }; return String(path[..<slash])
    }
}

/// Row identities and sparse selection are indexed together; no full archive
/// traversal or sorting is needed when selection changes.
public struct ArchiveDirectoryListing: Sendable {
    public static let empty = ArchiveDirectoryListing(entries: [], positions: [:])
    public let entries: [ArchiveMember]
    private let positions: [String: Int]
    private init(entries: [ArchiveMember], positions: [String: Int]) { self.entries = entries; self.positions = positions }
    init(entries: [ArchiveMember], checkingCancellation: () throws -> Void) throws {
        self.entries = entries
        var positions: [String: Int] = [:]; positions.reserveCapacity(entries.count)
        for (index, member) in entries.enumerated() {
            if index & 255 == 0 { try checkingCancellation() }
            positions[member.path] = index
        }
        self.positions = positions
    }
    public func contains(_ path: String) -> Bool { positions[path] != nil }
    public func selected(_ paths: Set<String>) -> [ArchiveMember] {
        if paths.count > max(1, entries.count / 4) { return entries.filter { paths.contains($0.path) } }
        return paths.compactMap { positions[$0] }.sorted().map { entries[$0] }
    }
    public func filtered(by query: String, checkingCancellation: () throws -> Void = {}) throws -> Self {
        guard !query.isEmpty else { return self }
        var matched: [ArchiveMember] = []
        for (index, member) in entries.enumerated() {
            if index & 255 == 0 { try checkingCancellation() }
            if member.name.localizedStandardContains(query) { matched.append(member) }
        }
        return try Self(entries: matched, checkingCancellation: checkingCancellation)
    }
}
