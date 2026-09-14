# File-surface input contract

Every native file presentation now shares `FileActivation` and `ExplorerWorkspace.activateFile`: Details, list, content, tiles, icons, and Gallery. Select mode adds/removes files without modifier keys. Single-click-open does not override Select mode. Long press in touch-friendly mode opens the owning pane's actions while preserving an existing multi-selection. A stale row cannot act on a file no longer in its pane's current presentation.

Touch-friendly density uses 44-point rows, column headers and shared command/button targets. Compact desktop rows remain 28 points and standard rows remain 36 points. Grid hit testing uses the same cell-height policy as rendering. Gallery preview controls expand with touch density, and the gesture preference also gates Gallery magnification.

A native drag prepares entries from the source pane before publishing file URLs/promises. Starting a drag from an inactive pane activates that source without taking the other pane's selection. Native drag completion never deletes sources based on a reported operation mask. Folder drop collision/undo/receipt contracts are unchanged.

`FileInputContractTests` exercises modifier-free selection across all modes, density persistence, inactive-pane drag preparation, long-press targeting and single-click-open suppression in Select mode. These are production command-path tests, not claims of physical touchscreen validation. Direct touch support depends on macOS/device drivers delivering supported pointer or AppKit events; trackpad gestures use native events.

API references: Apple AppKit event handling and local event monitors; SwiftUI accessibility actions. See https://developer.apple.com/documentation/appkit/event-handling and https://developer.apple.com/documentation/swiftui/accessible-controls .
