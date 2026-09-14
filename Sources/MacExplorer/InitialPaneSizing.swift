import SwiftUI
import AppKit
import ExplorerCore

/// SwiftUI's HSplitView retains native dividers and accessibility. A one-time
/// public NSSplitView adjustment gives its flexible panes useful initial widths
/// instead of letting auxiliary views consume their maximum preferred sizes.
struct InitialPaneSizing: NSViewRepresentable {
    let plan: WorkspaceLayout
    let preview: Bool
    let inspector: Bool
    func makeNSView(context: Context) -> InitialPaneSizingView {
        let view = InitialPaneSizingView(); updateNSView(view, context: context); return view
    }
    func updateNSView(_ view: InitialPaneSizingView, context: Context) {
        view.plan = plan
        view.configuration = "\(preview)|\(inspector)|\(plan.combinesAuxiliaryPanes)"
        view.requestLayout()
    }
}

@MainActor final class InitialPaneSizingView: NSView {
    var plan = WorkspaceLayout(width: 800, preview: false, inspector: false)
    var configuration = ""
    private weak var configuredSplit: NSSplitView?
    private var appliedConfiguration: String?
    private var scheduled = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); requestLayout() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); requestLayout() }
    override func layout() { super.layout(); requestLayout() }
    func requestLayout() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; scheduled = false
            applyIfNeeded()
        }
    }
    func applyIfNeeded() {
        var ancestor = superview
        while let candidate = ancestor, !(candidate is NSSplitView) { ancestor = candidate.superview }
        guard let split = ancestor as? NSSplitView, split.isVertical,
              split.bounds.width >= plan.requiredMinimum,
              split.arrangedSubviews.count == plan.auxiliaryCount + 2,
              configuredSplit !== split || appliedConfiguration != configuration else { return }
        // Record before layout callbacks so native constraint updates cannot
        // recursively reapply the initial positions or undo a later user drag.
        configuredSplit = split; appliedConfiguration = configuration
        let widths = plan.initialPaneWidths(totalWidth: split.bounds.width, dividerThickness: split.dividerThickness)
        var position: CGFloat = 0
        for index in 0..<(widths.count - 1) {
            position += widths[index]
            split.setPosition(position, ofDividerAt: index)
            position += split.dividerThickness
        }
        split.adjustSubviews()
    }
}
