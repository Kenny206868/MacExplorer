# In-place filename editing

F2, Rename in the command bar/menu, and touch file actions use the same `requestRename` path. A single selected file edits its label in Details, icons, tiles, list/content, Home recent files and the Gallery filmstrip. Multiple files retain the batch rename preview dialog.

The initial selection excludes the last extension for files, but not folders. UTF-16 selection ranges handle non-ASCII names and emoji correctly. Return validates and commits through the existing transactional rename queue; Escape cancels without filesystem writes. Invalid names and occupied destinations remain in the editor after Return. Leaving an invalid editor cancels it rather than silently replacing anything. Moving to another location or removing a row cancels that editor.

A session captures the originating tab, location and source/parent identities. Changed files, changed parents, stale tabs, invalid names and non-case-only occupied targets are refused. It does not claim to eliminate all races with unrelated processes; the filesystem engine performs the final guarded rename. Case-only renames are allowed only when the destination refers to the same source object. Existing undo/redo uses the same operation receipt as batch renaming.

SwiftUI owns the editor's placement and lifecycle. A small NSTextField bridge supplies native field-editor selection, composition, clipboard, undo, focus and assistive-technology semantics. The registry weakly keys sessions by BrowserTab and never retains a closed tab. Stable parent view identity avoids cancelling an editor merely because a label becomes an input. Native tests exercise text selection, invalid/conflicting/changed names and cancellation; light/dark captures show the actual in-place editor.
