import SwiftUI
import AppKit

/// SwiftUI split handle with pointer, keyboard and VoiceOver adjustment. Only
/// user drag intent is stored; responsive clamping never rewrites that intent.
struct PaneDivider: View {
    let title: String
    @Binding var value: Double
    let actual: Double
    var reversed = false
    @State private var origin: Double?
    @State private var hovered = false
    var body: some View {
        Rectangle().fill(ExplorerDesign.separator).frame(width: 1)
            .overlay {
                Rectangle().fill(hovered ? Color.accentColor.opacity(0.18) : .clear).frame(width: 7)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { gesture in
                            if origin == nil { origin = actual }
                            value = max(168, min(520, (origin ?? actual) + (reversed ? -1 : 1) * gesture.translation.width))
                        }.onEnded { _ in origin = nil })
                    .onHover { inside in
                        if inside != hovered { if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }; hovered = inside }
                    }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(title)
            .accessibilityValue("\(Int(actual)) points")
            .accessibilityAdjustableAction { direction in
                if direction == .increment { value = actual + 16 }
                else if direction == .decrement { value = max(168, actual - 16) }
            }
            .onDisappear { if hovered { NSCursor.pop(); hovered = false } }
    }
}
