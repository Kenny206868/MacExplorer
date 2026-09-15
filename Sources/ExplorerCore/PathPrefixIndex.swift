import Foundation

/// Path-component trie used during transfer-root normalization. Node indices
/// avoid recursive allocation/destruction and preserve component boundaries.
/// Each lookup walks a path once rather than comparing it with every source.
struct PathPrefixIndex: Sendable {
    private struct Node: Sendable { var children: [String: Int] = [:]; var terminal = false }
    private var nodes = [Node()]
    var nodeCount: Int { nodes.count }
    func containsAncestor(of components: [String]) -> Bool {
        var index = 0
        for component in components {
            if nodes[index].terminal { return true }
            guard let next = nodes[index].children[component] else { return false }
            index = next
        }
        return nodes[index].terminal
    }
    mutating func insert(_ components: [String]) {
        var index = 0
        for component in components {
            if nodes[index].terminal { return }
            if let next = nodes[index].children[component] { index = next }
            else {
                let next = nodes.count; nodes.append(Node())
                nodes[index].children[component] = next; index = next
            }
        }
        nodes[index].terminal = true
    }
}
