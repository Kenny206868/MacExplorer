import SwiftUI
import AppKit
import ExplorerCore

struct ExplorerInspector: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @State private var metadata: [String: String] = [:]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Details").font(.system(size: 12, weight: .semibold)); Spacer()
                    Button { preferences.value.inspector = false } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).help("Close details")
                }
                if let entry = workspace.selected.first {
                    ZStack { RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.18)); FileThumbnail(entry: entry, size: 128).padding(24) }.frame(height: 185).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(workspace.selected.count > 1 ? "\(workspace.selected.count) items selected" : entry.name).font(.system(size: 16, weight: .semibold)).textSelection(.enabled)
                        Text(entry.kind + " · " + entry.sizeText).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack { Button("Quick Look") { workspace.quickLook() }.buttonStyle(.borderedProminent); ShareLink(items: workspace.selectedURLs) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.bordered) }
                    Divider()
                    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 13) {
                        ForEach(["Location", "Created", "Modified", "Size", "Cloud", "Permissions"], id: \.self) { key in
                            GridRow { Text(key).foregroundStyle(.secondary).frame(width: 65, alignment: .leading); Text(metadata[key] ?? "—").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                    }.font(.system(size: 11))
                    Divider()
                    Text("Tags").font(.system(size: 12, weight: .semibold))
                    FlowTags(tags: entry.tags)
                    Button { workspace.sheet = .tags } label: { Label("Edit tags", systemImage: "plus") }.font(.caption)
                    Divider()
                    Button("Show all properties…") { workspace.sheet = .properties }.font(.caption)
                } else {
                    ContentUnavailableView("Select a file", systemImage: "info.circle", description: Text("See file information, tags, and a Quick Look preview.")).padding(.top, 35)
                }
            }.padding(19)
        }
        .task(id: workspace.selected.first?.url) {
            guard let url = workspace.selected.first?.url else { metadata = [:]; return }
            do { let result = try await tab.service.inspect(url); if !Task.isCancelled { metadata = result } }
            catch { metadata = ["Location": error.localizedDescription] }
        }
    }
}

struct FlowTags: View {
    let tags: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 65), spacing: 5)], alignment: .leading, spacing: 5) {
            ForEach(tags, id: \.self) { tag in
                Label(tag, systemImage: "circle.fill").font(.system(size: 10)).labelStyle(TagLabelStyle()).padding(.horizontal, 7).padding(.vertical, 5).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}
private struct TagLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 4) { configuration.icon.font(.system(size: 6)).foregroundStyle(.tint); configuration.title.lineLimit(1) } }
}
