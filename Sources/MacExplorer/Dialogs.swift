import SwiftUI
import AppKit
import ExplorerCore

struct ExplorerSheetView: View {
    let sheet: ExplorerSheet
    @ObservedObject var workspace: ExplorerWorkspace
    var body: some View {
        Group {
            switch sheet {
            case .newFolder, .newFile: NewItemSheet(workspace: workspace, folder: sheet == .newFolder)
            case .rename: RenameSheet(workspace: workspace)
            case .properties: PropertiesSheet(workspace: workspace)
            case .tags: TagsSheet(workspace: workspace)
            case .connect: ConnectSheet(workspace: workspace)
            case .operations: OperationsView(workspace: workspace)
            case .recovery: RecoveryView(workspace: workspace)
            }
        }.environmentObject(workspace.preferences)
    }
}

struct SheetHeading: View {
    let title: String
    let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 20, weight: .semibold)); Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading) }
}

struct NewItemSheet: View {
    @ObservedObject var workspace: ExplorerWorkspace
    let folder: Bool
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeading(title: folder ? "New folder" : "New text document", subtitle: workspace.destination?.path ?? "Choose a folder first.")
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).focused($focused).onSubmit(create)
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.caption) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Create", action: create).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(workspace.destination == nil) }
        }.padding(25).frame(width: 440).onAppear { name = folder ? "New folder" : "Untitled.txt"; focused = true }
    }
    private func create() {
        do {
            try FileNames.validate(name)
            guard let directory = workspace.destination else { return }
            let target = directory.appendingPathComponent(name)
            guard !FileNames.exists(target) else { throw ExplorerError.message("An item with that name already exists.") }
            workspace.operations.submit(FileJob(folder ? .createFolder : .createFile, destination: target), owner: workspace); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct RenameSheet: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var originals: [FileEntry] = []
    @State private var name = ""
    @State private var mode = "Replace text"
    @State private var find = ""
    @State private var replacement = ""
    @State private var format = "File {n}"
    @State private var start = 1
    @State private var padding = 3
    @State private var preserveExtension = true
    @State private var error: String?
    private var mapping: [(URL, String)] {
        originals.enumerated().map { index, entry in
            if originals.count == 1 { return (entry.url, name) }
            let base = preserveExtension && !entry.isDirectory ? entry.url.deletingPathExtension().lastPathComponent : entry.name
            let ext = preserveExtension && !entry.isDirectory && !entry.url.pathExtension.isEmpty ? "." + entry.url.pathExtension : ""
            let result: String
            switch mode {
            case "Replace text": result = find.isEmpty ? base : base.replacingOccurrences(of: find, with: replacement)
            case "Add prefix": result = replacement + base
            case "Add suffix": result = base + replacement
            default: result = format.replacingOccurrences(of: "{n}", with: String(format: "%0*d", padding, start + index)).replacingOccurrences(of: "{name}", with: base)
            }
            return (entry.url, result + ext)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeading(title: originals.count == 1 ? "Rename" : "Rename \(originals.count) items", subtitle: "Preview every name before applying. Existing files are never overwritten by a rename.")
            if originals.count == 1 { TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit(apply) }
            else {
                Picker("Mode", selection: $mode) { ForEach(["Replace text", "Add prefix", "Add suffix", "Name and number"], id: \.self) { Text($0) } }
                if mode == "Replace text" { TextField("Find", text: $find).textFieldStyle(.roundedBorder) }
                if mode == "Name and number" {
                    TextField("Template: {name} and {n}", text: $format).textFieldStyle(.roundedBorder)
                    HStack { Stepper("Start: \(start)", value: $start, in: 0...1_000_000); Stepper("Digits: \(padding)", value: $padding, in: 1...9) }
                } else { TextField(mode == "Replace text" ? "Replace with" : "Text to add", text: $replacement).textFieldStyle(.roundedBorder) }
                Toggle("Preserve file extensions", isOn: $preserveExtension)
            }
            if originals.count > 1 {
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        GridRow { Text("Original").fontWeight(.semibold); Text("New name").fontWeight(.semibold) }
                        ForEach(Array(mapping.enumerated()), id: \.offset) { _, pair in GridRow { Text(pair.0.lastPathComponent).foregroundStyle(.secondary); Text(pair.1) } }
                    }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.frame(height: 220).background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Rename", action: apply).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(originals.isEmpty) }
        }.padding(25).frame(width: originals.count > 1 ? 610 : 440)
            .onAppear { originals = workspace.selected.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }; name = originals.first?.name ?? "" }
    }
    private func apply() {
        do {
            let mapping = mapping.filter { $0.0.lastPathComponent != $0.1 }
            for pair in mapping { try FileNames.validate(pair.1) }
            if !mapping.isEmpty { workspace.operations.rename(mapping, owner: workspace) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct TagsSheet: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var append = false
    @State private var working = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeading(title: "Tags", subtitle: "Edit the macOS Finder tags on \(workspace.selected.count) selected item(s). Separate tags with commas.")
            TextField("Work, Personal, Red", text: $text).textFieldStyle(.roundedBorder)
            HStack { ForEach(["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"], id: \.self) { tag in Button(tag) { text = text.isEmpty ? tag : text + ", " + tag }.font(.caption) } }
            if workspace.selected.count > 1 { Toggle("Add to existing tags instead of replacing them", isOn: $append) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(working); Button(working ? "Saving…" : "Save", action: save).buttonStyle(.borderedProminent).disabled(working).keyboardShortcut(.defaultAction) }
        }.padding(25).frame(width: 510).onAppear { if workspace.selected.count == 1 { text = workspace.selected[0].tags.joined(separator: ", ") } }
    }
    private func save() {
        let tags = Array(Set(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        let selected = workspace.selected
        working = true
        Task {
            do {
                for entry in selected { try await workspace.current.service.setMetadata([entry.url], tags: append ? Array(Set(entry.tags + tags)).sorted() : tags, locked: nil, permissions: nil) }
                workspace.current.refresh(); dismiss()
            } catch { self.error = error.localizedDescription; working = false }
        }
    }
}

struct ConnectSheet: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @State private var address = "smb://"
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeading(title: "Connect to Server", subtitle: "Open a network share using macOS. Authentication is handled by the system; MacExplorer does not collect or store server passwords.")
            TextField("smb://server/share", text: $address).textFieldStyle(.roundedBorder).onSubmit(connect)
            Text("Supported address routes: SMB, AFP, NFS, and HTTPS WebDAV. Actual mounting depends on macOS and the server.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Connect", action: connect).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(25).frame(width: 490)
    }
    private func connect() { dismiss(); NativeIntegration.connect(address, owner: workspace) }
}

struct CollisionView: View {
    let prompt: ConflictPrompt
    @ObservedObject var workspace: ExplorerWorkspace
    @State private var all = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 15) { Image(systemName: "doc.on.doc").font(.system(size: 34)).foregroundStyle(.tint); SheetHeading(title: "An item with this name already exists", subtitle: prompt.collision.destination.lastPathComponent) }
            Grid(alignment: .topLeading, horizontalSpacing: 15, verticalSpacing: 12) {
                GridRow { Text("From").foregroundStyle(.secondary); Text(prompt.collision.source.path).textSelection(.enabled) }
                GridRow { Text("To").foregroundStyle(.secondary); Text(prompt.collision.destination.path).textSelection(.enabled) }
            }.font(.caption)
            Text("Keep Both creates a numbered copy. Replace retains the old item as a hidden recovery backup beside the destination. Replacing a folder replaces the whole folder; it does not merge its children.").font(.callout).foregroundStyle(.secondary)
            Toggle("Apply this decision to all remaining conflicts", isOn: $all)
            HStack { Button("Cancel Operation") { workspace.answerCollision(.cancel) }.keyboardShortcut(.cancelAction); Spacer(); Button("Skip") { workspace.answerCollision(.skip, all: all) }; Button("Replace") { workspace.answerCollision(.replace, all: all) }; Button("Keep Both") { workspace.answerCollision(.keepBoth, all: all) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width: 590)
    }
}
