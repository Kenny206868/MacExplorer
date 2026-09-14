import SwiftUI
import AppKit
import ExplorerCore

struct FileCollection: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    var body: some View {
        if tab.options.view == .gallery { FileGalleryView(workspace: workspace, tab: tab) }
        else if tab.options.view == .details { FileDetailsTable(workspace: workspace, tab: tab) }
        else if [.content, .list].contains(tab.options.view) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tab.groups.enumerated()), id: \.offset) { _, group in
                            if !group.0.isEmpty {
                                HStack { Text(group.0).fontWeight(.semibold); Text("\(group.1.count)").foregroundStyle(ExplorerDesign.muted); Spacer() }
                                    .font(.system(size: 11)).padding(.horizontal, 14).frame(height: 34)
                            }
                            ForEach(group.1) { entry in FileWideRow(entry: entry, workspace: workspace, tab: tab).id(entry.url) }
                        }
                    }.padding(tab.options.view == .content ? 14 : 4)
                }.onChange(of: tab.focusedURL) { _, url in if let url { proxy.scrollTo(url) } }
            }
        } else { FileGridView(workspace: workspace, tab: tab) }
    }
}
