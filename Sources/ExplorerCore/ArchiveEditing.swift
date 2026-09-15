import Foundation

/// Explicit mutations use virtual member paths, never filesystem URLs.
public enum ArchiveMutation: Sendable {
    case rename(path: String, to: String)
    case remove(paths: Set<String>)
    case createDirectory(path: String)
    case importItems(sources: [URL], into: String)
    case replace(path: String, source: URL)
}
struct ArchiveImport: Sendable {
    let path: String
    let source: URL?
    let directory: Bool
    let fingerprint: FileFingerprint?
    let size: Int64
}
/// Validate the complete namespace before writing. Imports never overwrite;
/// replacement is a separate explicit operation. Implicit directories, parent
/// conflicts, Unicode aliases and case collisions participate in validation.
struct ArchiveEditPlan {
    var mapping: [String: String] = [:]
    var removed = Set<String>()
    var imports: [ArchiveImport] = []
    let expectedPaths: Set<String>
    init(catalog: ArchiveCatalog, mutation: ArchiveMutation, options: ArchiveReadOptions, control: OperationControl) throws {
        guard !catalog.containsEncryption else { throw ExplorerError.message("Encrypted archives are read-only; editing must not remove their protection.") }
        guard catalog.members.allSatisfy({ $0.unsupportedReason == nil }) else { throw ExplorerError.message("Archives containing links or special objects are read-only.") }
        let original = Dictionary(uniqueKeysWithValues: catalog.members.map { ($0.path, $0.isDirectory) })
        var namespace = try Self.namespace(original)
        func require(_ path: String) throws -> Bool {
            guard let directory = namespace[path] else { throw ExplorerError.message("Archive member no longer exists: " + path) }; return directory
        }
        func parent(_ path: String) throws {
            let path = path.split(separator: "/").dropLast().joined(separator: "/")
            guard path.isEmpty || namespace[path] == true else { throw ExplorerError.message("Choose an existing archive folder.") }
        }
        switch mutation {
        case .rename(let path, let destination):
            let directory = try require(path)
            guard try ArchivePath.parse(destination, directory: directory) == destination else { throw ExplorerError.message("Use a canonical relative archive path.") }
            try parent(destination)
            guard destination != path, !destination.hasPrefix(path + "/"), namespace[destination] == nil else { throw ExplorerError.message("The new archive path is occupied or inside the selected folder.") }
            for member in catalog.members where member.path == path || member.path.hasPrefix(path + "/") { mapping[member.path] = destination + member.path.dropFirst(path.count) }
        case .remove(let paths):
            guard !paths.isEmpty else { throw ExplorerError.message("Select archive members to remove.") }
            for path in paths { _ = try require(path) }
            removed = Set(catalog.members.filter { member in paths.contains { member.path == $0 || member.path.hasPrefix($0 + "/") } }.map(\.path))
        case .createDirectory(let path):
            guard try ArchivePath.parse(path, directory: true) == path, namespace[path] == nil else { throw ExplorerError.message("The archive folder name is invalid or occupied.") }
            try parent(path); imports = [ArchiveImport(path: path, source: nil, directory: true, fingerprint: nil, size: 0)]
        case .importItems(let sources, let folder):
            guard folder.isEmpty || namespace[folder] == true else { throw ExplorerError.message("Choose an existing archive folder.") }
            guard !sources.isEmpty else { throw ExplorerError.message("Choose files or folders to add.") }
            var work = sources.map { ($0, folder.isEmpty ? $0.lastPathComponent : folder + "/" + $0.lastPathComponent) }
            while let (url, path) = work.popLast() {
                try control.checkpoint()
                guard imports.count < options.maximumEntries else { throw ExplorerError.message("Import exceeds the configured entry limit.") }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path), type = attributes[.type] as? FileAttributeType
                guard type == .typeDirectory || type == .typeRegular else { throw ExplorerError.message("Import ordinary files and folders only; links and special objects are not followed.") }
                let directory = type == .typeDirectory
                guard try ArchivePath.parse(path, directory: directory) == path, namespace[path] == nil else { throw ExplorerError.message("An archive member already exists: " + path) }
                namespace[path] = directory
                let fingerprint = try FileFingerprint(url)
                guard fingerprint.size <= UInt64(Int64.max) else { throw ExplorerError.message("Import file is too large.") }
                imports.append(ArchiveImport(path: path, source: url, directory: directory, fingerprint: fingerprint, size: directory ? 0 : Int64(fingerprint.size)))
                if directory {
                    let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                    guard work.count + imports.count + children.count <= options.maximumEntries else { throw ExplorerError.message("Import exceeds the configured entry limit.") }
                    work += children.map { ($0, path + "/" + $0.lastPathComponent) }
                }
            }
        case .replace(let path, let source):
            guard try !require(path), (try FileManager.default.attributesOfItem(atPath: source.path))[.type] as? FileAttributeType == .typeRegular else { throw ExplorerError.message("Replace an ordinary archive file with an ordinary local file.") }
            let fingerprint = try FileFingerprint(source)
            guard fingerprint.size <= UInt64(Int64.max) else { throw ExplorerError.message("Replacement file is too large.") }
            removed.insert(path); imports = [ArchiveImport(path: path, source: source, directory: false, fingerprint: fingerprint, size: Int64(fingerprint.size))]
        }
        var output: [String: Bool] = [:], bytes: Int64 = 0
        func insert(_ path: String, directory: Bool, size: Int64) throws {
            guard output.updateValue(directory, forKey: path) == nil else { throw ExplorerError.message("Multiple members would have the same archive path: " + path) }
            let (sum, overflow) = bytes.addingReportingOverflow(size)
            guard !overflow, sum <= options.maximumBytes, output.count <= options.maximumEntries else { throw ExplorerError.message("Edited archive exceeds the configured limits.") }; bytes = sum
        }
        for member in catalog.members where !removed.contains(member.path) { try insert(mapping[member.path] ?? member.path, directory: member.isDirectory, size: member.size) }
        for item in imports { try insert(item.path, directory: item.directory, size: item.size) }
        _ = try Self.namespace(output); expectedPaths = Set(output.keys)
    }
    private static func namespace(_ members: [String: Bool]) throws -> [String: Bool] {
        var nodes = members, aliases: [String: String] = [:]
        for path in members.keys {
            var components = path.split(separator: "/"); components.removeLast()
            while !components.isEmpty {
                let parent = components.joined(separator: "/")
                guard nodes[parent] != false else { throw ExplorerError.message("An archive file is also used as a folder: " + parent) }
                nodes[parent] = true; components.removeLast()
            }
        }
        for path in nodes.keys {
            let key = path.precomposedStringWithCanonicalMapping.lowercased()
            guard aliases[key] == nil || aliases[key] == path else { throw ExplorerError.message("Ambiguous case or Unicode archive names cannot be edited safely.") }; aliases[key] = path
        }
        return nodes
    }
}
