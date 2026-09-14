# MacExplorer user guide

## Your workspace

The tab strip, command bar, address/search row and file area follow Explorer conventions, with macOS visuals and system integration. The sidebar contains Home, Gallery, available cloud roots, pinned folders, This Mac, Network, Trash, tags and saved searches. Home shows files opened by MacExplorer; its recent list starts empty on a fresh installation.

Double-click a folder to enter it. Use Back/Forward/Up, breadcrumbs, or Cmd/Ctrl+L to edit a path. Absolute paths, relative paths and `~` are accepted. Choose View to change file presentation, sorting/grouping, hidden files, extensions, checkboxes, Details and Preview. Drag a pane divider to resize it. Narrow windows combine Details/Preview rather than discarding either preference.

Details initially shows Name, Date modified, Kind and Size. Click a header to sort, drag its edge to resize, drag headers to reorder, or open the header context menu to change columns, auto-size or restore defaults. Ordinary rows exist only for actual files. Date cells use a complete date when a full timestamp cannot fit; hover reveals the full value.

## Working with two panes

Click the split-pane command or press **Cmd/Ctrl+Shift+D**. Each pane has its own tabs, navigation history, current folder, view, search and selection. The numbered badge and accent line identify the active pane. Click a file area or its numbered badge to focus it; Tab switches panes when the file area owns keyboard focus. The shared top controls and sidebar follow that pane.

Both pane paths remain visible. Click a path to edit it directly, or use its menu to copy the path or navigate to an ancestor. The pane title menu switches that pane's tabs. The bottom layout menu chooses Side by Side or Stacked, equal widths, Swap Locations, or Same Location in Other Pane. A narrow window automatically stacks the browsers without changing saved layout preference. A wide window can also show the shared inspector.

Select files in the source pane and choose **Copy to other pane** or **Move…**. The destination is the other pane's current folder; wide layouts display its path beside the commands. Cmd/Ctrl+Option+C copies, while Cmd/Ctrl+Option+M requests a move. Moving requires confirmation, and identities are checked again before execution. Source and destination conflicts use the normal collision dialog, not silent overwrite. These actions do not create a permanent synchronized-folder relationship.

## Selection, keyboard and touch-friendly controls

Click selects one item; Command/Control-click toggles it; Shift-click extends a range. Shift+arrows extends keyboard selection, Control+arrows moves focus without replacing the selection, and Control+Space toggles the focused item. Home/End and Page Up/Down move through the file area; typing matches file names. Select All and Invert Selection are in More. Drag through empty grid space to draw a selection rectangle; dragging near the edge scrolls it.

Enable **View → Touch-friendly controls** for larger file rows, headers and common action targets. Select mode lets taps add/remove files without modifier keys. Open and More Actions are explicit buttons; a stationary long press opens actions for the touched file or its selected group. Single-click-open does not navigate away while Select mode is active. This remains a macOS app: physical touch depends on the connected hardware/driver delivering supported events.

F1 opens Keyboard & Gestures. F2 renames, F3 searches, F4 edits the address, F5 refreshes and F6 cycles address/search/files focus. Space opens Quick Look; Return opens selected files; forward Delete uses Trash, and Shift+Delete asks for permanent deletion. Cmd/Ctrl+T and W create/close tabs; Cmd/Ctrl+Shift+T reopens a closed tab. Control+Tab or Control+Page Up/Down cycles tabs and Cmd/Ctrl+1…9 selects them. Function keys may require Fn depending on keyboard settings.

Text fields keep their own Cut/Copy/Paste/Select All/Undo and cursor keys. Tab in an editor or native dialog is not a file-pane switch. Trackpad swipes navigate history, pinching changes icon density, and Gallery supports image magnification. The gesture setting disables application gesture handling; system-assigned gestures and device capabilities may affect delivery. Cmd/Ctrl plus or minus changes file view density outside text editing.

## Dragging, clipboard and transfers

Drag a selected file to transfer the selected group, including native file URLs and file promises for compatible receivers. Dropping into MacExplorer copies by default; Shift requests a move. Hover over a folder to spring-load it. Source selection belongs to the pane where the drag started, even when another pane was previously active. Incoming promised files are received into private staging and installed through the normal operation engine.

Cut/copy/paste uses the macOS pasteboard. Cut files are dimmed; the cut generation is reserved during the move. Skipped, cancelled or failed sources stay available for another paste. A finishing operation never replaces newer clipboard contents. Other applications do not share MacExplorer's internal cut marker.

A collision offers **Keep Both**, **Skip**, **Replace**, or **Merge Folders** when eligible. Replace replaces the whole destination item and retains a hidden recovery backup. Merge preserves destination-only children and resolves conflicting files separately. Packages and symbolic links are not traversed as ordinary merge folders. Cancel stops at safe checkpoints; completed child operations are retained with recovery receipts rather than rolled back automatically.

File Operations shows queue state, counts, transferred/logical bytes, measured throughput and an estimate where enough data is available. Clone operations can complete with little data copying. Pause/cancel are cooperative; a blocking system call may take time to return. Undo/Redo and Recovery History protect against changes made after the original operation. Recovery is not a complete crash write-ahead journal: inspect retained recovery objects after an interrupted process rather than assuming every crash has already been repaired.

## Rename, archives and properties

New creates a folder or text document. F2 renames one item or opens batch rename for a selection. Batch rename previews find/replace, prefixes/suffixes and `{name}`/`{n}` templates with numbering and extension options. Execution supports cycles and swaps without intentionally overwriting siblings.

Compress creates a ZIP. **Browse / Extract Archive…** opens a native archive browser with folder navigation, filtering, selection, destination choice and password entry. Extract Selected or Extract All installs into a new folder. Passwords are passed to the archive library and are not saved to preferences or recovery logs. Unsafe paths/links, duplicate entries and excessive expansion are rejected. In-place editing inside an archive is not implemented.

Properties and Details show filesystem information. Tags modifies Finder tags, while properties provide lock/permission controls and SHA-256. These metadata edits are not undoable; a multi-item edit can report partial completion. Preview and Gallery rotation do not change the source document. Quick Look and Open With use available native macOS handlers.

## System integration and releases

Connect to Server uses macOS authentication; MacExplorer does not collect server passwords. This Mac shows mounted volumes and capacity; Eject delegates to the system. iCloud and other File Provider roots are discovered, but provider-specific features vary. Folder association and launch-at-login are opt-in. Services and file/open URL events require running the complete application bundle.

Tabs, open windows and closed-window history are persisted, including dual-pane companions. Reopen closed windows from Window History. Saved frame positions are clamped to available screens. Application termination waits for active file operations to finish or be cancelled.

Install alpha ZIP/DMG distributions from the repository Releases page and read the included `INSTALL.md`. Alphas are ad-hoc signed, not Apple notarized; do not disable macOS security globally. Each alpha includes source, the sample-data design, native screenshot galleries, a commit identity and checksums. Production signing/notarization and Sparkle updates require owner-configured keys. See [capabilities](CAPABILITIES.md) for the current implementation boundaries.
