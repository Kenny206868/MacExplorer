import AppKit
import ExplorerCore

/// Capture paths before asynchronous validation. Virtual archive members are
/// not directories; their containing archive's physical folder is usable.
struct TerminalRequest: Sendable, Equatable {
    enum Scope: Sendable { case active, other, both }
    let folders: [URL]
    init(folders: [URL]) throws {
        guard !folders.isEmpty, folders.count <= 2, folders.allSatisfy(\.isFileURL) else { throw ExplorerError.message("Choose one or two local or mounted folders.") }
        var seen = Set<String>()
        self.folders = folders.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
    }
    @MainActor static func directory(for workspace: ExplorerWorkspace) -> URL? {
        let location = workspace.current.location
        if let directory = location.directory { return directory }
        if let archive = location.archiveSource { return archive.deletingLastPathComponent() }
        if location == .home { return FileManager.default.homeDirectoryForCurrentUser }
        return nil
    }
    @MainActor static func capture(_ workspace: ExplorerWorkspace, scope: Scope) throws -> Self {
        let other = workspace.paneController?.other(than: workspace)
        let candidates: [URL?]
        switch scope {
        case .active: candidates = [directory(for: workspace)]
        case .other: candidates = [other.flatMap { directory(for: $0) }]
        case .both:
            guard let other else { throw ExplorerError.message("Enable dual panes to open both locations in Terminal.") }
            candidates = [directory(for: workspace), directory(for: other)]
        }
        guard candidates.allSatisfy({ $0 != nil }) else { throw ExplorerError.message("Open a filesystem folder in each requested pane. Network discovery, tags and Trash are not shell working directories.") }
        return try Self(folders: candidates.compactMap { $0 })
    }
}

@MainActor final class TerminalLauncher {
    static let shared = TerminalLauncher()
    typealias Launch = @MainActor ([URL]) async throws -> Void
    private let launch: Launch
    private let checks = FileReadExecutor(name: "terminal-navigation", concurrency: 2, quality: .userInitiated)
    private var pending = Set<[String]>()
    init(launch: Launch? = nil) { self.launch = launch ?? Self.launchSystemTerminal }
    func open(from workspace: ExplorerWorkspace, scope: TerminalRequest.Scope = .active) {
        do { open(try TerminalRequest.capture(workspace, scope: scope), owner: workspace) }
        catch { workspace.fail("Terminal unavailable", error.localizedDescription) }
    }
    func open(_ request: TerminalRequest, owner: ExplorerWorkspace) {
        let key = request.folders.map(\.path)
        guard pending.insert(key).inserted else { return }
        Task { [weak owner] in
            defer { pending.remove(key) }
            do { try await perform(request) }
            catch { owner?.fail("Could not open Terminal", error.localizedDescription) }
        }
    }
    func perform(_ request: TerminalRequest) async throws {
        try await checks.run { cancellation in
            for url in request.folders {
                try cancellation.check()
                guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw ExplorerError.message("The requested working directory is no longer a folder: " + url.path) }
            }
        }
        try Task.checkCancellation(); try await launch(request.folders)
    }
    private static func launchSystemTerminal(_ folders: [URL]) async throws {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { throw ExplorerError.message("Apple Terminal is not available on this Mac.") }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(folders, withApplicationAt: app, configuration: configuration) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
