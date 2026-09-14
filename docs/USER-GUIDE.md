# MacExplorer user guide

## Workspace and design

Home shows pinned Quick Access folders and documents opened through MacExplorer. The sidebar provides available cloud roots, locations, tags and saved searches. This Mac shows mounted devices and common folders. The native light/dark palette and accent follow the design system; Settings provides General, Appearance, Input, Integration and Updates pages.

Double-click a folder to enter it. Back/Forward/Up, breadcrumbs and Command/Control+L navigate. The location editor accepts absolute/relative paths and `~`. The View menu changes file layouts, compact rows, checkboxes, extensions, hidden files and auxiliary panels. Drag dividers to resize; compact windows combine Details/Preview without losing preferences.

Details initially shows Name, Date modified, Kind and Size. Click headers to sort, drag header edges to resize, drag headers to reorder, or use their context menu to choose columns and sizing. Collapsed groups are excluded from keyboard selection, so an invisible row cannot remain a hidden file-action target. Row display labels may be shorter than macOS's full type/size/date descriptions; tooltips and Properties retain full values.

## Two independent panes

Use the split button or **Command/Control+Shift+D**. Both panes expose their own tab strip, location editor, ancestor menu and search. Tabs, histories, queries, view options and selections remain independent. The shared sidebar, commands and optional inspector follow the active pane, indicated by its accent edge/number. Click a file area or use **Tab** while file focus is active to switch panes.

The titlebar switches Side by Side and Stacked orientation. The center divider resizes panes; double-click resets equal sizes. Narrow windows stack without overwriting saved orientation. Wide windows can show auxiliary details or previews; these preferences are retained at smaller sizes.

The bottom bar shows source → destination. **Copy to other pane** transfers the source selection; **Move…** asks for confirmation. Command+Option+C/M provide shortcuts. Source/destination snapshots are checked again before execution. This is an explicit transfer, not ongoing synchronization. Control–Option is reserved for VoiceOver.

## Tabs, drag and windows

Use the plus button, Command/Control+T, or a tab context menu. Command/Control+W closes a tab; Command/Control+Shift+T reopens one. Control+Tab/Page Up/Page Down cycles tabs; Command/Control+1…9 selects them. Duplicate, Close Others and Close Right are available in the tab context menu.

Drag tabs within a strip, between panes or into another MacExplorer window. Live tab state moves with the tab. Dropping outside can request a new window when macOS reports an unambiguous mouse release; explicit **Move to New Window** uses the same source-retaining handoff. The original tab is not removed until the destination appears. Escape and failed internal drops leave it intact.

Open/closed windows, tabs, searches, selections and companion panes persist. Window History restores closed windows. Saved positions are clamped to available screens, and quitting waits for active file operations to finish or be cancelled.

## Keyboard, selection, touch and gestures

Click selects; Command/Control-click toggles; Shift-click extends a range. Shift+arrows extends a range, Control+arrows moves focus without replacing selection, and Control+Space toggles the focused file. Home/End and Page Up/Down move through the file area; typing selects matching names. Empty-space drags draw a marquee in icon grids and Details, with edge scrolling. Select All/Invert work on expanded rows.

F1 opens shortcut help. F2 renames, F3 searches, F4 edits location, F5 refreshes, and F6/Shift+F6 cycles location/search/files. Return opens, Space previews, Delete moves to Trash, and Shift+Delete asks for permanent removal. Function keys can require Fn according to system settings.

Enable Touch-friendly controls for larger common targets and file rows. Select mode adds/removes files without modifier keys; explicit Open and More Actions avoid requiring double-click or hover. A stationary long press opens file actions. Single-click-open does not interrupt modifier-free selection. Physical touchscreen behavior depends on compatible device/driver delivery of macOS events.

Trackpad swipes navigate history, pinching changes icon density, and Gallery supports image zoom. Smart zoom/pressure can invoke Quick Look when supported. Ordinary two-finger scrolling remains native. Disable application gestures in View or Settings; system-assigned gestures remain under macOS control.

Text editors, native sheets and dialogs retain clipboard/undo/cursor keys. Menu and keyboard commands share a guard that blocks file actions behind modal UI in either pane. Control–Option is never intercepted as a file command, preserving the standard VoiceOver modifier.

## File operations

Drag selected files to copy; Shift requests a move within MacExplorer. Native URL and promise formats are offered to compatible receivers. Hovering a folder can spring-load it. File promises are received into private staging, checked and installed by the normal operation engine. A receiver reporting Move never causes the source to delete files a second time.

Cut/copy/paste uses the macOS pasteboard. Cut files dim, and a specific clipboard generation is reserved during a move. Skipped, cancelled or failed sources remain available for another paste. A finishing job cannot replace newer clipboard contents; other apps do not share MacExplorer's internal cut intent.

Conflicts offer Keep Both, Skip, Replace or Merge Folders when eligible. Replace retains a hidden backup of the entire displaced item. Merge preserves destination-only children and resolves conflicting files separately; packages and links remain indivisible. Cancellation stops at safe checkpoints and retains completed child work with recovery records.

File Operations shows queue state, item counts, native copy/logical bytes, throughput, estimates, pause/cancel and errors. Clone copies may have little physical copying. Blocking system/provider calls may delay progress or cancellation. Undo/Redo and Recovery History protect against subsequent changes. This is not a complete crash write-ahead journal: retained recovery objects may need inspection after an interrupted process.

## Rename, archives and properties

F2 or Rename on one selected file edits its visible name in place. The initial selection excludes the final extension for ordinary files and uses the correct Unicode field-editor range. Return validates and renames through the undoable queue; Escape cancels. An occupied name or changed source is refused. Invalid text remains after Return; leaving an invalid editor cancels instead of replacing anything. Text selection during rename cannot start a file drag. Multiple-file Rename opens the preview dialog with find/replace, prefix/suffix and numbered `{name}`/`{n}` templates; swaps/cycles use staged renaming.

Compress creates ZIP. Browse / Extract Archive opens a native header browser with navigation, filter, selection, destination and password entry. Extract Selected/All installs into a new folder, preserving quarantine information where present. Passwords are passed to the archive library, not stored. Unsafe entries and excessive expansion are rejected. In-place editing inside archives is not implemented.

Properties exposes real metadata, lock/permission controls, tags and SHA-256. Metadata editing is not undoable and may report partial completion. Preview/Gallery rotation does not modify the source document. Quick Look, Open With, sharing and AirDrop use available macOS services.

## Integration and alpha distributions

Install the complete MacExplorer.app bundle for Services, URL routing and login items. Settings makes folder association and launch-at-login opt-in; Restore Finder reverses folder association. Server authentication is handled by macOS. Cloud roots and supported iCloud actions are discovered without inventing provider synchronization status.

Published alphas include matching universal ZIP/DMG, source, interactive sample-data design, native PNG review galleries, commit identity and checksums. Read INSTALL.md. Alphas are ad-hoc signed and not Apple notarized; never disable macOS security globally. Production signing/notarization and Sparkle updates require owner-configured keys. The [capability matrix](CAPABILITIES.md) records remaining development and platform boundaries.
