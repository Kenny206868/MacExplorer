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
            }.padding(.leading, 18).padding(.trailing, 8).frame(height: 46)
            Divider()
            ScrollView {
                if let entry = selection.first {
                    VStack(alignment: .leading, spacing: 18) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(ExplorerDesign.surface.opacity(0.5))
                            FileThumbnail(entry: entry, size: 120).padding(22)
                            if selection.count > 1 {
                                Text("\(selection.count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                    .padding(8).background(.regularMaterial, in: Capsule()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(12)
                            }
                        }.frame(height: 166).overlay(RoundedRectangle(cornerRadius: 12).stroke(ExplorerDesign.separator, lineWidth: 0.5))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selection.count > 1 ? "\(selection.count) items selected" : entry.name)
                                .font(.system(size: 16, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Text(summary(entry)).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Button("Quick Look") { workspace.quickLook() }.buttonStyle(.borderedProminent)
                            ShareLink(items: selection.map(\.url)) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                        }.controlSize(.small)
                        Divider()
                        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 12) {
                            ForEach(fields(entry), id: \.0) { key, value in
                                GridRow {
                                    Text(key).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
                                    Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }.font(.system(size: 11))
                        if let error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary) }
                        Divider()
                        HStack { Text("Tags").font(.system(size: 12, weight: .semibold)); Spacer(); Button("Edit…") { workspace.sheet = .tags }.font(.caption) }
                        let tags = Array(Set(selection.flatMap(\.tags))).sorted()
                        if tags.isEmpty { Text("No tags").font(.caption).foregroundStyle(.tertiary) }
                        else { FlowTags(tags: tags) }
                        Button("Show all properties…") { workspace.sheet = .properties }.font(.caption).buttonStyle(.link)
                    }.padding(18)
                } else {
                    ContentUnavailableView("Select a file", systemImage: "info.circle", description: Text("File information and tags appear here.")).padding(.top, 30)
                }
            }
        }.background(ExplorerDesign.surface.opacity(0.16))
            .task(id: selectionKey) {
                metadata = [:]; metadataURL = nil; error = nil
                guard selection.count == 1, let url = selection.first?.url else { return }
                do {
                    let result = try await tab.service.inspect(url)
                    guard !Task.isCancelled else { return }
                    metadataURL = url; metadata = result
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
    }
    private func summary(_ entry: FileEntry) -> String {
        if selection.count == 1 { return entry.kind + " · " + entry.sizeText }
        let folders = selection.filter(\.isDirectory).count
        return "\(selection.count - folders) files · \(folders) folders"
    }
    private func fields(_ entry: FileEntry) -> [(String, String)] {
        let parents = Set(selection.map { $0.url.deletingLastPathComponent() })
        let bytes = selection.reduce(Int64(0)) { total, entry in
            let (value, overflow) = total.addingReportingOverflow(max(0, entry.size)); return overflow ? .max : value
        }
        var result: [(String, String)] = [
            ("Location", parents.count == 1 ? entry.url.deletingLastPathComponent().path : "Multiple locations"),
            ("Size", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + (selection.contains(where: \.isDirectory) ? " in selected files" : ""))
        ]
        if selection.count == 1 {
            result += [("Created", entry.created.formatted(date: .abbreviated, time: .shortened)),
                       ("Modified", entry.modified.formatted(date: .abbreviated, time: .shortened)),
                       ("Cloud", entry.isCloud ? (entry.isDownloaded ? "Downloaded" : "Online only") : "Local")]
            if metadataURL == entry.url, let permissions = metadata["Permissions"] { result.append(("Permissions", permissions)) }
            if entry.isLocked { result.append(("Locked", "Yes")) }
        }
        return result
    }
}

struct FlowTags: View {
    let tags: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 65), spacing: 5)], alignment: .leading, spacing: 5) {
            ForEach(tags, id: \.self) { tag in
                Label(tag, systemImage: "circle.fill").font(.system(size: 10)).labelStyle(TagLabelStyle())
                    .padding(.horizontal, 7).padding(.vertical, 5).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}
private struct TagLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.font(.system(size: 6)).foregroundStyle(.tint); configuration.title.lineLimit(1) }
    }
}
