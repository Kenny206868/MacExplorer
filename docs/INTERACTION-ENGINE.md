# Explorer interaction engine

## Selection contract

`ExplorerSelection` is a filesystem-independent state machine in ExplorerCore. Focus, range anchor, and selected items have distinct identities. Plain Shift replaces the range rather than retaining stale items when the range shrinks. Control/Command toggles individual items; Control/Command+Shift adds a range. Arrow navigation extends from the focused item, not from the first item in the selected set. Home/End select boundaries, and focus-only movement supports Control+Arrow.

`TypeAheadSearch` maintains a Unicode-aware, case/diacritic-insensitive prefix with a monotonic timeout. Repeated single characters cycle matching names. Later characters refine the prefix. It never receives text from an active text editor.

The domain contract has fixture-free tests. App integration is committed separately so changes to routing, grid geometry, native tables, and selection have an explicit review boundary. A compiled state machine alone is not a claim of complete interactive parity.
