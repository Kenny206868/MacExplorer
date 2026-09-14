# Native command/comparison review

Review of the 98-view native matrix found a comparison-method caption wrapping into two lines. The caption now has its own non-wrapping layout budget and the segmented control has an accessible hidden label. Complete titled-window captures also exposed poor glyph contrast inside the nested SwiftUI toolbar material; the native toolbar integration now uses standard system symbol/menu items instead of that nested material.

The new real-event tests exercise NSWindow-delivered arrow and repeated-arrow input in the production palette search field. They also present the production sheet host, invoke a command, and require the next sheet to receive native text focus. Unlike model-only tests, the latter exposed a real lifecycle defect: onDismiss can run before AppKit releases the old sheet's key/modal boundary.

DeferredSheetAction now requires both SwiftUI dismissal and the actual AppKit boundary. Sheet-end/key-window notifications schedule one coalesced next-run-loop check; a changed owner, unrelated window or new modal cancels the action. A five-second deadline only discards abandoned requests and never executes them. This is not an animation-duration sleep. Observers and pending closures are removed on consumption, cancellation, replacement or window close. The unchanged actual-sheet test remains mandatory.

The combined mandatory screenshot contract is 98 captures on each macOS runner: original file/input/settings views, native inline editing, command palette states, real folder-comparison reports and complete titled windows. These checks and source changes are not a claim that an in-progress run has passed or that physical device/provider/accessibility evaluation is complete.
