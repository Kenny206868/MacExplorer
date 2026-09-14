# Capability matrix and platform boundaries

Status describes source implementation, not a completed QA certification. The CI history is the authority for compile/test status. A published browser design is not evidence that a native operating-system feature has been validated.

| Area | Implemented path | Boundary / qualification |
|---|---|---|
| Explorer layout | Tabs, command bar, address/breadcrumb navigation, search, tree, content, panes, status bar | Native macOS styling rather than Microsoft artwork or binary UI reuse |
| Windows and tabs | Multiple windows, close/duplicate tabs, history, session restoration | Dragging tabs between windows and full native tab tear-out are not implemented |
| Quick Access | Persistent bookmark-backed pins, Home cards | No automatic usage-ranked frequent-folder model |
| Navigation tree | Lazy child expansion, volumes, cloud roots, user folders | Symlink subtrees are not expanded; depth is bounded |
| Details | SwiftUI Table, selection, natural sort, columns, width/order/visibility customization | No arbitrary shell-extension columns |
| Views | Extra-large/large/medium/small icons, list, details, tiles, content, Gallery choice | Some modes share native layout primitives; exact pixel/interaction equivalence to every Windows view is not claimed |
| Selection | Table multiselect, Command/Control selection, Shift ranges, select all/invert | Rubber-band/lasso selection and every Explorer type-ahead edge case are not implemented; checkboxes apply to Details |
| Navigation shortcuts | Command and selected Control equivalents, Alt arrows, F2, F5, Enter, Delete, Space | Physical F-key behavior depends on the Mac keyboard Fn setting; shortcuts do not override text editing |
| Drag/drop | OS file URLs, destination folder drops, explicit Shift-to-move | File tiles export the dragged item; full multi-item outbound drag/promise parity and spring-loaded folders remain work |
| Clipboard | Native file URL pasteboard; private cut tracking by pasteboard change count | External apps do not share MacExplorer's cut-intent state |
| Transfers | Serialized operation engine, temporary staging, collision decisions, replacement backups | Replace-folder means replacement, not recursive merge; cross-volume moves are not a whole-tree transaction |
| Progress | Per-job and top-level item counts, queue, pause/cancel, error display | No byte-rate graph/ETA; an in-flight single-file copy or system call may not pause immediately |
| Undo/redo | In-memory stack and durable completed-step recovery receipts | Not a complete crash-write-ahead journal; system-wide external changes can invalidate receipts; metadata edits and permanent deletion have no undo |
| Rename | Single and batch rename, find/replace, prefix/suffix, numbered templates, preview, two-phase execution | Whole batch is staged; transaction recovery must be tested against volume-specific case and name rules |
| Trash | Real macOS Trash and tracked original restore destinations | Restore paths for items trashed by unrelated applications are not inferred; Full Disk Access may be required; no global Empty Trash command |
| Permanent deletion | Explicit confirmation and direct removal | No secure erase guarantee; disabled OS protections are never requested |
| Archives | ditto ZIP creation, libarchive extraction into a new directory | Unsafe links, device nodes, traversal, duplicates, oversized expansion are rejected; no archive-as-folder editing; encryption/password prompts unsupported; AppleDouble metadata extraction is not reconstructed |
| Properties | Real dates, sizes, owner/group, permissions, tags, cloud state, allocated size, SHA-256 | No arbitrary ACL editor, ownership escalation, NTFS alternate-stream tools, or Windows security dialog emulation |
| Tags and lock | Finder tag names and file lock attributes | Metadata changes may partially complete when a later item fails; not part of undo |
| Search | Recursive filename/metadata predicates; Spotlight content, tag and whole-Mac queries; saved expressions | Spotlight depends on indexing/permissions; 25,000-result recursive limit is explicit; no complete Windows AQS language |
| Gallery | Actual image enumeration/thumbnails in Pictures | Not a Photos library client or Windows Gallery collection manager |
| Quick Look | System Quick Look popup and optional preview surface | Depends on installed preview extensions and accessible/downloaded files |
| Sharing/Open With | Native ShareLink, AirDrop where offered, NSWorkspace application discovery/open | Available services depend on macOS configuration |
| Volumes | Mounted volumes, real capacity, eject | No disk partitioning, formatting, mounting arbitrary disk images, or BitLocker management |
| Network | Bonjour SMB discovery, server address route through macOS, mounted network folders | Not Active Directory/workgroup enumeration; NFS/WebDAV behavior depends on OS/server |
| Cloud | iCloud root and File Provider roots; ubiquitous-item availability/download/eviction | Third-party provider status/actions are not equivalent to iCloud APIs; no invented OneDrive/Dropbox state |
| Integration | Folder-type association opt-in/restore, Services, file/open URL events, Terminal, login item | Finder's desktop/Dock/private shell services and other apps' open/save panels are not replaced |
| Accessibility/theme | Native SwiftUI controls, VoiceOver labels, dynamic system colors, dark/light/system themes | Full assistive-technology/manual keyboard audit remains necessary |
| Distribution | Universal app, ZIP/DMG, optional Developer ID and notarization, signed Sparkle feed, GitHub releases | Secrets and signing identity must be configured by the owner; no notarized release is implied by committed workflows |
| Web design | Interactive, self-contained sample-data prototype and ZIP | Browser mockups label OS interactions as previews; they never pretend to operate the user's files |

## Why “100% Explorer and Finder replacement” is not the release claim

Windows shell COM extensions, NTFS-specific security/streams, BitLocker, Windows Libraries, Windows networking and cloud integrations are separate platform contracts. Public macOS APIs provide different contracts. MacExplorer uses those supported APIs rather than emulating undocumented behavior or disabling protections. This matrix keeps the visible work and the remaining parity gaps explicit.

The first implementation is substantial native application source, but must be evaluated on representative macOS machines, file providers, network shares, very large directories, privacy-denied paths, interrupted operations, and assistive technologies before being treated as production-certified.
