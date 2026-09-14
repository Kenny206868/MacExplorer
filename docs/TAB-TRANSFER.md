# Tab transfer and detachment

Single- and dual-pane headers use the same SwiftUI tab component and in-process transfer protocol. Tabs can be reordered, dragged between the two panes, or dragged into another MacExplorer window. The native source exports only a random single-use ticket; it does not publish filesystem URLs for a tab. The destination transfers the actual BrowserTab instance so history, selection, view state and active work are retained.

A mouse release outside application windows may request a new detached SwiftUI window. The source is retained until the destination window acknowledges that it has appeared. Then the live tab replaces the destination's temporary reconstructed tab. A failed or delayed window creation never closes the source. An emptied source pane receives Home; an otherwise empty single-pane source window closes only when no file operations are running.

Cancellation, unknown drag termination, and failed internal drops never request detachment. The public AppKit source callback is treated conservatively: automatic detachment requires an observable mouse-up release outside application windows. The explicit Move to New Window command uses the same acknowledged transaction on all devices. Headless tests cover one-shot tickets, live-object transfer, invalid tickets, cancellation, source retention and arrival acknowledgment; native WindowServer drag delivery still needs representative hardware evaluation.

Native bridge: Apple's public NSView.beginDraggingSession(with:event:source:) and NSDraggingSource callbacks. No private Finder APIs or global accessibility event taps are used.
