import SwiftUI
import AppKit

/// Native implementation of Design/index.html's semantic palette. Explicit
/// surfaces avoid NSVisualEffectView choosing unrelated gray/white backgrounds.
/// System accent, increased contrast and appearance remain user-controlled.
enum ExplorerDesign {
    static let canvas = adaptive("canvas", 0xFFFFFF, 0x202228)
    static let chrome = adaptive("chrome", 0xF7F7F9, 0x292B33)
    static let sidebar = adaptive("sidebar", 0xF3F4F7, 0x25272F)
    static let surface = chrome
    static let text = adaptive("text", 0x20232A, 0xF0F1F6)
    static let muted = adaptive("muted", 0x78808C, 0x9399A7)
    static let separator = adaptive("separator", 0xE5E7EB, 0x393C46)
    static let hover = adaptive("hover", 0xEAEDF2, 0x343845)
    static let selection = adaptive("selection", 0xE4F0FF, 0x153E6D)
    static let radius: CGFloat = 8
    static let iconTarget: CGFloat = 32
    static let titleHeight: CGFloat = 48
    static let toolbarHeight: CGFloat = 54
    static let addressHeight: CGFloat = 54
    static let statusHeight: CGFloat = 30
    static let sidebarWidth: CGFloat = 211
    static let inspectorWidth: CGFloat = 254
    static let rowHeight: CGFloat = 36

    private static func adaptive(_ name: String, _ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("MacExplorer." + name)) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let increased = appearance.name == .accessibilityHighContrastAqua || appearance.name == .accessibilityHighContrastDarkAqua
            if increased && name == "text" { return isDark ? .white : .black }
            if increased && name == "muted" { return isDark ? .lightGray : .darkGray }
            if increased && name == "separator" { return .gray }
            let value = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static func tagColor(_ tag: String) -> Color {
        switch tag.lowercased() {
        case "red": return .red
        case "orange", "design": return .orange
        case "yellow": return .yellow
        case "green", "personal": return .green
        case "blue": return .blue
        case "purple", "work": return .purple
        default: return .gray
        }
    }
}

struct ExplorerIconStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { LabelView(configuration: configuration, selected: selected) }
    private struct LabelView: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .foregroundStyle(enabled ? (selected ? Color.accentColor : ExplorerDesign.text) : ExplorerDesign.muted.opacity(0.45))
                .background(selected ? ExplorerDesign.selection : hovered && enabled || configuration.isPressed ? ExplorerDesign.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .onHover { hovered = $0 }
        }
    }
}
struct CommandIcon: View {
    let title: String
    let symbol: String
    var disabled: Bool
    var selected: Bool
    let action: () -> Void
    init(_ title: String, _ symbol: String, disabled: Bool = false, selected: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.disabled = disabled; self.selected = selected; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .regular))
                .frame(width: ExplorerDesign.iconTarget, height: ExplorerDesign.iconTarget).contentShape(Rectangle())
        }.buttonStyle(ExplorerIconStyle(selected: selected)).disabled(disabled).help(title).accessibilityLabel(title)
    }
}
struct ExplorerButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View { ButtonBody(configuration: configuration, primary: primary) }
    private struct ButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let primary: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(minHeight: 32)
                .foregroundStyle(primary ? Color.white : ExplorerDesign.text)
                .background(primary ? Color.accentColor : hovered ? ExplorerDesign.hover : ExplorerDesign.canvas, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary ? Color.clear : ExplorerDesign.separator, lineWidth: 1))
                .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.75 : 1).onHover { hovered = $0 }
        }
    }
}
struct ExplorerRule: View {
    var body: some View { Rectangle().fill(ExplorerDesign.separator).frame(height: 1).accessibilityHidden(true) }
}
struct ExplorerMenuLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14))
            Text(title).font(.system(size: 12))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium)).foregroundStyle(ExplorerDesign.muted)
        }.padding(.horizontal, 8).frame(height: 32).contentShape(Rectangle())
    }
}

/// Geometry is emitted by production components only in debug builds.
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
