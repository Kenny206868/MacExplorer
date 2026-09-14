# Capability matrix and platform boundaries

Status describes source implementation, not a completed QA certification. The CI history is the authority for compile/test status. A published browser design is not evidence that a native operating-system feature has been validated.

| Area | Implemented path | Boundary / qualification |
|---|---|---|
| Explorer layout | Tabs, command bar, address/breadcrumb navigation, search, tree, content, panes, status bar | Native macOS styling rather than Microsoft artwork or binary UI reuse |
| Windows and tabs | Multiple windows, draggable/reorderable tabs, cross-window transfer, duplicate, close others/right, reopen closed, explicit Move to New Window, history and session restoration | Desktop drag-to-detach and persistent closed-window recovery are not implemented; reopened tabs are retained in a bounded per-window stack |
| Quick Access | Persistent bookmark-backed pins, Home cards | No automatic usage-ranked frequent-folder model |
| Navigation tree | Lazy child expansion, volumes, cloud roots, user folders | Symlink subtrees are not expanded; depth is bounded |
| Details | SwiftUI Table, selection, natural sort, columns, width/order/visibility customization | No arbitrary shell-extension columns |
| Views | Extra-large/large/medium/small icons, list, details, tiles, content, Gallery choice | Some modes share native layout primitives; exact pixel/interaction equivalence to every Windows view is not claimed |
| Selection | Table multiselect, Command/Control toggles, shrinking Shift ranges, additive range baseline, select all/invert, grid marquee, checkboxes in details and grids, separate focus and anchor, Unicode type-ahead | Grid hit testing uses deterministic geometry for virtualized cells; edge-autoscroll and every cross-group keyboard/type-ahead edge case remain separate work |
| Navigation shortcuts | Command and Control equivalents, Alt arrows/address, F2/F3/F5, Enter, forward Delete, Space, Backspace navigation, Home/End, tab cycling/reopening and 1–9 selection | Physical F-key behavior depends on the Mac keyboard Fn setting; text Edit commands are routed to the field editor rather than filesystem operations |
| Drag/drop | Native multi-item NSURL dragging sessions, file URL drops, explicit Shift-to-move, delayed spring-folder navigation, process-local tab drag tickets | No NSFilePromiseProvider transfer; inbound/outbound behavior depends on the receiving app; source files are never deleted solely because a drag reports Move |
| Clipboard | Native file URL pasteboard, cut dimming, generation-scoped cut reservation, exact completed-source reconciliation, cancellation/partial-failure retention | External apps do not share MacExplorer's cut intent; a newer pasteboard generation is never overwritten by an older operation |
| Transfers | Serialized operation engine, temporary staging, collision decisions, replacement backups, origin-tab result selection after refresh | Replace-folder means replacement, not recursive merge; cross-volume moves are not a whole-tree transaction |
| Progress | Per-job and top-level item counts, queue, pause/cancel, error display, finished-state protection against late progress callbacks | No byte-rate graph/ETA; an in-flight single-file copy or system call may not pause immediately |
| Undo/redo | In-memory stack and durable completed-step recovery receipts, two-phase inverse rename batches with cycle-safe Redo, preserved batch marker on retry | Not a complete crash-write-ahead journal; external changes can invalidate fingerprints; metadata edits and permanent deletion have no undo |
| Rename | Single and batch rename, find/replace, prefix/suffix, numbered templates, preview, two-phase execution, swap/cycle-aware recovery | Whole batch is staged; volume-specific case/name rules and interrupted rollback require representative filesystem coverage |
| Trash | Real macOS Trash and tracked original restore destinations | Restore paths for items trashed by unrelated applications are not inferred; Full Disk Access may be required; no global Empty Trash command |
| Permanent deletion | Explicit confirmation and direct removal | No secure erase guarantee; disabled OS protections are never requested |
| Archives | ditto ZIP creation, libarchive extraction into a new directory, system-library ABI bridge for SDKs without development headers | Unsafe links, device nodes, traversal, duplicates, oversized expansion are rejected; no archive-as-folder editing; encryption/password prompts unsupported; AppleDouble metadata extraction is not reconstructed |
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
| Accessibility/theme | Native SwiftUI controls, VoiceOver labels, focus presentation, system colors, dark/light/system themes | Full assistive-technology/manual keyboard audit remains necessary |
| Distribution | Universal app, ZIP/DMG, optional Developer ID and notarization, signed Sparkle feed, GitHub releases, exact-commit source/design ZIPs | Secrets and signing identity must be configured by the owner; no notarized release or current green build is implied by committed workflows |
| Web design | Interactive, self-contained sample-data prototype and standalone ZIP | Browser mockups label OS interactions as previews; they never pretend to operate the user's files |

## Platform contracts and release claims

Windows shell COM extensions, NTFS-specific security/streams, BitLocker, Windows Libraries, Windows networking and cloud integrations are separate platform contracts. Public macOS APIs provide different contracts. MacExplorer uses those supported APIs rather than emulating undocumented behavior or disabling protections. This matrix distinguishes implemented user interactions from the remaining parity gaps.

Representative macOS machines, file providers, network shares, very large directories, privacy-denied paths, interrupted operations, and assistive technologies still require release-level evaluation. A successful build of an earlier commit does not establish the status of a later commit. No 100% Explorer parity or production certification is claimed.

Implementation contracts: [selection engine](INTERACTION-ENGINE.md), [file surface](FILE-SURFACE.md), [tabs and clipboard](TABS-DRAG-AND-CLIPBOARD.md), [rename recovery](RENAME-RECOVERY.md), [text command routing](TEXT-COMMANDS-AND-DELIVERY.md), and [release configuration](RELEASING.md).
