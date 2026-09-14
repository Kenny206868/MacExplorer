# Native file promises

Outbound dragging publishes both a filesystem URL and an `NSFilePromiseProvider` in each selected item's pasteboard writer. The delegate is strongly retained through the provider's `userInfo`, so writing can finish after the drag UI or originating tab disappears. AppKit asks for the final basename on the main actor; actual copying runs on a supplied background operation queue.

The promise captures the source fingerprint at drag time. Fulfillment revalidates it, coordinates read/write access using the URLs supplied by `NSFileCoordinator`, copies with metadata into an exclusively created private staging directory, checks cancellation and source/parent identity, and installs without replacing an occupied destination. The source is never moved or deleted in response to an external drag result. External promises advertise Copy; same-application file-URL transfers retain Copy/Move/Link negotiation.

`FilePromiseExportTests` covers lazy export, content/metadata preservation, occupied destinations, changed sources, cancellation and recursive destinations. These filesystem tests do not substitute for receiver-specific application compatibility testing. Incoming promise reception is a separate integration contract, not implied by outbound support.

Primary API reference: https://developer.apple.com/documentation/appkit/supporting-table-view-drag-and-drop-through-file-promises
