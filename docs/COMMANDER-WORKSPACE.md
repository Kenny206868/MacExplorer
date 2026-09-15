# Commander workspace and responsive window chrome

The default remains a native Mac file manager. Commander features are individually optional rather than a destructive preset. Open **Power Tools** in the native toolbar or bottom status bar, or the **Commander** menu. **Enable Commander Workspace** opens the second pane and shows the command strip; it does not remap function keys, alter file associations, select files, or change existing row/view preferences.

## Native window, paths and panes

The title bar uses the taller unified macOS style so the active folder and pane subtitle have room. Standard window buttons, represented-folder behavior, accessibility, toolbar overflow and customization remain native. **Commander Settings → Compact native title bar** changes density live without replacing the toolbar or discarding its customization. Existing saved toolbar configurations are retained; Power Tools remains available in the footer/menu even when an older customized toolbar omits it.

Each pane retains independent tabs, history, view, search, selection and editable full path. Side-by-side/stacked arrangement, draggable/equal split, swapping locations and copying a location to the opposite pane remain in the Panes menu. The active pane is identified in native window chrome and with a narrow pane/status accent. Clicking a pane-local Terminal button activates that pane before launching; the button is an optional setting.

| Action | Keyboard route |
| --- | --- |
| Toggle dual panes | Shift–Command–D |
| Switch file panes | Tab / Shift–Tab, while the file surface owns focus |
| Edit the complete active path | Command–L / Control–L / Shift–Command–G |
| Complete / navigate / new tab | Tab / Return / Command–Return in the path editor |
| Cancel path editing | Escape |
| Terminal at active location | Option–Command–Return |
| Terminal at both pane locations | Shift–Option–Command–Return |
| Copy / confirmed move to opposite pane | Option–Command–C / Option–Command–M |
| Search all commands | Shift–Command–P / Shift–Control–P |

Path validation and completion are asynchronous. Relative/home paths, file URLs, Unicode/IME text and invalid drafts are handled by the existing native editor; obsolete results cannot navigate another tab. Terminal receives captured directory URLs, never shell-interpolated text. Archive members are virtual: Terminal uses the containing archive's real filesystem directory, not an invented member path. Both-pane launches deduplicate identical directories. Network discovery and Trash are not working directories.

## Optional commands

The command strip exposes View, Edit in TextEdit, Copy, Move, New Folder and Trash, plus selection and file-tool menus. The classic function-key profile is **off by default**, independently of whether the strip is visible. When enabled, F3/F4/F5/F6/F7/F8 invoke those six actions only with ordinary filesystem file-surface focus. Editors, IME composition, virtual archive tables, sheets and VoiceOver chords are not repurposed; repeated key-downs do not repeatedly issue these actions. macOS may require Fn to deliver physical function keys. With the option off, F3 Search, F4 Path, F5 Refresh and F6 focus cycling remain unchanged.

**Select by Pattern** matches basenames from the current visible listing, including already-produced search results, without new filesystem enumeration. Use `*.swift;*.cs | *.g.cs;Generated*` to include either extension and exclude generated files. `*` matches arbitrary text, `?` matches one Unicode grapheme, `;` combines masks and one `|` starts exclusions. `*.*` includes extensionless names. Matching defaults to case-insensitive canonical Unicode; case-sensitive matching and folders are explicit options. Replace, Add and Remove operate only after reviewing the count and up to 80 preview names. A changed listing invalidates the preview. Hidden/collapsed items are not silently added. Masks are bounded to 4,096 source characters, 256 per mask and 32 masks, with a non-backtracking matcher. These are not regular expressions or shell commands; reserved mask separators cannot match filenames containing those separators literally.

**Select Same Extension** compares the exact suffix, including the empty suffix, on the bounded presentation worker. It cancels on tab teardown and rejects results after selection/listing changes. Multi-rename, ZIP compression, archive browsing/extraction and read-only pane comparison reuse the existing real engines; this release does not claim Total Commander plugin, FTP client or integrated binary-editor parity.

## Footer and transfer behavior

The footer separates selection information from storage/activity and commands. Logical byte totals count selected regular files only; directory contents, resource forks and physical allocation are not recursively computed. Counts/sizes are cached per tab and invalidated for selection or listing changes, including equal-count replacement selections. A selection popover explains what is counted. Each pane can show available storage when space permits; the storage popover shows volume details. File Activity remains nonmodal so a user can inspect, pause or cancel operations without leaving the folder. With the command strip shown, the shared footer omits duplicate Copy/Move buttons.

Cross-pane preparation captures source URLs, pane/tab/location and selection before performing filesystem reads off the main actor. Fingerprints and destination checks run on a bounded metadata lane; the operation engine independently plans source roots on its bounded read lane. Input and navigation remain available, but a changed source selection, listing, pane, destination or dialog prevents an unconfirmed result from being submitted. Preparation has a visible Cancel action. Move still requires confirmation; its immutable snapshot is revalidated off the UI actor after confirmation, without retargeting a later location. Existing collision, serialized mutation, journal and recovery safeguards remain authoritative. No write is performed by the preparation worker.

The operation engine retains the concurrent `OperationSourcePlan` implementation: raw jobs capture intent without filesystem access; a bounded worker canonicalizes parents and uses a component-sorted containment sweep while preserving symlink objects and disjoint-source order. The compatible legacy `FileNames.independentRoots` helper is separately optimized with a component trie, resolving each candidate once instead of repeating all-pairs filesystem reads. Its prefix lookups are proportional to path depth. Filesystem resolution can still block inside an OS/provider call; cancellation releases the awaiting UI task and prevents late publication, but cannot forcibly interrupt a kernel call.

Storage readers share in-flight requests for identical folder/revision keys. Each observer can cancel independently; the last cancellation retires queued work. Results, including unavailable storage, are cached for ten seconds with a 32-key cap. Folder/listing or completed-operation changes request updated information. Two different folders on the same volume are intentionally not merged by a potentially blocking main-thread volume-resolution step.

## Validation and remaining boundaries

`FilenameSelectionMaskTests` covers Unicode, exclusions, limits, adversarial wildcards and saturating logical-byte totals. `PathPrefixIndexTests` includes 50,000 sibling paths, component boundaries and real symlink-root behavior. Native tests cover preference isolation/persistence, selection-summary cache invalidation, masked/extension selection, stale-result suppression, optional function keys, editor/modal/VoiceOver ownership, live title-bar changes and retained customization. Transfer tests block the real read lane while changing selection or cancelling; storage tests verify coalescing, cancellation and bounded caching.

Eight added native captures cover wide/narrow Commander windows, settings and selection masks in both appearances, bringing the required gallery to 120 per platform. Existing macOS 15 Intel/macOS 26 tests, crash probes, universal packaging and optimized scrolling diagnostics remain in CI. Portable harness checks and source parsing do not replace native builds or screenshot inspection; use the exact commit's CI status and artifacts for what actually passed.

This work does not certify physical input-to-photon latency, GPU completion or refresh-rate smoothness. Representative touch/gesture hardware, cross-process file-provider interactions, desktop drag-out and a complete VoiceOver audit still need evaluation. Apple signing/notarization and production Sparkle credentials remain owner-managed. Archive-format/metadata preservation limits and journal boundaries are documented separately; neither an app preview nor a successful UI test makes arbitrary filesystem/provider behavior universally safe.
