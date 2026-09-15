import SwiftUI
import AppKit
import ExplorerCore

struct ArchiveEditPrompt: Identifiable {
    let id = UUID()
    let path: String?
    let folder: String
    var name: String
}

/// Only the containing archive has a filesystem URL. Virtual member paths never
/// enter native delete, move, preview or clipboard handlers as fabricated URLs.
@MainActor struct ArchiveLocationView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @StateObject private var model: ArchiveLocationModel
    @ObservedObject private var center = OperationCenter.shared
    @State private var selectingFiles = false
    @State private var namedMutation: ArchiveMutation?
    var folder: String
    init(workspace: ExplorerWorkspace, tab: BrowserTab, source: URL, folder: String, model: ArchiveLocationModel? = nil) {
        self.workspace = workspace; self.tab = tab; self.folder = folder
        _model = StateObject(wrappedValue: model ?? ArchiveLocationModel(source: source))
    }
    private var children: [ArchiveMember] { model.listing.entries }
    private var locked: Bool { model.busy || model.loading || model.filtering || selectingFiles }
    private var other: ExplorerWorkspace? { workspace.paneController?.other(than: workspace) }
    private var selection: [ArchiveMember] { model.selected }
    var body: some View {
        VStack(spacing: 0) {
            header
            ExplorerRule()
            breadcrumb
            actions
            ExplorerRule()
            contents
            if let notice = model.notice {
                ExplorerRule()
                HStack(alignment: .top) { Image(systemName: "info.circle"); Text(notice).textSelection(.enabled).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 0) }
                    .font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted).padding(12)
            }
            if model.encrypted || model.catalog == nil {
                HStack { SecureField("Archive password (memory only)", text: $model.password).textFieldStyle(.roundedBorder)
                    Button("Reload") { Task { await model.scan(force: true) } }.disabled(locked) }.padding(12)
            }
        }.background(ExplorerDesign.canvas).foregroundStyle(ExplorerDesign.text)
            .task(id: tab.archiveRevision) { model.show(folder: folder, query: tab.query); await model.scan(); updateStatus() }
            .onChange(of: model.selection) { _, _ in updateStatus() }
            .onChange(of: model.listingRevision) { _, _ in updateStatus() }
            .onChange(of: tab.query) { _, value in model.show(folder: folder, query: value) }
            .onChange(of: folder) { _, value in model.show(folder: value, query: tab.query) }
            .onDisappear { model.stop() }
            .sheet(item: $model.prompt, onDismiss: {
                guard let mutation = namedMutation else { return }; namedMutation = nil
                Task { await model.apply(mutation, center: center); updateStatus() }
            }) { prompt in ArchiveNameEditor(prompt: prompt) { mutation in namedMutation = mutation; model.prompt = nil } }
            .confirmationDialog("Save changes to this archive?", isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }), titleVisibility: .visible) {
                if let mutation = model.pending { Button("Save Archive") { model.pending = nil; Task { await model.apply(mutation, center: center); updateStatus() } } }
                Button("Cancel", role: .cancel) { model.pending = nil }
            } message: {
                Text("The archive is rebuilt and its original retained for Undo. ZIP/TAR member data and standard metadata are supported; vendor-specific fields and archive comments may not survive rewriting. Encrypted archives remain read-only.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .archiveRenameRequested)) { event in if event.object as? UUID == tab.id { rename() } }
            .dropDestination(for: URL.self) { urls, _ in
                guard !locked, model.editable, !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return false }
                model.pending = .importItems(sources: urls, into: folder); return true
            }
            .accessibilityIdentifier("explorer.archiveLocation")
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.zipper").font(.system(size: 22, weight: .light)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.source.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(model.catalog.map { "\($0.format) · \($0.members.count) entries" } ?? "Reading archive…").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted)
            }
            Spacer(minLength: 0)
            if model.loading || model.busy || model.filtering { ProgressView().controlSize(.small) }
            Label(model.editable ? "Editable" : "Read only", systemImage: model.editable ? "pencil" : "lock")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(ExplorerDesign.muted)
                .padding(.horizontal, 8).padding(.vertical, 5).background(ExplorerDesign.chrome, in: Capsule())
        }.padding(14)
    }
    private var actions: some View {
        HStack(spacing: 10) {
            Menu {
                Button("New Folder…") { model.prompt = ArchiveEditPrompt(path: nil, folder: folder, name: "New Folder") }
                Button("Add Files or Folders…") { chooseImport() }
                if let other { Button("Add Selection from Other Pane…") { model.pending = .importItems(sources: other.selectedURLs, into: folder) }.disabled(other.selectedURLs.isEmpty) }
            } label: { Label("Add", systemImage: "plus") }.disabled(locked || !model.editable)
            Button("Rename…") { rename() }.disabled(locked || !model.editable || selection.count != 1)
            Menu {
                Button("Replace Contents…") { chooseImport(replacing: selection.first?.path) }.disabled(selection.count != 1 || selection.first?.isDirectory == true)
                Button("Remove Selected…") { model.pending = .remove(paths: model.selection) }.disabled(selection.isEmpty)
            } label: { Image(systemName: "ellipsis.circle") }.disabled(locked || !model.editable).accessibilityLabel("Archive member actions")
            Spacer(minLength: 4)
            Menu {
                Button("Extract Selection…") { extract(all: false) }.disabled(selection.isEmpty)
                Button("Extract All…") { extract(all: true) }
                if let destination = other?.destination { Button("Extract Selection to Other Pane") { extract(all: false, to: destination) }.disabled(selection.isEmpty) }
            } label: { Label("Extract", systemImage: "square.and.arrow.down") }.disabled(locked || model.catalog == nil)
        }.font(.system(size: 11)).buttonStyle(.borderless).padding(.horizontal, 14).padding(.vertical, 9).background(ExplorerDesign.chrome)
    }
    private var contents: some View {
        Table(children, selection: $model.selection) {
            TableColumn("Name") { member in Label(member.name, systemImage: member.isDirectory ? "folder.fill" : "doc").help(member.unsupportedReason ?? member.path) }.width(min: 140, ideal: 260)
            TableColumn("Size") { member in Text(member.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: member.size, countStyle: .file)).monospacedDigit() }.width(min: 65, ideal: 80)
            TableColumn("Modified") { member in Text(member.modified.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—") }.width(min: 100, ideal: 120)
        }.alternatingRowBackgrounds(.disabled).scrollContentBackground(.hidden).background(ExplorerDesign.canvas)
            .contextMenu(forSelectionType: String.self) { selected in
                Button("Rename…") { model.selection = selected; rename() }.disabled(selected.count != 1 || locked || !model.editable)
                Button("Remove…") { model.pending = .remove(paths: selected) }.disabled(selected.isEmpty || locked || !model.editable)
                Button("Extract…") { model.selection = selected; extract(all: false) }.disabled(selected.isEmpty || locked)
            } primaryAction: { selected in
                if selected.count == 1, let member = children.first(where: { selected.contains($0.path) }), member.isDirectory { navigate(member.path) }
            }
            .onDeleteCommand { if !locked && model.editable && !selection.isEmpty { model.pending = .remove(paths: model.selection) } }
            .accessibilityLabel("Archive contents").accessibilityIdentifier("explorer.archiveContents")
    }
    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Button("Archive") { navigate("") }
                let parts = folder.split(separator: "/").map(String.init)
                ForEach(Array(parts.enumerated()), id: \.offset) { index, name in
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(ExplorerDesign.muted)
                    Button(name) { navigate(parts.prefix(index + 1).joined(separator: "/")) }
                }
            }.font(.system(size: 11)).buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 10)
        }.background(ExplorerDesign.canvas)
    }
    private func updateStatus() { tab.archiveItemCount = children.count; tab.archiveSelectionCount = model.selection.count }
    private func navigate(_ folder: String) { workspace.navigate(.archive(model.source, folder: folder)) }
    private func rename() {
        guard !locked, model.editable, selection.count == 1, let member = selection.first else { return }
        model.prompt = ArchiveEditPrompt(path: member.path, folder: folder, name: member.name)
    }
    private func chooseImport(replacing path: String? = nil) {
        guard !locked else { return }; selectingFiles = true
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = path == nil; panel.allowsMultipleSelection = path == nil
        panel.prompt = path == nil ? "Add to Archive" : "Replace Contents"
        let folder = folder
        panel.begin { response in
            selectingFiles = false
            guard response == .OK, let first = panel.urls.first else { return }
            model.pending = path.map { .replace(path: $0, source: first) } ?? .importItems(sources: panel.urls, into: folder)
        }
    }
    private func extract(all: Bool, to destination: URL? = nil) {
        guard !locked else { return }
        let paths = all ? nil : model.selection, source = model.source, password = model.password
        func submit(_ destination: URL) {
            workspace.operations.submit(FileJob(.extract, sources: [source], destination: destination, archiveOptions: ArchiveReadOptions(passphrase: password, selectedPaths: paths)), owner: workspace)
        }
        if let destination { submit(destination); return }
        selectingFiles = true
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Extract Here"
        panel.begin { response in selectingFiles = false; if response == .OK, let target = panel.url { submit(target) } }
    }
}
extension Notification.Name { static let archiveRenameRequested = Notification.Name("MacExplorer.archiveRename") }
private struct ArchiveNameEditor: View {
    let prompt: ArchiveEditPrompt
    let confirm: (ArchiveMutation) -> Void
    @State private var name: String
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(prompt: ArchiveEditPrompt, confirm: @escaping (ArchiveMutation) -> Void) { self.prompt = prompt; self.confirm = confirm; _name = State(initialValue: prompt.name) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt.path == nil ? "New Archive Folder" : "Rename Archive Member").font(.headline)
            Text("Rebuilds the archive and retains its original for Undo. Vendor-specific metadata and comments may not survive rewriting.").font(.caption).foregroundStyle(.secondary)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit(save)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save Archive", action: save).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 360)
    }
    private func save() {
        do {
            try FileNames.validate(name)
            let target = prompt.folder.isEmpty ? name : prompt.folder + "/" + name
            confirm(prompt.path.map { .rename(path: $0, to: target) } ?? .createDirectory(path: target))
        } catch { self.error = error.localizedDescription }
    }
}
