import SwiftUI
import AppKit
import Combine
import ExplorerCore

/// A bounded, nonrecursive window snapshot. Old single-pane sessions decode
/// unchanged; the optional companion has its own independent tab collection.
struct WindowSession: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let saved: Date
    let tabs: [BrowserSession]
    let activeIndex: Int
    let closedTabs: [BrowserSession]
    let frame: CGRect?
    let companion: CompanionSession?
    init(id: UUID = UUID(), saved: Date = Date(), tabs: [BrowserSession], activeIndex: Int,
         closedTabs: [BrowserSession] = [], frame: CGRect? = nil, companion: CompanionSession? = nil) {
        self.id = id; self.saved = saved; self.tabs = Array(tabs.prefix(100)).map(Self.bounded)
        self.activeIndex = min(max(0, activeIndex), max(0, self.tabs.count - 1))
        self.closedTabs = Array(closedTabs.suffix(30)).map(Self.bounded); self.frame = frame
        self.companion = companion
    }
    static func bounded(_ tab: BrowserSession) -> BrowserSession {
        BrowserSession(id: tab.id, history: tab.history, options: tab.options,
            query: String(tab.query.prefix(8192)), allLocations: tab.allLocations, selection: Array(tab.selection.prefix(2048)))
    }
    private enum CodingKeys: String, CodingKey { case id, saved, tabs, activeIndex, closedTabs, frame, companion }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); saved = try c.decode(Date.self, forKey: .saved)
        tabs = try c.decode([BrowserSession].self, forKey: .tabs); activeIndex = try c.decode(Int.self, forKey: .activeIndex)
        closedTabs = try c.decodeIfPresent([BrowserSession].self, forKey: .closedTabs) ?? []
        frame = try c.decodeIfPresent(CGRect.self, forKey: .frame)
        companion = try c.decodeIfPresent(CompanionSession.self, forKey: .companion)?.validated()
        guard !tabs.isEmpty, tabs.count <= 100, tabs.indices.contains(activeIndex), closedTabs.count <= 30,
              (tabs + closedTabs).allSatisfy({ !$0.history.locations.isEmpty && $0.history.locations.count <= 128 && $0.history.locations.indices.contains($0.history.index) && $0.query.utf8.count <= 32_768 && $0.selection.count <= 2048 }),
              frame.map({ $0.origin.x.isFinite && $0.origin.y.isFinite && $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 }) ?? true else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid or oversized window session"))
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var title: String { tabs.indices.contains(activeIndex) ? tabs[activeIndex].history.current.title : "Window" }
    func newIdentity() -> WindowSession { WindowSession(tabs: tabs, activeIndex: activeIndex, closedTabs: closedTabs, frame: frame, companion: companion) }
}
struct SessionDocument: Codable, Sendable {
    var schemaVersion = 1
    var openWindows: [WindowSession] = []
    var closedWindows: [WindowSession] = []
}
final class SessionDiskStore: @unchecked Sendable {
    let url: URL
    private let queue = DispatchQueue(label: "MacExplorer.session-persistence", qos: .utility)
    init(url: URL) { self.url = url }
    func read() throws -> SessionDocument {
        guard FileNames.exists(url) else { return SessionDocument() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 8 * 1024 * 1024 else { throw ExplorerError.message("Saved sessions exceed the recovery size limit.") }
        let value = try JSONDecoder().decode(SessionDocument.self, from: Data(contentsOf: url))
        guard value.schemaVersion == 1, value.openWindows.count <= 30, value.closedWindows.count <= 12 else { throw ExplorerError.message("Unknown or oversized session format.") }
        return value
    }
    func write(_ value: SessionDocument, completion: @escaping @Sendable (String?) -> Void) {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
            guard data.count <= 8 * 1024 * 1024 else { throw ExplorerError.message("The session is too large to persist.") }
        } catch { completion(error.localizedDescription); return }
        queue.async { [url] in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path); completion(nil)
            } catch { completion(error.localizedDescription) }
        }
    }
    func flush() { queue.sync {} }
}
@MainActor final class WorkspaceSessionCoordinator: ObservableObject {
    static let shared = WorkspaceSessionCoordinator(storage: SessionDiskStore(url:
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacExplorer/Sessions/windows-v1.json")))
    @Published private(set) var closedWindows: [WindowSession]
    @Published private(set) var storageError: String?
    private struct Registration { weak var workspace: ExplorerWorkspace?; let subscription: AnyCancellable }
    private var live: [UUID: Registration] = [:]
    private var order: [UUID] = []
    private var restoration: [WindowSession]
    private var didClaimInitial = false
    private var didRequestAdditional = false
    private var quitting = false
    private let storage: SessionDiskStore
    private let hadStoredDocument: Bool
    init(storage: SessionDiskStore) {
        self.storage = storage; hadStoredDocument = FileNames.exists(storage.url)
        do { let saved = try storage.read(); restoration = saved.openWindows; closedWindows = saved.closedWindows }
        catch { restoration = []; closedWindows = []; storageError = error.localizedDescription }
    }
    enum InitialWindow { case restored(WindowSession), legacy, fresh }
    func claimInitialWindow(restore: Bool) -> InitialWindow {
        guard !didClaimInitial else { return .fresh }; didClaimInitial = true
        guard restore else { restoration = []; return .fresh }
        if !restoration.isEmpty { return .restored(restoration.removeFirst()) }
        return hadStoredDocument ? .fresh : .legacy
    }
    func restoreAdditionalWindows(using open: (WindowSession) -> Void) {
        guard didClaimInitial, !didRequestAdditional else { return }; didRequestAdditional = true
        let pending = restoration; restoration = []
        for session in pending { open(session.newIdentity()) }
    }
    func register(_ workspace: ExplorerWorkspace) {
        guard live[workspace.id] == nil, !quitting else { return }
        let subscription = workspace.objectWillChange.debounce(for: .milliseconds(450), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.persist() } }
        live[workspace.id] = Registration(workspace: workspace, subscription: subscription)
        order.append(workspace.id); persist()
    }
    func record(_ workspace: ExplorerWorkspace) { guard live[workspace.id] != nil, !quitting else { return }; persist() }
    func close(_ workspace: ExplorerWorkspace) {
        guard live[workspace.id] != nil else { return }
        if !quitting {
            closedWindows.insert(snapshot(workspace), at: 0); closedWindows = Array(closedWindows.prefix(12))
            live.removeValue(forKey: workspace.id); order.removeAll { $0 == workspace.id }; persist()
        }
    }
    func reopen(_ id: UUID? = nil) -> WindowSession? {
        let found: Int?
        if let id { found = closedWindows.firstIndex { $0.id == id } } else { found = closedWindows.isEmpty ? nil : 0 }
        guard let index = found else { return nil }
        let session = closedWindows.remove(at: index).newIdentity(); persist(); return session
    }
    func clearClosedWindows() { closedWindows = []; persist() }
    func prepareToQuit() { persist(); quitting = true; storage.flush() }
    func persist() {
        guard !quitting else { return }
        var value = SessionDocument()
        value.openWindows = Array((order.compactMap { live[$0]?.workspace }.map(snapshot) + restoration).prefix(30))
        value.closedWindows = Array(closedWindows.prefix(12))
        storage.write(value) { [weak self] error in Task { @MainActor in self?.storageError = error } }
    }
    func snapshot(_ workspace: ExplorerWorkspace) -> WindowSession {
        WindowSession(id: workspace.id, tabs: workspace.tabs.map { $0.session() },
            activeIndex: workspace.tabs.firstIndex { $0.id == workspace.activeID } ?? 0,
            closedTabs: workspace.closedTabs, frame: workspace.window?.frame, companion: workspace.dualPane?.snapshot())
    }
    func flushForTesting() { storage.flush() }
}
struct SessionHistoryView: View {
    @ObservedObject private var sessions = WorkspaceSessionCoordinator.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Window history").font(.title2.weight(.semibold))
                    Text("Restore tabs, searches, layouts and navigation together.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(); Button("Clear History") { sessions.clearClosedWindows() }.disabled(sessions.closedWindows.isEmpty)
            }.padding(24)
            Divider()
            if sessions.closedWindows.isEmpty {
                ContentUnavailableView("No closed windows", systemImage: "macwindow.on.rectangle", description: Text("Recently closed MacExplorer windows will appear here.")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sessions.closedWindows) { session in
                    HStack(spacing: 16) {
                        Image(systemName: session.companion == nil ? "macwindow" : "rectangle.split.2x1").font(.title2).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.title).fontWeight(.semibold).lineLimit(1)
                            Text("\(session.tabs.count + (session.companion?.tabs.count ?? 0)) tabs · " + session.saved.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            Text(session.tabs.map { $0.history.current.title }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(); Button("Restore Window") { if let value = sessions.reopen(session.id) { openWindow(id: "restored-session", value: value) } }
                    }.padding(.vertical, 10)
                }
            }
            if let error = sessions.storageError { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary).padding(16) }
        }.frame(minWidth: 600, minHeight: 400).background(ExplorerDesign.canvas)
    }
}
@MainActor extension NSWindow {
    func restoreExplorerFrame(_ saved: CGRect) {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(saved) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = CGSize(width: min(visible.width, max(800, saved.width)), height: min(visible.height, max(500, saved.height)))
        let frame = CGRect(x: min(max(visible.minX, saved.minX), visible.maxX - size.width),
                           y: min(max(visible.minY, saved.minY), visible.maxY - size.height), width: size.width, height: size.height)
        setFrame(frame, display: true)
    }
}
