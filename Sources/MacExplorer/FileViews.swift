import SwiftUI
import AppKit
import ExplorerCore

struct ExplorerContent: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var input = InputPreferences.shared
    var body: some View {
        VStack(spacing: 0) {
            content.background(PaneInputBridge(workspace: workspace))
            if input.touchFriendly && workspace.paneController == nil { TouchFileBar(workspace: workspace) }
        }
    }
    private var content: some View {
        Group {
            if case .archive(let source, let folder) = tab.location {
                ArchiveLocationView(workspace: workspace, tab: tab, source: source, folder: folder).id(source)
            } else if tab.query.isEmpty && tab.location == .home { HomeView(workspace: workspace, tab: tab) }
            else if tab.query.isEmpty && tab.location == .computer { ComputerView(workspace: workspace) }
            else if tab.query.isEmpty && tab.location == .network { NetworkView(workspace: workspace) }
            else if tab.entries.isEmpty && !tab.loading {
                ContentUnavailableView {
                    Label(tab.query.isEmpty ? "This folder is empty" : "No matching files", systemImage: tab.query.isEmpty ? "folder" : "magnifyingglass")
                } description: { Text(tab.query.isEmpty ? "Create a folder or paste items here." : "Try a different name or a broader scope. Content searches require Spotlight indexing.") } actions: {
                    if workspace.destination != nil { Button("New Folder") { workspace.sheet = .newFolder }.buttonStyle(ExplorerButtonStyle(primary: true)) }
                    if !tab.query.isEmpty { Button("Clear Search") { tab.query = "" }.buttonStyle(ExplorerButtonStyle()) }
                }
            } else { FileCollection(workspace: workspace, tab: tab) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ExplorerDesign.canvas)
    }
}
struct HomeView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @State private var showAllRecent = false
    @ObservedObject private var input = InputPreferences.shared
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Home").font(.system(size: 23, weight: .semibold)).tracking(-0.6)
                        Text("Everything you need. Right where you expect it.").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
                    }.padding(.bottom, 2)
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeading("Quick access", symbol: "star")
                        if preferences.value.pins.isEmpty {
                            Text("Pin folders from the sidebar or a folder's context menu.").font(.system(size: 12)).foregroundStyle(ExplorerDesign.muted).padding(.vertical, 12)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: geometry.size.width >= 660 ? 3 : geometry.size.width >= 420 ? 2 : 1), spacing: 11) {
                                ForEach(preferences.value.pins) { FolderShortcutCard(url: $0.url, workspace: workspace) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            sectionHeading("Recent", symbol: "clock")
                            Spacer()
                            if tab.entries.count > 12 {
                                Button(showAllRecent ? "Show less" : "View all") { showAllRecent.toggle() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Color.accentColor)
                            }
                        }
                        if tab.entries.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "clock").font(.system(size: 28)).foregroundStyle(ExplorerDesign.muted)
                                Text("Your recent work will appear here").font(.system(size: 12))
                                Text("Open a document to add it to this list.").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
                            }.frame(maxWidth: .infinity).padding(.vertical, 40)
                        } else {
                            FileDetailsTable(workspace: workspace, tab: tab, embedded: true)
                                .frame(height: 34 + CGFloat(showAllRecent ? min(tab.entries.count, 60) : min(tab.entries.count, 12)) * input.rowHeight(compact: preferences.value.compact))
                        }
                    }
                }.padding(26)
            }
        }.background(ExplorerDesign.canvas).accessibilityIdentifier("explorer.home")
    }
    private func sectionHeading(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) { Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(ExplorerDesign.muted); Text(title).font(.system(size: 13, weight: .semibold)) }
    }
}
struct ComputerView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @State private var volumes: [URL] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("This Mac").font(.system(size: 23, weight: .semibold)).tracking(-0.6)
                    Text("Your folders, devices, and connected storage.").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
                }
                Label("Devices and drives", systemImage: "internaldrive").font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                    ForEach(volumes, id: \.self) { url in
                        Button { workspace.navigate(.folder(url)) } label: {
                            HStack(spacing: 17) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().frame(width: 44, height: 44)
                                VolumeCapacity(url: url)
                            }.padding(19).frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
                        }.buttonStyle(ExplorerCardStyle()).contextMenu {
                            Button("Open in New Tab") { workspace.newTab(.folder(url)) }
                            if url.path != "/" { Button("Eject") { NativeIntegration.eject(url, owner: workspace) } }
                        }
                    }
                }
                Label("Folders", systemImage: "folder").font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 11)], spacing: 11) {
                    ForEach(["Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies", "Applications"], id: \.self) { name in
                        let url = name == "Applications" ? URL(fileURLWithPath: "/Applications") : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
                        FolderShortcutCard(url: url, workspace: workspace)
                    }
                }
            }.padding(26)
        }.background(ExplorerDesign.canvas).accessibilityIdentifier("explorer.computer")
            .task { volumes = NativeIntegration.volumes() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in volumes = NativeIntegration.volumes() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in volumes = NativeIntegration.volumes() }
    }
}
