import Foundation

/// Deterministic pane allocation from the interactive design, independent of
/// NSSplitView's equal-priority expansion. Clamping never rewrites user intent.
public struct WorkspaceLayout: Sendable, Equatable {
    public let width: Double
    public let sidebarMinimum: Double = 168
    public let contentMinimum: Double = 350
    public let auxiliaryMinimum: Double = 220
    public var sidebarIdeal: Double { width < 1000 ? 184 : 211 }
    public let combinesAuxiliaryPanes: Bool
    public let auxiliaryCount: Int
    public var compactToolbar: Bool { width < 1050 }
    public var searchWidth: Double { max(160, min(255, width * 0.23)) }
    public var requiredMinimum: Double { sidebarMinimum + contentMinimum + Double(auxiliaryCount) * auxiliaryMinimum + Double(auxiliaryCount + 1) }
    public init(width: Double, preview: Bool, inspector: Bool) {
        self.width = width.isFinite ? max(0, width) : 800
        combinesAuxiliaryPanes = preview && inspector && self.width < 1240
        auxiliaryCount = combinesAuxiliaryPanes ? 1 : (preview ? 1 : 0) + (inspector ? 1 : 0)
    }
    public struct Allocation: Sendable, Equatable {
        public let sidebar: Double
        public let auxiliary: Double
        public let preview: Double
        public let content: Double
    }
    public func allocate(sidebar: Double = 211, inspector: Double = 254, preview: Double = 300,
                         hasInspector: Bool, hasPreview: Bool) -> Allocation {
        func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
            min(maximum, max(minimum, value.isFinite ? value : minimum))
        }
        let dividers = Double(1 + auxiliaryCount)
        let reserve = Double(auxiliaryCount) * auxiliaryMinimum
        let side = clamp(sidebar, sidebarMinimum, max(sidebarMinimum, min(288, width - contentMinimum - reserve - dividers)))
        let capacity = max(0, width - side - contentMinimum - dividers)
        let auxiliary = hasInspector || combinesAuxiliaryPanes
            ? clamp(inspector, auxiliaryMinimum, max(auxiliaryMinimum, min(400, capacity - (hasPreview && !combinesAuxiliaryPanes ? auxiliaryMinimum : 0)))) : 0
        let previewWidth = hasPreview && !combinesAuxiliaryPanes
            ? clamp(preview, auxiliaryMinimum, max(auxiliaryMinimum, min(520, capacity - auxiliary))) : 0
        return Allocation(sidebar: side, auxiliary: auxiliary, preview: previewWidth,
                          content: max(0, width - side - auxiliary - previewWidth - dividers))
    }
    /// Retained for native split hosts. Uses the same updated design budgets.
    public func initialPaneWidths(totalWidth: Double, dividerThickness: Double) -> [Double] {
        let totalWidth = totalWidth.isFinite ? max(requiredMinimum, totalWidth) : width
        let divider = dividerThickness.isFinite ? max(0, dividerThickness) : 1
        let usable = max(0, totalWidth - Double(auxiliaryCount + 1) * divider)
        let sidebar = min(sidebarIdeal, max(sidebarMinimum, usable - contentMinimum - Double(auxiliaryCount) * auxiliaryMinimum))
        var auxiliary = auxiliaryCount == 2 ? [300.0, 254.0] : auxiliaryCount == 1 ? [254.0] : []
        let deficit = max(0, sidebar + contentMinimum + auxiliary.reduce(0, +) - usable)
        let reducible = auxiliary.reduce(0) { $0 + max(0, $1 - auxiliaryMinimum) }
        if deficit > 0, reducible > 0 { auxiliary = auxiliary.map { max(auxiliaryMinimum, $0 - deficit * ($0 - auxiliaryMinimum) / reducible) } }
        return [sidebar, max(contentMinimum, usable - sidebar - auxiliary.reduce(0, +))] + auxiliary
    }
}
