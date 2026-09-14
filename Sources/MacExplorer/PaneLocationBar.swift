import SwiftUI
import AppKit
import ExplorerCore

/// Each pane's actual path remains visible, even when shared chrome follows the
/// other pane. Inline editing is a native text field with its own focus lifetime.
struct PaneLocationBar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject private var input = InputPreferences.shared
    @State private var editing = false
    @State private var address = ""
    @FocusState private var focused: Bool
    private var location: Location { workspace.current.location }
    private var displayPath: String {
        guard let url = location.directory else { return location.title }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path == home { return "~" }
        if url.path.hasPrefix(home + "/") { return "~" + url.path.dropFirst(home.count) }
        return url.path
    }
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(ExplorerDesign.muted)
            if editing {
                TextField("Pane folder path", text: $address).textFieldStyle(.plain).focused($focused)
                    .onSubmit { let value = address; editing = false; focused = false; workspace.goToAddress(value) }
                    .onExitCommand { editing = false; focused = false; workspace.focusFileSurface() }
                    .accessibilityLabel("Folder path for " + location.title)
            } else {
                Button(action: edit) {
                    Text(displayPath).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: input.touchFriendly ? 40 : 27).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Edit location: " + (location.directory?.path ?? location.title))
                    .accessibilityLabel("Edit pane location, " + displayPath)
            }
            Menu {
                Button("Edit Location", action: edit)
                if let url = location.directory {
                    Button("Copy Path") { NativeIntegration.copyPaths([url]) }
                    Button("Open in New Tab") { workspace.newTab(.folder(url)) }
                    Divider()
                    ForEach(parents, id: \.self) { parent in
                        Button(parent.path == "/" ? "Macintosh HD" : parent.lastPathComponent) { workspace.navigate(.folder(parent)) }
                    }
                }
            } label: { Image(systemName: "chevron.down").font(.system(size: 8)).frame(width: input.touchFriendly ? 40 : 22, height: input.touchFriendly ? 40 : 27) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("Pane location actions")
        }.font(.system(size: input.touchFriendly ? 11 : 10, design: .monospaced)).foregroundStyle(ExplorerDesign.muted)
            .padding(.horizontal, 12).frame(height: input.touchFriendly ? 44 : 30)
            .background(ExplorerDesign.canvas).overlay(alignment: .bottom) { ExplorerRule() }
            .onChange(of: focused) { _, value in if !value { editing = false } }
            .onChange(of: location) { _, _ in editing = false; focused = false }
            .onChange(of: workspace.activeID) { _, _ in editing = false; focused = false }
    }
    private var parents: [URL] {
        guard var value = location.directory else { return [] }
        var result: [URL] = []
        while value.path != "/" { value = value.deletingLastPathComponent(); result.append(value) }
        return result
    }
    private func edit() {
        workspace.activatePane(); workspace.fileSurfaceFocused = false
        address = location.directory?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        editing = true; focused = true
    }
}
