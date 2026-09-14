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

struct FileCollection: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    var body: some View {
        if tab.options.view == .details && tab.options.group == .none { FileDetailsTable(workspace: workspace, tab: tab) }
        else if [.content, .list].contains(tab.options.view) {
            List(selection: $tab.selection) {
                ForEach(Array(tab.groups.enumerated()), id: \.offset) { _, group in
                    Section { ForEach(group.1) { entry in FileWideRow(entry: entry, workspace: workspace, tab: tab).tag(entry.url) } } header: { if !group.0.isEmpty { Text(group.0) } }
                }
            }.listStyle(.inset)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 15) {
                        ForEach(Array(tab.groups.enumerated()), id: \.offset) { _, group in
                            if !group.0.isEmpty { Text(group.0).font(.headline).padding(.top, 10) }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: gridWidth), spacing: 9)], alignment: .leading, spacing: 10) {
                                ForEach(group.1) { entry in FileTile(entry: entry, workspace: workspace, tab: tab).id(entry.url) }
                            }
                        }
                    }.padding(18)
                }.onChange(of: tab.selection) { _, selection in if let first = selection.first { proxy.scrollTo(first, anchor: .center) } }
            }
        }
    }
    private var gridWidth: CGFloat { switch tab.options.view { case .extraLarge: return 170; case .tiles, .small, .details: return 240; case .gallery: return 180; default: return 125 } }
}

