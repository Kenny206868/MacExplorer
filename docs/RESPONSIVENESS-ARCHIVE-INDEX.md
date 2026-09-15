# Archive browsing responsiveness

The archive view previously called `ArchiveCatalog.children(of:)` and filtered/sorted its results from computed properties during selection and layout updates. Its editable-state getter also traversed every member. These repeated passes are removed from the shipping view.

`ArchiveDirectoryIndex` builds immediate-child listings and path-position indexes once on a bounded archive read lane. It preserves explicit metadata and empty folders, synthesizes implicit ancestors, rejects file-as-parent conflicts and checks cancellation during indexing/sorting. Unfiltered folder navigation is a dictionary lookup. Sparse selection resolves only selected identities in presentation order. Editability/encryption are calculated during index installation, not while drawing controls.

An unchanged archive reuses its index after an asynchronous fingerprint check. Name filtering runs on the presentation executor and carries a generation token; old filters cannot overwrite a newer query. Mutating controls stay disabled while a filter is pending. Rendering and selection do not initiate archive enumeration or filesystem writes. Native file-operation and archive-write durability contracts are unchanged.

Tests cover a 50,000-member namespace, 2,000 repeated folder/selection lookups, implicit directories, ordering, cancellation, malformed parents and sparse/dense selections. The native model test exercises 1,000 selection changes and rapidly superseded filters against a real archive. Passing these algorithm/state tests is not a claim of a particular screen refresh rate or of physical-device input certification. Inspect the exact commit's macOS test artifacts for native results.
