import SwiftUI
import AppKit
import ExplorerCore

struct ExplorerContent: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    var body: some View {
        Group {
            if tab.query.isEmpty && tab.location == .home { HomeView(workspace: workspace, tab: tab) }
            else if tab.query.isEmpty && tab.location == .computer { ComputerView(workspace: workspace) }
            else if tab.query.isEmpty && tab.location == .network { NetworkView(workspace: workspace) }
            else if tab.entries.isEmpty && !tab.loading {
                ContentUnavailableView {
                    Label(tab.query.isEmpty ? "This folder is empty" : "No matching files", systemImage: tab.query.isEmpty ? "folder" : "magnifyingglass")
                } description: { Text(tab.query.isEmpty ? "Create a folder or paste items here." : "Try a different name or a broader scope. Content searches require Spotlight indexing.") } actions: {
                    if workspace.destination != nil { Button("New Folder") { workspace.sheet = .newFolder } }
                    if !tab.query.isEmpty { Button("Clear Search") { tab.query = "" } }
                }
            } else { FileCollection(workspace: workspace, tab: tab) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HomeView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Home").font(.system(size: 27, weight: .semibold)).tracking(-0.6)
                    Text("Everything you need. Right where you expect it.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.bottom, 3)
                VStack(alignment: .leading, spacing: 14) {
                    Label("Quick access", systemImage: "star").font(.system(size: 13, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(preferences.value.pins) { bookmark in
                            Button { workspace.navigate(.folder(bookmark.url)) } label: {
                                HStack(spacing: 12) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: bookmark.url.path)).resizable().frame(width: 43, height: 43)
                                    VStack(alignment: .leading, spacing: 5) { Text(bookmark.url.lastPathComponent).font(.system(size: 12, weight: .medium)); Text(bookmark.url.deletingLastPathComponent().lastPathComponent).font(.system(size: 10)).foregroundStyle(.secondary) }
                                    Spacer(minLength: 0)
                                }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
                            }.buttonStyle(.plain).contextMenu { Button("Open in New Tab") { workspace.newTab(.folder(bookmark.url)) }; Button("Unpin") { preferences.unpin(bookmark.url) } }
                        }
                    }
                }
                HStack { Label("Recent", systemImage: "clock").font(.system(size: 13, weight: .semibold)); Spacer(); Text("Files opened with MacExplorer").font(.caption).foregroundStyle(.secondary) }
                if tab.entries.isEmpty {
                    VStack(spacing: 10) { Image(systemName: "clock").font(.system(size: 30)).foregroundStyle(.tertiary); Text("Your recent work will appear here").foregroundStyle(.secondary); Text("Open a document to add it to this list.").font(.caption).foregroundStyle(.tertiary) }.frame(maxWidth: .infinity).padding(35)
                } else {
                    LazyVStack(spacing: 0) { ForEach(tab.visibleEntries.prefix(40)) { entry in FileWideRow(entry: entry, workspace: workspace, tab: tab) } }
                }
            }.padding(27)
        }
    }
}

struct ComputerView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("This Mac").font(.system(size: 27, weight: .semibold)).tracking(-0.6)
                Text("Devices and drives").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                    ForEach(NativeIntegration.volumes(), id: \.self) { url in
                        Button { workspace.navigate(.folder(url)) } label: {
                            HStack(spacing: 16) { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 44, height: 44); VolumeCapacity(url: url).frame(maxWidth: .infinity, alignment: .leading) }.padding(20).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                        }.buttonStyle(.plain).contextMenu { Button("Open in New Tab") { workspace.newTab(.folder(url)) }; if url.path != "/" { Button("Eject") { NativeIntegration.eject(url, owner: workspace) } } }
                    }
                }
                Text("Folders").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                    ForEach(["Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies", "Applications"], id: \.self) { name in
                        let url = name == "Applications" ? URL(fileURLWithPath: "/Applications") : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
                        Button { workspace.navigate(.folder(url)) } label: { Label(name, systemImage: "folder.fill").frame(maxWidth: .infinity, alignment: .leading).padding(15).background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                    }
                }
            }.padding(27)
        }
    }
}
