import Foundation

/// Responsive pane policy. User preferences describe intent; the layout never
/// rewrites them merely because a window becomes narrower.
public struct WorkspaceLayout: Sendable, Equatable {
    public let width: Double
    public let sidebarMinimum: Double
    public let sidebarIdeal: Double
    public let contentMinimum: Double
    public let auxiliaryMinimum: Double
    public let combinesAuxiliaryPanes: Bool
    public let auxiliaryCount: Int
    public var compactToolbar: Bool { width < 1050 }
    public var searchWidth: Double { max(160, min(260, width * 0.23)) }
    public var requiredMinimum: Double {
        sidebarMinimum + contentMinimum + Double(auxiliaryCount) * auxiliaryMinimum + Double(auxiliaryCount + 1)
    }
    public init(width: Double, preview: Bool, inspector: Bool) {
        self.width = width.isFinite ? max(0, width) : 800
        sidebarMinimum = 168
        sidebarIdeal = self.width < 1000 ? 184 : 208
        contentMinimum = 350
        auxiliaryMinimum = 240
        combinesAuxiliaryPanes = preview && inspector && self.width < 1240
        auxiliaryCount = combinesAuxiliaryPanes ? 1 : (preview ? 1 : 0) + (inspector ? 1 : 0)
    }
}

extension WorkspaceLayout {
    /// Native split-view initialization only; resizing remains under user control.
    public func initialPaneWidths(totalWidth: Double, dividerThickness: Double) -> [Double] {
        let totalWidth = totalWidth.isFinite ? max(requiredMinimum, totalWidth) : width
        let divider = dividerThickness.isFinite ? max(0, dividerThickness) : 1
        let usable = max(0, totalWidth - Double(auxiliaryCount + 1) * divider)
        let sidebar = min(sidebarIdeal, max(sidebarMinimum, usable - contentMinimum - Double(auxiliaryCount) * auxiliaryMinimum))
        var auxiliary = auxiliaryCount == 2 ? [310.0, 270.0] : auxiliaryCount == 1 ? [270.0] : []
        let deficit = max(0, sidebar + contentMinimum + auxiliary.reduce(0, +) - usable)
        let reducible = auxiliary.reduce(0) { $0 + max(0, $1 - auxiliaryMinimum) }
        if deficit > 0, reducible > 0 {
            auxiliary = auxiliary.map { max(auxiliaryMinimum, $0 - deficit * ($0 - auxiliaryMinimum) / reducible) }
        }
        let content = max(contentMinimum, usable - sidebar - auxiliary.reduce(0, +))
        return [sidebar, content] + auxiliary
    }
}
