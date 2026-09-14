import SwiftUI
import AppKit
import ExplorerCore

struct PropertiesSheet: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var files: [FileEntry] = []
    @State private var values: [String: String] = [:]
    @State private var permissions = ""
    @State private var locked = false
    @State private var originalLocked = false
    @State private var originalPermissions = ""
    @State private var hash = ""
    @State private var calculation = ""
    @State private var error: String?
    @State private var working = false
    @State private var work: Task<Void, Never>?
    @State private var application: URL?
    @State private var permissionConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeading(title: files.count == 1 ? (files.first?.name ?? "Properties") : "Properties · \(files.count) items", subtitle: "Real filesystem metadata. Changes to permissions and lock state are not part of the file-operation undo stack.")
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    if let first = files.first {
                        HStack(spacing: 15) { FileThumbnail(entry: first, size: 55); VStack(alignment: .leading, spacing: 5) { Text(first.kind).font(.headline); Text(first.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
                    }
                    Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 12) {
                        ForEach(values.keys.sorted(), id: \.self) { key in GridRow { Text(key).foregroundStyle(.secondary).frame(width: 100, alignment: .leading); Text(values[key] ?? "—").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
                    }.font(.system(size: 12))
                    if files.count == 1, let entry = files.first {
                        Divider()
                        if entry.isDirectory {
                            Button(working ? "Calculating…" : "Calculate folder size on disk") { calculateSize(entry.url) }.disabled(working)
                            if !calculation.isEmpty { Text(calculation).font(.caption).textSelection(.enabled) }
                        } else {
                            HStack { Button(working ? "Calculating…" : "Calculate SHA-256") { checksum(entry.url) }.disabled(working); if !hash.isEmpty { Button("Copy checksum") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hash, forType: .string) } } }
                            if !hash.isEmpty { Text(hash).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                        }
                        Divider()
                        Toggle("Locked", isOn: $locked)
                        HStack { Text("POSIX permissions").foregroundStyle(.secondary); TextField("644", text: $permissions).textFieldStyle(.roundedBorder).frame(width: 80); Spacer(); Button("Apply Changes…") { permissionConfirmation = true }.disabled(working || (locked == originalLocked && permissions == originalPermissions)) }
                        Text("Permissions are applied only to the selected item, not recursively. ACL editing and ownership changes are intentionally not performed here.").font(.caption).foregroundStyle(.secondary)
                        if !entry.isDirectory {
                            Divider()
                            Picker("Open with", selection: $application) {
                                Text("Choose application").tag(nil as URL?)
                                ForEach(NSWorkspace.shared.urlsForApplications(toOpen: entry.url), id: \.self) { app in Text(app.deletingPathExtension().lastPathComponent).tag(Optional(app)) }
                            }
                            HStack {
                                Button("Open") { if let application { NativeIntegration.openWith([entry.url], application: application, owner: workspace) } }.disabled(application == nil)
                                Button("Use for This File Type…") { setDefault(entry.url) }.disabled(application == nil)
                            }
                        }
                    }
                    if let error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                }.padding(.trailing, 8)
            }.frame(maxHeight: 510)
            HStack { if working { ProgressView().controlSize(.small); Button("Cancel Calculation") { work?.cancel(); working = false } }; Spacer(); Button("Done") { work?.cancel(); dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(25).frame(width: 590)
            .task {
                files = workspace.selected
                if files.count == 1, let entry = files.first {
                    do {
                        values = try await workspace.current.service.inspect(entry.url)
                        permissions = values["Permissions"] ?? ""; originalPermissions = permissions; locked = entry.isLocked; originalLocked = locked
                        application = NSWorkspace.shared.urlForApplication(toOpen: entry.url)
                    } catch { self.error = error.localizedDescription }
                } else {
                    values = ["Items": String(files.count), "Files": String(files.filter { !$0.isDirectory }.count), "Folders": String(files.filter(\.isDirectory).count), "File sizes": ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.size }, countStyle: .file)]
                }
            }
            .onDisappear { work?.cancel() }
            .confirmationDialog("Apply file permission and lock changes?", isPresented: $permissionConfirmation, titleVisibility: .visible) { Button("Apply") { applyMetadata() }; Button("Cancel", role: .cancel) {} } message: { Text("Changing permissions can prevent access to the file. These changes are not undoable in MacExplorer.") }
    }
    private func calculateSize(_ url: URL) {
        working = true; error = nil
        work = Task { do { let (bytes, count) = try await workspace.current.service.allocatedSize(url); calculation = "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) allocated · \(count) entries" } catch is CancellationError {} catch { self.error = error.localizedDescription }; working = false }
    }
    private func checksum(_ url: URL) {
        working = true; error = nil
        work = Task { do { hash = try await workspace.current.service.checksum(url) } catch is CancellationError {} catch { self.error = error.localizedDescription }; working = false }
    }
    private func applyMetadata() {
        guard let url = files.first?.url, permissions.count == 3, permissions.allSatisfy({ "01234567".contains($0) }), let mode = Int(permissions, radix: 8) else { error = "Enter exactly three octal digits, such as 644 or 755."; return }
        working = true
        work = Task {
            do {
                // Unlock before chmod; apply the requested final lock state afterwards.
                if originalLocked { try await workspace.current.service.setMetadata([url], tags: nil, locked: false, permissions: nil) }
                do { try await workspace.current.service.setMetadata([url], tags: nil, locked: nil, permissions: mode) }
                catch { try? await workspace.current.service.setMetadata([url], tags: nil, locked: originalLocked, permissions: nil); throw error }
                try await workspace.current.service.setMetadata([url], tags: nil, locked: locked, permissions: nil)
                values = try await workspace.current.service.inspect(url); originalLocked = locked; originalPermissions = permissions; workspace.current.refresh()
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }
    private func setDefault(_ url: URL) {
        guard let application else { return }
        NSWorkspace.shared.setDefaultApplication(at: application, toOpenContentTypeOfFileAt: url) { failure in
            Task { @MainActor in if let failure { error = failure.localizedDescription } }
        }
    }
}
