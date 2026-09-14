import Foundation

public enum PaneSide: String, Codable, CaseIterable, Sendable { case primary, secondary
    public var other: PaneSide { self == .primary ? .secondary : .primary }
}
public enum PaneOrientation: String, Codable, CaseIterable, Sendable { case sideBySide, stacked }

/// Pure layout policy. An automatic narrow fallback never changes saved intent.
public struct DualPaneLayout: Equatable, Sendable {
    public let orientation: PaneOrientation
    public let first: Double
    public let second: Double
    public let extent: Double
    public let divider: Double = 7
    public init(width: Double, height: Double, preferred: PaneOrientation, ratio: Double) {
        let width = width.isFinite ? max(0, width) : 0
        let height = height.isFinite ? max(0, height) : 0
        orientation = preferred == .stacked || width < 760 ? .stacked : .sideBySide
        let length = orientation == .stacked ? height : width
        extent = max(0, length - divider)
        let minimum = min(extent / 2, orientation == .stacked ? 160 : 320)
        let ratio = Self.normalizedRatio(ratio)
        first = min(extent - minimum, max(minimum, extent * ratio))
        second = extent - first
    }
    public static func normalizedRatio(_ value: Double) -> Double { value.isFinite ? min(0.8, max(0.2, value)) : 0.5 }
}

/// Serializable companion state is intentionally nonrecursive. A companion has
/// independent tabs, but cannot contain an unbounded tree of nested workspaces.
public struct PaneGeometry: Codable, Hashable, Sendable {
    public var orientation: PaneOrientation
    public var ratio: Double
    public var focused: PaneSide
    public init(orientation: PaneOrientation = .sideBySide, ratio: Double = 0.5, focused: PaneSide = .primary) {
        self.orientation = orientation; self.ratio = DualPaneLayout.normalizedRatio(ratio); self.focused = focused
    }
}
