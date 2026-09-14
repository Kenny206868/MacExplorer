# Native file promises

## Outbound

Outbound dragging publishes both a filesystem URL and an `NSFilePromiseProvider` in each selected item's pasteboard writer. The delegate is strongly retained through the provider's `userInfo`, so writing can finish after the drag UI or originating tab disappears. AppKit asks for the final basename on the main actor; actual copying runs on a shared background operation queue with a bounded concurrency of two.

The promise captures the source fingerprint at drag time. Fulfillment revalidates it, coordinates read/write access using the URLs supplied by `NSFileCoordinator`, copies with metadata into an exclusively created private staging directory, checks cancellation and source/parent identity, and installs without replacing an occupied destination. The source is never moved or deleted in response to an external drag result. External promises advertise Copy; same-application file-URL transfers retain Copy/Move/Link negotiation.

`FilePromiseExportTests` covers lazy export, content/metadata preservation, occupied destinations, changed sources, cancellation and recursive destinations. These filesystem tests do not substitute for receiver-specific application compatibility testing.

## Incoming

The SwiftUI file surface is hosted by a narrow AppKit drag-destination adapter. It recognizes `NSFilePromiseReceiver` before ordinary file URLs, while preserving internal URL drag/move handling. Drops target the folder under the pointer when available, otherwise the current folder. Every receiver for a drag writes to the same exclusively created private inbox, as required by AppKit. Only completed regular files/directories directly under the original inbox may enter the filesystem operation queue. Root symbolic links, special nodes, escaped paths and substituted inboxes are rejected. No imported content is automatically opened or executed.

The inbox retains receivers during asynchronous fulfillment, reports an operation row, supports cancellation, and captures the original destination identity and browser tab. Valid received files are installed using the normal serialized Copy engine, collision dialogs and Undo receipts. Changing tabs while a provider is still writing cannot redirect the drop or its final selection. A failed/skipped import retains the received originals with an explicit recovery path. Timed-out providers retain temporary data rather than deleting a directory that may still be in use; completed cleanup checks the inbox identity. macOS does not provide a cancellation method for an arbitrary source application's promise writer.

`FilePromiseIntegrationTests` performs a native AppKit pasteboard provider-to-receiver round trip. `PromisedImportFileTests` checks inbox boundaries, rejected links and external replacement. Both macOS CI variants run the complete native UI test target serially; core filesystem tests remain parallel in the build job. The CI outcome for each commit, not the presence of the tests, determines validation status.

Primary API references:
- https://developer.apple.com/documentation/appkit/supporting-table-view-drag-and-drop-through-file-promises
- https://developer.apple.com/documentation/appkit/nsfilepromisereceiver/receivepromisedfiles(atdestination:options:operationqueue:reader:)
