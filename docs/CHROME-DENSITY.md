# Useful titlebar space, one action shelf

The previous Commander presentation used a 32-point per-pane status row, a 37-point function-key strip, a separator, and a 40-point transfer footer. The screenshot review identified stretched command cells and a largely vacant titlebar center. This revision reorganizes those existing functions instead of filling the window with more decoration.

## Native titlebar

A SwiftUI Workspace Navigation view is installed as a real customizable NSToolbarItem. It contains Single/Side-by-side/Stacked layout controls, independently clickable pane identities, Swap, Compare (when space permits), and Search Commands. In a single pane the middle space offers Go to Folder. Compact windows keep layout and command search; all workspace actions remain in the native overflow menu and layout control context menu. Tooltips retain complete paths. Existing path editors and Terminal shortcuts remain unchanged.

The titlebar view has its own equatable value model: file selection and hover do not republish it. Resizing updates its constraints without recreating the toolbar. AppKit retains traffic lights, title, represented-folder integration, native dragging, overflow and customization. An exact old default toolbar is migrated; a user's different/customized arrangement is preserved, with Workspace Navigation available in Customize Toolbar.

## Footer

Commander commands are content-sized groups: View/Edit, Copy/Move, Folder/Trash. A single 38-point desktop shelf contains those groups, a destination shortcut, Select, Activity and Tools. Clicking the destination edits the other pane's full path. Transfer preparation uses the same shelf for cancellable checking; notice details are available without opening a blocking sheet. With Commander disabled, the shelf offers the Panes menu and Copy/Move. Single-pane native mode retains the existing status summary.

Per-pane summaries are 26 points high on desktop. The duplicate Commander/transfer row is removed, saving 45 vertical points versus the previous side-by-side Commander layout (110 to 65 points including separating rules). No function key is remapped by this redesign; existing opt-in Commander behavior and confirmation guards are preserved. The plain status now says `1 item`, not `1 items`.

Touch mode keeps 44-point action targets and a 52-point shared shelf. Narrow touch layouts replace text labels with accessible, named icons rather than shrinking targets. Layout policy is pure ExplorerCore code with finite-input and density tests.

## Validation contract

Eight additional native captures cover wide/narrow Commander, narrow touch, and standard-profile windows in both appearances. They assert exact shelf and pane-status heights, bounded command-group width, nonoverlap of footer regions, visible/sized native titlebar controls and unchanged file selection. The required gallery is 128 captures per platform. Real native tests also exercise layout/modal routing, no-selection-publication behavior, live host resizing, customization preservation and exact-default migration.

The existing macOS 15 Intel/macOS 26 native, filesystem, crash-recovery and optimized scrolling gates remain. Source parsing on Linux is not a native UI pass; the exact commit's CI and images establish what was executed. These checks do not measure physical input-to-photon latency or replace a complete hardware/VoiceOver audit.
