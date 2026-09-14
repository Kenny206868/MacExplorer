import SwiftUI
import AppKit
import ExplorerCore

/// Weak keys keep closed tabs out of the editor cache. A session holds only
/// weak references to its owning tab/workspace and never to a native window.
@MainActor final class FilenameEditorRegistry {
    static let shared = FilenameEditorRegistry()
    private let editors = NSMapTable<BrowserTab, FilenameEditor>(keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
    func editor(for tab: BrowserTab) -> FilenameEditor {
        if let editor = editors.object(forKey: tab) { return editor }
        let editor = FilenameEditor(); editors.setObject(editor, forKey: tab); return editor
    }
}
@MainActor final class FilenameEditor: ObservableObject {
    @Published private(set) var session: FilenameEditSession?
    func begin(_ entry: FileEntry, in workspace: ExplorerWorkspace) throws {
        cancel(); session = try FilenameEditSession(entry: entry, workspace: workspace, coordinator: self)
    }
    func cancel() { session?.finished = true; session = nil }
    func finish(_ value: FilenameEditSession) { if session === value { value.finished = true; session = nil } }
}
@MainActor final class FilenameEditSession: ObservableObject, Identifiable {
    let id = UUID()
    let source: URL
    let initialSelection: NSRange
    @Published var draft: String { didSet { error = nil } }
    @Published private(set) var error: String?
    fileprivate var finished = false
    private let identity: FileFingerprint
    private let parentIdentity: FileFingerprint
    private let location: Location
    private weak var workspace: ExplorerWorkspace?
    private weak var tab: BrowserTab?
    private weak var coordinator: FilenameEditor?
    init(entry: FileEntry, workspace: ExplorerWorkspace, coordinator: FilenameEditor) throws {
        source = entry.url; draft = entry.name
        identity = try FileFingerprint(entry.url); parentIdentity = try FileFingerprint(entry.url.deletingLastPathComponent())
        initialSelection = FilenameEditing.initialSelection(entry.name, isDirectory: entry.canBrowse)
        location = workspace.current.location; self.workspace = workspace; tab = workspace.current; self.coordinator = coordinator
    }
    func validatedName() throws -> String {
        guard !finished, let workspace, let tab, workspace.current === tab, tab.location == location,
              tab.entries.contains(where: { $0.url == source }), identity.matches(source),
              parentIdentity.matchesIdentity(source.deletingLastPathComponent()) else {
            throw ExplorerError.message("The file or its location changed. Cancel and start renaming again.")
        }
        try FileNames.validate(draft)
        let target = source.deletingLastPathComponent().appendingPathComponent(draft)
        if FileNames.exists(target), target.standardizedFileURL.path != source.standardizedFileURL.path {
            let caseOnly = source.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased() == draft.precomposedStringWithCanonicalMapping.lowercased()
            guard caseOnly, identity.matchesIdentity(target) else { throw ExplorerError.message("An item named \(draft) already exists.") }
        }
        return draft
    }
    @discardableResult func commit() -> Bool {
        guard !finished else { return true }
        do {
            let name = try validatedName()
            guard let workspace else { cancel(); return true }
            coordinator?.finish(self)
            if name != source.lastPathComponent { workspace.operations.rename([(source, name)], owner: workspace) }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func cancel() { coordinator?.finish(self); finished = true }
}
@MainActor extension ExplorerWorkspace {
    func requestRename() {
        let files = selected; guard !files.isEmpty else { return }
        if files.count > 1 { sheet = .rename; return }
        activatePane(files: true)
        do {
            guard let entry = files.first else { return }; current.focusedURL = entry.url
            try FilenameEditorRegistry.shared.editor(for: current).begin(entry, in: self)
        } catch { fail("Rename unavailable", error.localizedDescription) }
    }
}
struct FileNameLabel: View {
    let entry: FileEntry
    let tab: BrowserTab
    var lines: Int
    var centered: Bool
    @EnvironmentObject private var preferences: PreferenceStore
    @ObservedObject private var editor: FilenameEditor
    init(entry: FileEntry, tab: BrowserTab, lines: Int = 1, centered: Bool = false) {
        self.entry = entry; self.tab = tab; self.lines = lines; self.centered = centered
        _editor = ObservedObject(wrappedValue: FilenameEditorRegistry.shared.editor(for: tab))
    }
    var body: some View {
        // A stable container matters: Group distributes lifecycle modifiers to
        // its children and would cancel when the label changes into an editor.
        ZStack(alignment: centered ? .center : .leading) {
            if let session = editor.session, session.source == entry.url {
                InlineFilenameField(session: session, centered: centered).id(session.id).frame(minHeight: 24)
            } else {
                Text(displayName(entry, extensions: preferences.value.showExtensions)).lineLimit(lines).truncationMode(.middle)
                    .multilineTextAlignment(centered ? .center : .leading)
            }
        }.foregroundStyle(ExplorerDesign.text)
            .onDisappear { cancelIfCurrent() }
            .onChange(of: tab.location) { _, _ in cancelIfCurrent() }
    }
    private func cancelIfCurrent() { if editor.session?.source == entry.url { editor.cancel() } }
}
struct InlineFilenameField: NSViewRepresentable {
    @ObservedObject var session: FilenameEditSession
    var centered = false
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> FilenameTextField {
        let field = FilenameTextField()
        field.stringValue = session.draft; field.isEditable = true; field.isSelectable = true
        field.isBezeled = true; field.bezelStyle = .roundedBezel; field.focusRingType = .exterior
        field.font = .systemFont(ofSize: InputPreferences.shared.fileFontSize)
        field.alignment = centered ? .center : .left; field.delegate = context.coordinator
        field.initialSelection = session.initialSelection
        field.identifier = NSUserInterfaceItemIdentifier("explorer.inlineRename")
        field.setAccessibilityLabel("Rename " + session.source.lastPathComponent)
        return field
    }
    func updateNSView(_ field: FilenameTextField, context: Context) {
        context.coordinator.session = session
        if field.currentEditor() == nil && field.stringValue != session.draft { field.stringValue = session.draft }
        field.toolTip = session.error ?? "Return renames; Escape cancels."
        field.setAccessibilityHelp(session.error ?? "Edit the file name. Return renames and Escape cancels.")
        field.textColor = session.error == nil ? .labelColor : .systemRed
    }
    static func dismantleNSView(_ field: FilenameTextField, coordinator: Coordinator) { field.delegate = nil; coordinator.session.cancel() }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var session: FilenameEditSession
        init(session: FilenameEditSession) { self.session = session }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { session.draft = field.stringValue }
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, !session.finished else { return }
            session.draft = field.stringValue
            if !session.commit() { session.cancel() }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == NSSelectorFromString("cancelOperation:") { session.cancel(); control.window?.makeFirstResponder(nil); return true }
            if selector == NSSelectorFromString("insertNewline:") {
                session.draft = textView.string
                if session.commit() { control.window?.makeFirstResponder(nil) }; return true
            }
            return false
        }
    }
}
@MainActor final class FilenameTextField: NSTextField {
    var initialSelection = NSRange(location: 0, length: 0)
    private var focusedOnce = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); guard window != nil, !focusedOnce else { return }; focusedOnce = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            if let editor = self.currentEditor() as? NSTextView { editor.setSelectedRange(self.initialSelection) }
        }
    }
}
