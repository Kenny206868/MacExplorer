import SwiftUI
import AppKit

/// Semantic tokens shared by the native workspace. Colors follow the system
/// appearance, contrast settings and user accent instead of a fixed RGB theme.
enum ExplorerDesign {
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor).opacity(0.6)
    static let radius: CGFloat = 8
    static let iconTarget: CGFloat = 32
    static let toolbarHeight: CGFloat = 48
    static let addressHeight: CGFloat = 54
    static let statusHeight: CGFloat = 30
}

struct ExplorerIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ExplorerIconLabel(configuration: configuration)
    }
    private struct ExplorerIconLabel: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.45))
                .background(configuration.isPressed ? Color.primary.opacity(0.12) : hovered && enabled ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .onHover { hovered = $0 }
        }
    }
}

struct CommandIcon: View {
    let title: String
    let symbol: String
    var disabled: Bool
    let action: () -> Void
    init(_ title: String, _ symbol: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.disabled = disabled; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .frame(width: ExplorerDesign.iconTarget, height: ExplorerDesign.iconTarget).contentShape(Rectangle())
        }.buttonStyle(ExplorerIconStyle()).disabled(disabled).help(title).accessibilityLabel(title)
    }
}

/// Debug-only geometry instrumentation makes actual SwiftUI layout observable
/// to headless tests without screen scraping or production view-tree traversal.
struct ExplorerLayoutRegions: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
extension View {
    @ViewBuilder func explorerRegion(_ name: String) -> some View {
        #if DEBUG
        self.background(GeometryReader { proxy in
            Color.clear.preference(key: ExplorerLayoutRegions.self, value: [name: proxy.frame(in: .named("Explorer.workspace"))])
        }).accessibilityIdentifier("explorer." + name)
        #else
        self.accessibilityIdentifier("explorer." + name)
        #endif
    }
}
