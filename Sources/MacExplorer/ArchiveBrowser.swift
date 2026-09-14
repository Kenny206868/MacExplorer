import SwiftUI
import AppKit
import ExplorerCore

@MainActor final class ArchiveBrowserModel: ObservableObject {
    let source: URL
    @Published var destination: String
    @Published var password = ""
    @Published var catalog: ArchiveCatalog?
    @Published var folder = ""
    @Published var query = ""
    @Published var selection: Set<String> = []
    @Published var loading = false
    @Published var extracting = false
    @Published var error: String?
    @Published var output: URL?
    private var scanTask: Task<Void, Never>?
    private var control = OperationControl()
    init(source: URL, destination: URL) { self.source = source; self.destination = destination.path }
    var children: [ArchiveMember] {
        (catalog?.children(of: folder) ?? []).filter { query.isEmpty || $0.name.localizedStandardContains(query) }
    }
    func scan() {
        control.cancel(); scanTask?.cancel(); control = OperationControl()
        let source = source, options = ArchiveReadOptions(passphrase: password), control = control
        loading = true; error = nil
        scanTask = Task {
            do {
                let value = try await Task.detached(priority: .userInitiated) { try ArchiveCatalog.read(source, options: options, control: control) }.value
                guard !Task.isCancelled else { return }
                catalog = value; loading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription; loading = false
            }
        }
    }
    func navigate(_ path: String) { folder = path; selection = []; query = "" }
    func stop() { control.cancel(); scanTask?.cancel(); scanTask = nil; password = "" }
    func extract(all: Bool, owner: ExplorerWorkspace) {
        guard !extracting else { return }
        let target = URL(fileURLWithPath: (destination as NSString).expandingTildeInPath, isDirectory: true)
        guard (try? FileEntry(url: target).canBrowse) == true else { error = "Choose an existing destination folder."; return }
        let options = ArchiveReadOptions(passphrase: password, selectedPaths: all ? nil : selection)
        extracting = true; error = nil; output = nil
        owner.operations.submit(FileJob(.extract, sources: [source], destination: target, archiveOptions: options), owner: owner) { [weak self] result in
            guard let self else { return }
            extracting = false
            if !result.errors.isEmpty { error = result.errors.joined(separator: "\n") }
            else if result.cancelled { error = "Extraction was cancelled. No partial folder was installed." }
            else { output = result.outputs.first; password = "" }
        }
    }
}

struct ArchiveBrowserSheet: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @StateObject private var model: ArchiveBrowserModel
    @Environment(\.dismiss) private var dismiss
    init(workspace: ExplorerWorkspace, source: URL) {
        self.workspace = workspace
        _model = StateObject(wrappedValue: ArchiveBrowserModel(source: source, destination: workspace.destination ?? source.deletingLastPathComponent()))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.zipper").font(.system(size: 30)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.source.lastPathComponent).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(model.catalog.map { "\($0.format) · \($0.members.count) entries · \(ByteCountFormatter.string(fromByteCount: $0.logicalBytes, countStyle: .file))" } ?? "Browse and extract archive contents")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if model.loading { ProgressView().controlSize(.small) }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            HStack(spacing: 10) {
                CommandIcon("Parent folder", "arrow.up", disabled: model.folder.isEmpty) {
                    model.navigate(model.folder.split(separator: "/").dropLast().joined(separator: "/"))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button("Archive") { model.navigate("") }.buttonStyle(.plain)
                        let components = model.folder.split(separator: "/").map(String.init)
                        ForEach(Array(components.enumerated()), id: \.offset) { index, name in
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            Button(name) { model.navigate(components.prefix(index + 1).joined(separator: "/")) }.buttonStyle(.plain)
                        }
                    }.font(.callout)
                }
                TextField("Filter this folder", text: $model.query).textFieldStyle(.roundedBorder).frame(width: 185)
            }.padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
            Divider()
            Table(model.children, selection: $model.selection) {
                TableColumn("Name") { member in
                    Label(member.name, systemImage: member.isDirectory ? "folder.fill" : "doc")
                        .foregroundStyle(member.unsupportedReason == nil ? Color.primary : Color.orange)
                        .help(member.unsupportedReason ?? member.path)
                }.width(min: 240, ideal: 350)
                TableColumn("Size") { member in
                    Text(member.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: member.size, countStyle: .file)).monospacedDigit()
                }.width(min: 70, ideal: 100)
                TableColumn("Modified") { member in
                    Text(member.modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                }.width(min: 140, ideal: 170)
                TableColumn("Protection") { member in
                    if member.encrypted { Label("Encrypted", systemImage: "lock").font(.caption) }
                }.width(min: 80, ideal: 100)
            }
            .contextMenu(forSelectionType: String.self) { selection in
                Button("Extract Selection") { model.selection = selection; model.extract(all: false, owner: workspace) }
                    .disabled(selection.isEmpty || model.extracting)
            } primaryAction: { selection in
                if selection.count == 1, let path = selection.first,
                   model.children.first(where: { $0.path == path })?.isDirectory == true { model.navigate(path) }
            }
            .overlay { if model.catalog == nil && !model.loading { ContentUnavailableView("Archive contents unavailable", systemImage: "doc.zipper", description: Text("Enter a password when required, then reload the archive.")) } }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Extract to").frame(width: 74, alignment: .leading)
                    TextField("Destination folder", text: $model.destination).textFieldStyle(.roundedBorder)
                    Button("Choose…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                        panel.directoryURL = URL(fileURLWithPath: model.destination, isDirectory: true)
                        panel.begin { response in if response == .OK, let url = panel.url { model.destination = url.path } }
                    }
                }
                HStack {
                    Text("Password").frame(width: 74, alignment: .leading)
                    SecureField("Optional for encrypted ZIP files", text: $model.password).textFieldStyle(.roundedBorder).onSubmit { model.scan() }
                    Button("Reload") { model.scan() }.disabled(model.loading || model.extracting)
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red).textSelection(.enabled).lineLimit(3)
                }
                if let output = model.output {
                    HStack {
                        Label("Extraction complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Open Folder") { workspace.newTab(.folder(output)); dismiss() }
                    }.font(.callout)
                }
                HStack {
                    Text(model.selection.isEmpty ? "Passwords are kept only in memory. Format support depends on macOS." : "\(model.selection.count) selected · folder selections include their contents")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 10)
                    if model.extracting {
                        ProgressView().controlSize(.small)
                        Button("Show Progress") { workspace.sheet = .operations }
                    } else {
                        Button("Extract Selected") { model.extract(all: false, owner: workspace) }.disabled(model.selection.isEmpty || model.loading)
                        Button("Extract All") { model.extract(all: true, owner: workspace) }.buttonStyle(.borderedProminent).disabled(model.loading)
                    }
                }
            }.padding(20)
        }.frame(width: 840, height: 650).background(ExplorerDesign.canvas)
            .onAppear { model.scan() }.onDisappear { model.stop() }
    }
}
