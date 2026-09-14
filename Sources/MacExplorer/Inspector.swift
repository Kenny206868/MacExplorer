import SwiftUI
import AppKit
import ExplorerCore

struct ExplorerInspector: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @State private var metadata: [String: String] = [:]
    @State private var metadataURL: URL?
    @State private var error: String?
    private var selection: [FileEntry] { workspace.selected }
    private var selectionKey: [URL] { selection.map(\.url).sorted { $0.path < $1.path } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Details").font(.system(size: 12, weight: .semibold)); Spacer()
                CommandIcon("Close Details", "xmark") { preferences.value.inspector = false }
            }.padding(.leading, 20).padding(.trailing, 10).frame(height: 48)
            ExplorerRule()
            ScrollView {
                if let entry = selection.first { information(entry).padding(20) }
                else { emptyState.padding(20) }
            }
        }.foregroundStyle(ExplorerDesign.text).background(ExplorerDesign.canvas)
            .task(id: selectionKey) {
                metadata = [:]; metadataURL = nil; error = nil
                guard selection.count == 1, let url = selection.first?.url else { return }
                do {
                    let result = try await tab.service.inspect(url)
                    guard !Task.isCancelled else { return }; metadataURL = url; metadata = result
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
    }
    private func information(_ entry: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 9).fill(ExplorerDesign.chrome)
                FileArtwork(entry: entry, size: entry.isImage ? 168 : 104).frame(maxWidth: .infinity, maxHeight: .infinity)
                if selection.count > 1 { Text("\(selection.count) items").font(.system(size: 10, weight: .medium)).padding(7).background(ExplorerDesign.canvas, in: Capsule()).padding(10) }
            }.frame(height: 188).overlay(RoundedRectangle(cornerRadius: 9).stroke(ExplorerDesign.separator, lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                Text(selection.count > 1 ? "\(selection.count) items selected" : entry.name).font(.system(size: 15, weight: .semibold)).lineLimit(3).textSelection(.enabled)
                Text(summary(entry)).font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
            }
            HStack(spacing: 8) {
                Button("Quick Look") { workspace.quickLook() }.buttonStyle(ExplorerButtonStyle(primary: true))
                ShareLink(items: selection.map(\.url)) { Image(systemName: "square.and.arrow.up").frame(width: 13) }.buttonStyle(ExplorerButtonStyle()).help("Share selected items")
            }
            ExplorerRule()
            VStack(alignment: .leading, spacing: 13) {
                Text("INFORMATION").font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(ExplorerDesign.muted)
                ForEach(fields(entry), id: \.0) { key, value in
                    HStack(alignment: .top, spacing: 8) {
                        Text(key).foregroundStyle(ExplorerDesign.muted).frame(width: 72, alignment: .leading)
                        Text(value).lineLimit(key == "Where" ? 2 : 3).truncationMode(.middle).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.system(size: 11))
                }
            }.help(entry.url.deletingLastPathComponent().path)
            if let error { Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted) }
            ExplorerRule()
            HStack { Text("Tags").font(.system(size: 12, weight: .semibold)); Spacer(); Button("Edit…") { workspace.sheet = .tags }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Color.accentColor) }
            let tags = Array(Set(selection.flatMap(\.tags))).sorted()
            if tags.isEmpty { Text("No tags").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted) } else { FlowTags(tags: tags) }
            Button("Show all properties…") { workspace.sheet = .properties }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Color.accentColor).padding(.top, 2)
        }
    }
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 36, weight: .light)).foregroundStyle(ExplorerDesign.muted.opacity(0.55))
            Text("Select a file").font(.system(size: 14, weight: .semibold))
            Text("See a preview, file information, and tags without leaving your workspace.").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.top, 54)
    }
    private func summary(_ entry: FileEntry) -> String {
        if selection.count == 1 { return entry.kind + " · " + entry.sizeText }
        let folders = selection.filter(\.isDirectory).count
        return "\(selection.count - folders) files · \(folders) folders"
    }
    private func fields(_ entry: FileEntry) -> [(String, String)] {
        let parents = Set(selection.map { $0.url.deletingLastPathComponent() })
        let bytes = selection.filter { !$0.isDirectory }.reduce(Int64(0)) { total, entry in
            let (value, overflow) = total.addingReportingOverflow(max(0, entry.size)); return overflow ? .max : value
        }
        var result: [(String, String)] = [("Where", parents.count == 1 ? entry.url.deletingLastPathComponent().lastPathComponent : "Multiple locations"),
            ("Size", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + (selection.contains(where: \.isDirectory) ? " in selected files" : ""))]
        if selection.count == 1 {
            result += [("Created", entry.created.formatted(date: .abbreviated, time: .omitted)), ("Modified", entry.modified.formatted(date: .abbreviated, time: .omitted)),
                       ("Availability", entry.isCloud ? (entry.isDownloaded ? "Downloaded" : "Online only") : "On this Mac")]
            if metadataURL == entry.url, let permissions = metadata["Permissions"] { result.append(("Permissions", permissions)) }
            if entry.isLocked { result.append(("Locked", "Yes")) }
        }
        return result
    }
}
struct FlowTags: View {
    let tags: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 5) { Circle().fill(ExplorerDesign.tagColor(tag)).frame(width: 5, height: 5); Text(tag).lineLimit(1) }
                    .font(.system(size: 10)).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(ExplorerDesign.tagColor(tag).opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(ExplorerDesign.tagColor(tag).opacity(0.2), lineWidth: 0.5))
            }
        }
    }
}
