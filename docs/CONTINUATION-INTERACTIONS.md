# Native interaction continuation — 2026-09-14

The native app now uses the tested Explorer selection state machine for pointer selection and keyboard navigation. It supports shrinking Shift ranges, additive Control/Command selection, independent keyboard focus, Home/End, Control+Space, Control+Arrow, Unicode type-ahead, Control+Tab, Control+Shift+Tab, and Control+Shift+T to reopen a closed tab. Text fields, text views, IME composition, attached sheets, alerts, and deletion confirmations retain their own input handling.

File-operation output selection is delivered after refreshed directory contents arrive, and only to the initiating tab while it remains at the initiating location. Navigating elsewhere during a transfer no longer selects unrelated paths. Failed/skipped/cancelled cut-paste sources remain on the clipboard; successful moves consume only the still-current private cut session. A later user clipboard change is never overwritten by an older operation completion.

Closed windows cannot suspend the global operation queue with invisible collision prompts. Stopping a tab invalidates asynchronous enumeration generations. The configured Home/This Mac startup location is now respected when restoring tabs is disabled.

Grid geometry, native multi-file dragging, and tab transfer are layered in subsequent changes. CI status is reported separately from source implementation; this is not a claim of complete Finder/Windows shell substitution.
