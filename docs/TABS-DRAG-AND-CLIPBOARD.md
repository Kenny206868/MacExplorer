# Native tab, selection and clipboard integration

## Tab lifecycle

The SwiftUI tab strip supports reordering and dragging a live tab between MacExplorer windows. A process-local item-provider ticket identifies the source; an old or foreign ticket cannot move an arbitrary tab. Moving the only tab to another window leaves a Home tab behind. The context menu exposes Duplicate, Move to New Window, Close, Close Other Tabs, Close Tabs to the Right and Reopen Closed Tab. A value-driven SwiftUI WindowGroup receives the detached session; no AppKit view controller replaces the app's SwiftUI shell.

Duplicate, reopen and detach preserve location history, view options, query, search scope and selected paths. The closed-tab stack is capped at 30 per workspace. It is an in-process stack, not persistent closed-window recovery. Ctrl+Tab/Ctrl+Shift+Tab cycle tabs, Command/Control+1…8 select a tab and 9 selects the last. Command+Shift+T or Control+Shift+T reopens a closed tab. The tab list menu makes overflowed tabs accessible.

## Selection and dragging

The existing ExplorerSelection and TypeAheadSearch core models remain the authority for ordered range/toggle/focus behavior. UI selection order follows displayed groups. Adaptive-grid column count drives vertical navigation. Focus has its own published URL and visual indicator. Plain Shift ranges replace the previous range; Control/Command+Shift uses a stable baseline so shrinking an additive range does not accumulate stale items.

This integration retains main's split FileCollection, FileGridView, FileItemViews and FileDragIntegration. Their deterministic grid geometry, grid checkboxes, native multi-file dragging, 750 ms spring-folder targets and package-context corrections are preserved, rather than installing a second gesture router. File drag icon preparation now reuses a fallback after eight items; the shared interaction modifier presents cut-item dimming consistently in details, grids and content rows. Offscreen marquee edge-autoscroll, file promises, and dragging a tab directly onto the desktop to detach it remain separate work; Move to New Window provides explicit detachment.

Backspace navigates Back outside text editing; forward Delete moves to Trash and Shift+Delete requests permanent deletion with confirmation. Command+Delete remains the native macOS trash shortcut. F3 focuses search and Alt+D focuses the address field. Text editing, attached sheets, alerts and deletion confirmations keep ownership of input; tab-switch shortcuts intentionally remain available from a text field.

## Clipboard and asynchronous completion

Cut tracking now has a generation-scoped reservation. Repeated Paste cannot queue the same reserved cut batch twice. Finishing a move reconciles only FileJobResult.completedSources; skipped, cancelled and failed sources remain cut. A completed parent removes its selected descendants from cut intent. A newer pasteboard generation is never overwritten. The clipboard publishes changes for dimmed cut items across views.

File-operation results target the captured originating tab/location, not whichever tab became active while the operation ran. Selection waits for the refreshed directory snapshot. An empty result preserves existing selection instead of clearing cut items after cancellation. Late progress callbacks cannot turn a finished row back into Running. A closed origin window cancels collision resolution rather than holding the global queue behind an invisible prompt.

The workspace forwards active-tab observation to focused SwiftUI commands so command availability follows current selection. Retry receipts preserve the rename-batch marker, retaining two-phase Undo/Redo behavior after an interrupted recovery attempt. The existing operation completion callback API remains available.

## Integration status

The concurrent commits 03cd945 and 02cb402 are retained in the ancestry and integrated with these changes. System libarchive and rename-cycle recovery fixes remain intact. Source syntax parsing is not a macOS compile, UI automation, signed release, or parity certification. CI and release artifacts provide those separate outcomes.
