# Window sessions and recovery

Every Explorer window has its own recoverable snapshot: tab order, active tab, each tab's back/forward history, search expression and scope, per-tab layout, selected paths, closed-tab stack and window frame. Unlike the legacy global list of folder paths, this does not let one window overwrite every other window's state.

The first ordinary Explorer window claims the launch snapshot once. Remaining saved windows are requested through a typed SwiftUI WindowGroup; subsequent New Window commands start at the configured starting location. Disabling Restore Tabs suppresses launch recovery. **Window → Reopen Closed Window** and **Window History** provide explicit recovery after a relaunch. Clearing history affects only recovery metadata, not user files.

Closing a window records it in the bounded recent-history stack. Quitting flushes all open windows before termination and does not mistake quit-time close notifications for user-closed windows. Restored frames are clamped to available screen work areas.

Snapshots are coalesced, serialized to a private Application Support location on a utility queue, and installed by atomic replacement. The file is mode 0600; new parent directories are mode 0700. Invalid schemas, empty windows, invalid navigation indices, non-finite rectangles and oversized documents are rejected before indexing. A decoding error leaves the original file intact and appears in Window History rather than crashing launch.

Recovery persistence is bounded to 30 open windows, 12 closed windows, 100 tabs per window, 30 closed tabs, 128 history locations and 2,048 selected paths per tab, with an 8 MiB document limit. Persisted searches are limited to 8,192 characters. These persistence bounds do not restrict normal in-memory selection, tab duplication, or drag transfer. Archive passwords are never part of session models.

Native CI tests exercise round trips, permissions, invalid payloads, single-consumption launch restoration, closed-window recovery, and quit behavior using isolated temporary stores. Scene activation, relaunch and multi-monitor behavior require end-to-end OS coverage beyond these model tests.