struct FileDetailsTable: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @State private var sortOrder = [KeyPathComparator(\FileEntry.name)]
    @SceneStorage("MacExplorer.DetailColumns") private var customization: TableColumnCustomization<FileEntry>
    var body: some View {
        Table(tab.visibleEntries, selection: $tab.selection, sortOrder: $sortOrder, columnCustomization: $customization) {
            TableColumn("Name", value: \.name) { entry in
                HStack(spacing: 8) {
                    if preferences.value.checkboxes { Toggle("Select \(entry.name)", isOn: Binding(get: { tab.selection.contains(entry.url) }, set: { if $0 { tab.selection.insert(entry.url) } else { tab.selection.remove(entry.url) } })).labelsHidden().toggleStyle(.checkbox) }
                    FileThumbnail(entry: entry, size: 20)
                    Text(displayName(entry, extensions: preferences.value.showExtensions)).lineLimit(1)
                    if entry.isLocked { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.frame(minHeight: preferences.value.compact ? 22 : 29)
                    .onDrag { NSItemProvider(object: entry.url as NSURL) }
                    .onDrop(of: ["public.file-url"], isTargeted: nil) { entry.canBrowse && workspace.drop($0, to: entry.url, move: NSEvent.modifierFlags.contains(.shift)) }
            }.width(min: 180, ideal: 310).customizationID("name")
            TableColumn("Date modified", value: \.modified) { entry in Text(entry.modified.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }.width(min: 130, ideal: 150).customizationID("modified")
            TableColumn("Kind", value: \.kind) { entry in Text(entry.kind).foregroundStyle(.secondary) }.width(min: 100, ideal: 140).customizationID("kind")
            TableColumn("Size", value: \.size) { entry in Text(entry.sizeText).monospacedDigit().foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing) }.width(min: 65, ideal: 80).customizationID("size")
            TableColumn("Tags") { entry in Text(entry.tags.joined(separator: ", ")).foregroundStyle(.secondary) }.width(min: 90, ideal: 130).customizationID("tags")
            TableColumn("Availability") { entry in
                if entry.isCloud { Label(entry.isDownloaded ? "Downloaded" : "Online only", systemImage: entry.isDownloaded ? "checkmark.icloud" : "icloud.and.arrow.down").foregroundStyle(.secondary) }
                else { Text("Local").foregroundStyle(.tertiary) }
            }.width(min: 90, ideal: 125).customizationID("availability")
        }
        .font(.system(size: 12))
        .contextMenu(forSelectionType: URL.self) { urls in FileContextMenu(workspace: workspace, urls: Array(urls)) } primaryAction: { urls in tab.selection = urls; workspace.openSelection() }
        .onChange(of: sortOrder) { _, order in
            guard let first = order.first else { return }
            if first.keyPath == \FileEntry.name { tab.options.sort = .name }
            else if first.keyPath == \FileEntry.modified { tab.options.sort = .modified }
            else if first.keyPath == \FileEntry.kind { tab.options.sort = .kind }
            else if first.keyPath == \FileEntry.size { tab.options.sort = .size }
            tab.options.descending = first.order == .reverse
        }
    }
}

private func displayName(_ entry: FileEntry, extensions: Bool) -> String { extensions || entry.canBrowse || entry.url.pathExtension.isEmpty ? entry.name : entry.url.deletingPathExtension().lastPathComponent }

struct FileTile: View {
    let entry: FileEntry
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    private var selected: Bool { tab.selection.contains(entry.url) }
    private var horizontal: Bool { [.tiles, .small, .details].contains(tab.options.view) }
    var body: some View {
        Group {
            if horizontal {
                HStack(spacing: 12) { FileThumbnail(entry: entry, size: tab.options.view == .small ? 20 : 44); labels(alignment: .leading); Spacer(minLength: 0) }.padding(10).frame(height: tab.options.view == .small ? 36 : 80)
            } else {
                VStack(spacing: 12) { FileThumbnail(entry: entry, size: CGFloat(tab.options.view.iconSize)); labels(alignment: .center) }.padding(12).frame(maxWidth: .infinity).frame(height: CGFloat(tab.options.view.iconSize) + 63)
            }
        }
        .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor.opacity(0.3) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { workspace.open(entry) }
        .onTapGesture {
            workspace.select(entry.url, extend: NSEvent.modifierFlags.intersection([.command, .control]).isEmpty == false, range: NSEvent.modifierFlags.contains(.shift))
            if preferences.value.singleClickOpen { workspace.open(entry) }
        }
        .contextMenu { FileContextMenu(workspace: workspace, urls: selected ? workspace.selectedURLs : [entry.url]) }
        .onDrag { if !selected { tab.selection = [entry.url] }; return NSItemProvider(object: entry.url as NSURL) }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { entry.canBrowse && workspace.drop($0, to: entry.url, move: NSEvent.modifierFlags.contains(.shift)) }
        .accessibilityElement(children: .combine).accessibilityLabel(entry.name + ", " + entry.kind).accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { workspace.open(entry) }
        .help(entry.url.path)
    }
    private func labels(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(displayName(entry, extensions: preferences.value.showExtensions)).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(horizontal ? .leading : .center)
            if tab.options.view == .tiles { Text(entry.kind).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1); Text(entry.sizeText).font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
    }
}

struct FileWideRow: View {
    let entry: FileEntry
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    var body: some View {
        HStack(spacing: 11) {
            FileThumbnail(entry: entry, size: tab.options.view == .content ? 42 : 23)
            VStack(alignment: .leading, spacing: 4) { Text(displayName(entry, extensions: preferences.value.showExtensions)).font(.system(size: 12)).lineLimit(1); if tab.options.view == .content { Text(entry.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
            Spacer(minLength: 10)
            Text(entry.modified.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            Text(entry.sizeText).font(.caption).foregroundStyle(.secondary).frame(width: 65, alignment: .trailing)
        }.padding(.horizontal, 9).padding(.vertical, preferences.value.compact ? 4 : 8)
            .background(tab.selection.contains(entry.url) ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
            .onTapGesture(count: 2) { workspace.open(entry) }
            .onTapGesture { workspace.select(entry.url, extend: !NSEvent.modifierFlags.intersection([.command, .control]).isEmpty, range: NSEvent.modifierFlags.contains(.shift)); if preferences.value.singleClickOpen { workspace.open(entry) } }
            .contextMenu { FileContextMenu(workspace: workspace, urls: tab.selection.contains(entry.url) ? workspace.selectedURLs : [entry.url]) }
            .onDrag { NSItemProvider(object: entry.url as NSURL) }
    }
}

struct FileContextMenu: View {
    @ObservedObject var workspace: ExplorerWorkspace
    let urls: [URL]
    private func perform(_ action: () -> Void) { workspace.current.selection = Set(urls); action() }
    var body: some View {
        if urls.isEmpty {
            Button("New Folder") { workspace.sheet = .newFolder }.disabled(workspace.destination == nil)
            Button("Paste") { workspace.paste() }.disabled(workspace.destination == nil)
            Button("Refresh") { workspace.current.refresh() }
        } else {
            Button("Open") { perform { workspace.openSelection() } }
            if urls.count == 1, let first = urls.first, (try? FileEntry(url: first).canBrowse) == true {
                Button("Open in New Tab") { workspace.newTab(.folder(first)) }
                Button("Show Package Contents") { workspace.navigate(.folder(first)) }
                Button("Pin to Quick Access") { workspace.preferences.pin(first) }
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
            Button("Rename…") { perform { workspace.sheet = .rename } }
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
            Divider()
            ShareLink(items: urls) { Text("Share / AirDrop…") }
            Button("Compress to ZIP") { perform { workspace.compress() } }
            Button("Extract Archive") { perform { workspace.extract() } }
            Button("Create Symbolic Link") { perform { workspace.alias() } }
            Button("Tags…") { perform { workspace.sheet = .tags } }
            Button("Download iCloud Items") { Task { do { try await workspace.current.service.requestDownload(urls); workspace.current.refresh() } catch { workspace.fail("Download failed", error.localizedDescription) } } }
            Button("Remove iCloud Download") { Task { do { try await workspace.current.service.evict(urls); workspace.current.refresh() } catch { workspace.fail("Could not remove download", error.localizedDescription) } } }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            Button("Properties…") { perform { workspace.sheet = .properties } }
        }
    }
}
