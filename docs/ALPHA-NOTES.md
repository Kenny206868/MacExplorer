# Dual-pane design and input alpha

The native application now has independent tab groups in two panes: separate locations, histories, search, selection and view modes; active-pane command routing; responsive stacked fallback; resizable split proportions; and persisted companion sessions. Copy to Other Pane captures its destination. Move to Other Pane requires confirmation and revalidates source/destination identities. Both use the real operation engine and recovery receipts.

All file presentations share one activation path. Touch Select mode works without modifier keys, long press opens the owning pane's actions, and single-click-open cannot accidentally navigate away while selecting. Touch density uses 44-point rows, headers and shared controls. Native dragging prepares only the source pane's files. Gallery uses the same selection contract and its magnification honors the gesture preference.

The mandatory native capture matrix has **68 views on macOS 15 Intel and 68 on macOS 26 Apple Silicon**. It includes populated dual panes in both orientations, narrow fallback, the wide inspector, secondary focus, touch density, file actions and keyboard help, alongside the single-pane design references and all existing modes/dialogs. Native tests feed actual NSEvents through command routing and verify text editors and focused controls retain their own events. These are headless production-view and command-path tests, not physical touchscreen or full cross-application drag certification.

Release assembly reruns the exact source commit's complete visual contract and checks every native package checksum before publication. All assets identify that commit; a source edit cannot silently reuse an older binary or screenshot gallery. Alpha builds are ad-hoc signed and not Apple notarized. The stable Sparkle feed is not modified; production signing/update credentials require owner configuration.

Known remaining parity boundaries remain in the capability matrix. In particular, an alpha does not claim to replace Finder's private desktop/Dock services, Windows-only shell extensions, or every external application's file-promise implementation.
