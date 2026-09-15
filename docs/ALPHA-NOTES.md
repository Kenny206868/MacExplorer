# Native power-user workspace and responsiveness

This revision brings editable archive locations, full-path navigation and native Terminal actions into the real SwiftUI app. The macOS window uses standard controls and a customizable titlebar toolbar. Independent Commander panes retain separate tab groups, paths, histories, selection and view state; shared file actions target the active pane. Status-bar activity and volume information are nonmodal.

## Direct paths and Terminal

Click either pane's full path, or use Command/Control-L, F4 or Command-Shift-G. The native field selects the Unicode path, supports IME composition, asynchronous bounded folder suggestions, Tab completion, Return navigation, Command-Return for a new tab and Escape cancellation. Stale results cannot navigate a different tab. File paths reveal their containing folder instead of launching the file. Terminal uses captured directory URLs, not shell interpolation: Command-Option-Return opens the active location and Command-Shift-Option-Return opens both. Native menus and command search also expose the other pane. Control-Option remains reserved for VoiceOver.

## Archives and recovery

Archive members are virtual paths, never invented local file URLs. Unencrypted ZIP and supported TAR variants offer rename, subtree removal, folder creation, import and explicit replacement. Reconstruction streams into private staging, then installs through the write-ahead journal; the original archive is retained for exact-byte Undo. Encrypted, link/special-object and unsupported formats remain read-only. Vendor-specific member fields and archive comments may not survive reconstruction; the UI discloses that boundary before editing.

The serialized filesystem engine records intent before mutations and checkpoints completed inverse receipts in SQLite WAL. Real subprocess exits exercise install and recovery boundaries. Interrupted native Trash/delete outcomes are never guessed; recovery and explicit Keep Current Files acknowledgement retain the audit record. Standalone metadata changes and arbitrary external-provider/export operations are not all journaled.

## Input and rendering

Pointer regions intersect actual bounds with drawing visibility, fixing neighboring rows and panes claiming the same click on modern AppKit. Selection occurs on mouse-down without waiting for a double-click timeout. Listing/presentation work runs on bounded executors; watcher events coalesce rather than continually restarting useful scans. Archive directories are indexed once, sparse selection uses indexed identities and obsolete filters are discarded. Details rows receive narrowly scoped selected/focused state rather than observing every workspace publication. Implicit archive namespace growth is capped.

The mandatory native gallery has **112 captures per platform**, covering complete macOS windows, dual panes, settings, input/editor states, virtual archives, recovery, commands and status activity. Native large-directory tests additionally record actual NSScrollView layout/display and NSEvent dispatch measurements for a 2,000-file fixture, with structural checks for lazy rows, localized rendering and no extra listing/sorting. See each exact build's logs and `large-directory-performance.json`; debug shared-runner timings are not physical input-to-photon measurements or an FPS certification.

Every published alpha is assembled only after its exact main commit passes native packaging and both UI jobs. Its universal app, source, original interactive design, galleries, checksums and provenance match. These are ad-hoc-signed development builds, not Apple-notarized releases. Production Developer ID, notarization and Sparkle keys are owner-managed; alphas do not alter the signed stable update feed. Physical touch/gesture delivery, cross-process provider behavior, desktop drag-out and a complete VoiceOver audit still require representative hardware evaluation.
