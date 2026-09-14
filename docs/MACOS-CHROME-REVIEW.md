# Native window chrome review

The alpha-77 content renders an imitation title area above an imitation command bar while `.hiddenTitleBar` obscures the real window identity. The new direction keeps Explorer's tabs, path navigation and Commander-style independent panes, but assigns window responsibilities to AppKit: standard traffic lights, native drag/double-click/fullscreen behavior, proxy location and a customizable unified toolbar. App-created controls remain SwiftUI inside toolbar items. No private view names, reparenting of traffic lights or fabricated window buttons are used.

The content has a compact tab strip and path row, not a second title bar. Dual panes retain their own tab strips and path editors. Native toolbar actions and overflow menu entries must use `WorkspaceCommandScope`, including modal guards in both panes. The status strip reports real item counts, selected file sizes, volume space, and operation state; an idle indicator is not presented as successful completion of unperformed work.

Verification must include a complete titled native window, not just a borderless content screenshot: system buttons, represented URL, toolbar customization/overflow and content geometry must be inspected together. Existing standalone content captures remain useful for every view mode, sheet and panel.

Primary API references: Apple AppKit `NSWindow.toolbarStyle`, `NSWindow.representedURL`, `NSToolbar`, and `NSTitlebarAccessoryViewController`. AppKit owns behavior and layout rather than a simulated web title bar.
