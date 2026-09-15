# Input responsiveness contracts

## Cancelled filesystem work

`FileReadExecutor` uses a fixed-width `OperationQueue` lane and one cancellable operation per read. An operation owns the read closure until execution begins or cancellation wins. Cancellation clears queued captures before a blocked earlier read returns, so obsolete directory arrays are not retained merely because the UI already stopped awaiting them. Completion and cancellation share one lock-protected terminal state; continuation resumption and closure destruction occur outside the lock. Running kernel calls remain cooperatively cancellable; this is not a claim that an SMB filesystem call can be forcibly interrupted.

`ReadCancellationRetentionTests` holds the first worker inside a semaphore and asserts that a queued 1 MiB captured listing is destroyed before that semaphore is released. It also exercises 250 cancel/enqueue races. The retention regression fails with the former anonymous queued closure implementation and passes with the owning operation.

## Marquee selection

`ExplorerGridGeometry` returns compressed `IndexSet` ranges. Full-width selections are contiguous per group; partial-width selections produce row ranges. Direct point and identity hit testing use binary search over group geometry. Header gaps, cell gaps, partial rows, empty groups and nonfinite input are excluded. Compatibility array APIs remain available but the SwiftUI marquee path no longer calls them.

`MarqueeSelection` captures one unique-identity order, selection mode and baseline. A new hit set changes only the entering/leaving identities; an identical hit set returns nil. `FileMarqueeSession` publishes only a changed selection and invalidates synchronously after navigation, a data revision or a new navigation projection. Views also end gestures when their layout, grouping or density changes. No old drag may silently continue against a new row order.

The result is still a value-semantic Swift `Set`. Publishing a changed set can incur copy-on-write proportional to its size; this implementation does not claim constant-time materialization of arbitrary selections. Its explicit guarantees are compressed geometry, delta membership processing and no repeated selection projection/publication for unchanged hits. Physical frame latency requires profiling the rendered application, not inferring frames per second from unit tests.

Regression coverage compares 3,000 randomized rectangles with brute-force cell intersections, checks 4,500 input sequences against reference set algebra, represents a million-cell full-width hit with one range, and checks 10,000 unchanged hits over an 89,000-file selection. Native tests observe `BrowserTab.$selection` and reject refreshed/reordered drag sessions before a SwiftUI change observer runs.

## Paths and native command routing

Path typing performs lexical parsing only. Submitted-path validation and completion use independent fixed-width read lanes. Production completion is shallow and bounded by 4,096 examined entries, 512 cached folders, a 150 ms cooperative scan budget and 12 output suggestions. A single blocking filesystem call may exceed that budget; cancellation releases the waiting UI independently. Tests inject a monotonic clock and scan limits rather than weakening output assertions on busy CI machines.

Command-L/Control-L reuse and select the full draft. Native field-editor focus uses UTF-16 selection coordinates, preserves marked text and is not reset by every completion publication. Path and Terminal commands are shared by keyboard, menu and palette routes. File-context Terminal actions use the same validated explicit-URL pipeline.

## Validation boundary

The portable harness exercises the exact Foundation-only source files on Linux. MacExplorer's SwiftUI, AppKit integration and universal package must additionally pass macOS CI. Native test/screenshot success establishes those scripted contracts, not an exhaustive VoiceOver audit, hardware gesture evaluation, File Provider interoperability certification or production notarization. Those capabilities retain their existing documented release boundaries.
