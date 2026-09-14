# Native chrome and recovery continuation

The window remains a native titled AppKit window with a customizable symbol/menu toolbar, standard traffic lights and a represented folder URL. File tabs, independent Commander panes, path/search, inspector and status remain SwiftUI. A lifecycle actor-isolation defect in the new sheet handoff was fixed before extending those views.

The status bar now uses a transient file-activity popover rather than forcing a modal sheet to observe a running transfer. It shows actual live progress, pause/cancel controls and recent outcomes; cancellation never reports an operation as successful. A separate volume popover reports the owning volume, native format, access mode and OS-reported capacity. Selected folder metadata is not presented as recursively computed content size. Unknown capacity is omitted instead of fabricated. Shared operations remain accessible from the menu and command palette.

The native capture contract adds idle activity, running activity and volume information in both appearances. The tests render the same production SwiftUI popover contents and assert that rendering does not mutate operation state. These captures supplement the complete native-window, dual-pane, settings, inline-editor and modal lifecycle tests.

Hardware-dependent touch delivery, real cross-process providers and a full assistive-technology audit must still be evaluated on representative Macs. They are not inferred from bitmap rendering. Production Developer ID/notarization and Sparkle keys remain owner-managed secrets.
