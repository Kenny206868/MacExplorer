# User guide

## Familiar layout

The top strip contains tabs. Below it are the command bar, navigation buttons, editable breadcrumb/address field, and search. The left tree contains Home, Gallery, cloud roots, Quick Access, mounted devices, network, Trash, tags, and saved searches. The main area shows real files. Details and Quick Look Preview can be shown independently on the right.

Home's recent list starts empty and contains files opened with MacExplorer. Pin folders using the context menu; unpin from the tree. Gallery enumerates image files beneath Pictures, not the Photos database.

Double-click folders to enter them. Select a breadcrumb to navigate to an ancestor. Command-L edits the path; absolute, relative, and tilde-prefixed filesystem paths are accepted. Alt-Left/Right go back/forward; Alt-Up goes to the parent. Open Folder uses a native panel.

## Views and selection

The View menu offers extra-large, large, medium, small, list, details, tiles, content, and gallery layouts. Sort by name, dates, kind, size, or tags; choose direction, folders first, and optional grouping. These settings are remembered per folder. Details uses a native customizable table: resize/reorder columns and use its column customization controls. Check boxes are a Details-view option.

Click to select, Command/Control-click to toggle, and Shift-click for a range. Command-A selects all. More → Invert Selection selects the remainder. Icon/list views can be configured for single-click opening. Rubber-band selection and full outbound multi-item drag parity are not part of this version.

## File work

Use New → Folder or Text Document. F2 opens Rename. For multiple selected files the rename dialog previews find/replace, prefixes, suffixes, and templates using `{name}` and `{n}`. Numbering has configurable start and padding. Rename preflights the batch and does not overwrite unrelated files.

Cut/Copy/Paste use the native pasteboard. Command-X/C/V and Control-X/C/V work when a file view has focus. The private cut state is invalidated when another application changes the pasteboard. Copy To and Move To offer pins or a chosen folder.

Drop a file URL onto a folder to copy it. Hold **Shift** to request a move. The prototype and native app do not claim Finder's complete volume-dependent drag heuristic. Tile drags currently export the dragged item rather than an arbitrary selected set.

A collision dialog offers Keep Both, Replace, Skip, or Cancel. Keep Both chooses a numbered name. Replace keeps the old destination as a hidden `.MacExplorer-replaced-*` backup. **Replacing a folder replaces the folder; it does not merge children.** File Operations shows progress, pause/resume, cancellation, and per-item errors. Progress is top-level item based, not a byte-throughput graph. A large in-flight system copy may finish its current file before cancellation takes effect.

Command-Z and Shift-Command-Z undo/redo reversible operations. Recovery History lists completed-step receipts preserved across launches. Recovery refuses files that no longer match their recorded identity or destinations occupied by newer data. Do not delete receipts or hidden replacement backups until you have decided they are no longer needed. A receipt is not a backup of every byte.

Delete moves selected files to Trash. Shift-Delete requests permanent deletion with confirmation. Permanent deletion has no undo and is not secure erase. Items trashed by MacExplorer have recorded restore destinations. MacExplorer does not invent original paths for files trashed by other applications; use Finder for those restorations.

## Preview, share, and properties

Space or Command-Y invokes macOS Quick Look. The Preview pane embeds Apple's preview surface; installed preview extensions determine supported formats. Online-only files may need downloading first. Share opens the native share sheet, including AirDrop when available. Open With lists applications registered for the selected file.

Command-I opens Properties. It includes real file dates, size, type, location, owner/group, permissions, tags, and cloud status. Calculate folder allocated size or a streaming SHA-256 checksum explicitly; these operations are cancellable. Tags edit Finder tag names. Permissions and lock changes apply only to the selected item, not recursively, and are not undoable in MacExplorer. Setting a default application uses Apple's consent-aware API.

Compress creates a ZIP with macOS ditto. Extract creates a new folder through libarchive. Unsafe archive paths, links, special entries, duplicate names, or safety-limit violations are rejected. Encrypted archives and in-place archive editing are not supported. Extraction does not reconstruct ditto AppleDouble metadata.

## Search

Search is literal by default. Examples:

```text
quarterly report
"release notes" ext:md
ext:pdf size:>10MB
kind:folder
modified:today
modified:week
tag:Work
content:"pump specification"
```

The current-folder search can include descendants. This Mac uses Spotlight. Content queries always use Spotlight; results depend on indexing and permissions, not a separate crawler. Save Search retains the expression. The recursive result limit is 25,000; the UI reports truncation rather than silently claiming an exhaustive result.

## macOS services

This Mac shows actual mounted volumes and capacity. Eject uses the system API and reports busy/error conditions. Network discovers SMB servers that advertise through Bonjour. Command-K accepts a server address and delegates authentication and mounting to macOS. No server passwords are stored by MacExplorer.

Cloud roots include iCloud Drive and visible File Provider folders. iCloud download/eviction actions apply to ubiquitous items; third-party providers may implement different behavior. MacExplorer does not fabricate their sync state.

Install in Applications to use Finder → Services → Open in MacExplorer, `open -a MacExplorer /path`, or `macexplorer://open?path=/path`. Settings → Integration offers explicit folder-handler and login-item opt-ins. Both are reversible. Finder's system desktop, Dock contracts, and other apps' open/save panels continue to exist.

## Keyboard reference

| Action | Shortcut |
|---|---|
| New window / new tab / close tab | Command-N / Command-T / Command-W |
| New folder | Shift-Command-N |
| Address / search | Command-L / Command-F |
| Back / forward / up | Alt-Left / Alt-Right / Alt-Up |
| Rename / refresh | F2 / F5 (Fn may be required on Mac keyboards) |
| Open / Quick Look | Enter / Space |
| Properties / server / operations | Command-I / Command-K / Command-J |
| Cut / copy / paste | Command-X / C / V; selected Control equivalents |
| Copy paths | Shift-Command-C |
| Trash / permanent deletion | Delete / Shift-Delete |
| Undo / redo | Command-Z / Shift-Command-Z |
| Hidden items | Shift-Command-period |

Shortcuts are scoped to the application and do not intercept typing in text fields. See the capability matrix for remaining parity limitations.
