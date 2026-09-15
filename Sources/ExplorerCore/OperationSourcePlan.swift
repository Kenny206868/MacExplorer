import Foundation

/// Build on the operation's read lane, not in FileJob.init or an input handler.
/// Resolve parents once per candidate; never follow the selected object's leaf
/// symlink. Lexicographic component ordering makes containment a linear sweep.
struct OperationSourcePlan {
    struct Candidate {
        let source: URL
        let components: [String]
        let directory: Bool
        let ordinal: Int
    }
    static func roots(_ sources: [URL], checkingCancellation: () throws -> Void) throws -> [URL] {
        var seen = Set<URL>(), candidates: [Candidate] = []
        candidates.reserveCapacity(sources.count)
        for (ordinal, source) in sources.enumerated() {
            try checkingCancellation()
            guard source.isFileURL else { throw ExplorerError.message("File operations require local or mounted filesystem URLs.") }
            let url = source.standardizedFileURL
            guard seen.insert(url).inserted else { continue }
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
            let canonical = url.path == "/" ? url : parent.appendingPathComponent(url.lastPathComponent)
            // A failed metadata read remains an independent input so normal
            // per-item engine errors can report it instead of hiding it.
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let directory = attributes?[.type] as? FileAttributeType == .typeDirectory
            candidates.append(Candidate(source: url, components: canonical.pathComponents, directory: directory, ordinal: ordinal))
        }
        var comparisons = 0
        candidates = try candidates.sorted { a, b in
            comparisons += 1
            if comparisons & 255 == 0 { try checkingCancellation() }
            return a.components == b.components ? a.ordinal < b.ordinal : a.components.lexicographicallyPrecedes(b.components)
        }
        var result: [Candidate] = [], ancestor: [String]?, previous: [String]?
        for candidate in candidates {
            try checkingCancellation()
            if previous == candidate.components { continue }
            previous = candidate.components
            if let ancestor, candidate.components.starts(with: ancestor) { continue }
            result.append(candidate)
            ancestor = candidate.directory ? candidate.components : nil
        }
        return result.sorted { $0.ordinal < $1.ordinal }.map(\.source)
    }
}

/// Pure component-prefix index for completed cut roots. No disk/pasteboard
/// access and no sources-times-completed-roots nested comparison loop.
public struct FilePathCoverage: Sendable {
    private struct Node: Sendable {
        var children: [String: Int] = [:]
        var coversDescendants = false
    }
    private var nodes: [Node] = [Node()]
    public init(roots: [URL]) {
        for url in roots where url.isFileURL {
            var node = 0
            for component in url.standardizedFileURL.pathComponents {
                if nodes[node].coversDescendants { break }
                if let next = nodes[node].children[component] { node = next }
                else {
                    let next = nodes.count
                    nodes.append(Node()); nodes[node].children[component] = next; node = next
                }
            }
            nodes[node].coversDescendants = true
        }
    }
    public func contains(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        var node = 0
        for component in url.standardizedFileURL.pathComponents {
            if nodes[node].coversDescendants { return true }
            guard let next = nodes[node].children[component] else { return false }; node = next
        }
        return nodes[node].coversDescendants
    }
}
