import SwiftUI
import AppKit
import ExplorerCore

struct FileContextMenu: View {
    @ObservedObject var workspace: ExplorerWorkspace
    let urls: [URL]
    private func perform(_ action: () -> Void) { workspace.activatePane(); workspace.current.selection = Set(urls); action() }
    var body: some View {
        if urls.isEmpty {
            Button("New Folder") { workspace.sheet = .newFolder }.disabled(workspace.destination == nil)
            Button("Paste") { workspace.paste() }.disabled(workspace.destination == nil)
            Button("Refresh") { workspace.current.refresh() }
        } else {
            Button("Open") { perform { workspace.openSelection() } }
            if urls.count == 1, let first = urls.first, (try? FileEntry(url: first).canBrowse) == true {
                Button("Open in New Tab") { workspace.newTab(.folder(first)) }
                Button("Pin to Quick Access") { workspace.preferences.pin(first) }
            }
            if urls.count == 1, let first = urls.first, (try? first.resourceValues(forKeys: [.isPackageKey]).isPackage) == true {
                Button("Show Package Contents") { workspace.navigate(.folder(first)) }
            }
            if let first = urls.first {
                Menu("Open With") {
                    ForEach(NSWorkspace.shared.urlsForApplications(toOpen: first), id: \.self) { app in Button(app.deletingPathExtension().lastPathComponent) { NativeIntegration.openWith(urls, application: app, owner: workspace) } }
                }
            }
            Button("Quick Look") { perform { workspace.quickLook() } }
            Divider()
            Button("Cut") { perform { workspace.copy(cut: true) } }
            Button("Copy") { FileClipboard.shared.write(urls, cut: false) }
            Button("Copy as Path") { NativeIntegration.copyPaths(urls) }
            Button("Paste") { workspace.paste() }.disabled(workspace.destination == nil)
            Button("Rename") { perform { workspace.requestRename() } }
            Button("Duplicate") { perform { workspace.duplicate() } }
            Menu("Copy To") {
                ForEach(workspace.preferences.value.pins) { pin in Button(pin.url.lastPathComponent) { workspace.transfer(to: pin.url, move: false, urls: urls) } }
                Divider(); Button("Choose Folder…") { NativeIntegration.chooseFolder(owner: workspace) { workspace.transfer(to: $0, move: false, urls: urls) } }
            }
            Menu("Move To") {
                ForEach(workspace.preferences.value.pins) { pin in Button(pin.url.lastPathComponent) { workspace.transfer(to: pin.url, move: true, urls: urls) } }
                Divider(); Button("Choose Folder…") { NativeIntegration.chooseFolder(owner: workspace) { workspace.transfer(to: $0, move: true, urls: urls) } }
            }
            Button("Move to Trash") { perform { workspace.delete() } }
            Divider(); ShareLink(items: urls) { Text("Share / AirDrop…") }
            Button("Compress to ZIP") { perform { workspace.compress() } }
            Button("Browse / Extract Archive…") { perform { workspace.extract() } }
            Button("Create Symbolic Link") { perform { workspace.alias() } }
            Button("Tags…") { perform { workspace.sheet = .tags } }
            Button("Download iCloud Items") {
                let tab = workspace.current
                Task { do { try await tab.service.requestDownload(urls); tab.refresh() } catch { workspace.fail("Download failed", error.localizedDescription) } }
            }
            Button("Remove iCloud Download") {
                let tab = workspace.current
                Task { do { try await tab.service.evict(urls); tab.refresh() } catch { workspace.fail("Could not remove download", error.localizedDescription) } }
            }
            Divider(); Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            Button("Properties…") { perform { workspace.sheet = .properties } }
        }
    }
}
