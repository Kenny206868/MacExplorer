# Command, editor and accessibility scopes

`WorkspaceCommandScope` is shared by native menu commands and the local keyboard router. Any pending native sheet, collision, message, destructive confirmation or cross-pane transfer confirmation blocks file commands for both panes of that window. A stale focused workspace cannot act on another key window. Text-editor cut/copy/paste/undo stays independent and never falls through into filesystem operations when an editor declines an action.

Control–Option is reserved for macOS VoiceOver. Cross-pane copy/move uses Command–Option–C/M, or explicit buttons and menus. Control-only Explorer navigation remains available; Control–arrow and Control–Space affect files only when a file surface owns focus. Ordinary focused controls and text fields retain their navigation. The keyboard help and input preferences provide discoverable alternatives to gestures and modifier-dependent selection.

Sources: Apple VoiceOver User Guide, “Control your Mac using keyboard commands with VoiceOver” (Control–Option or Caps Lock is the default VO modifier), and public AppKit event-monitor documentation. Tests use real NSEvents and native windows without globally injecting keyboard input. This is not a substitute for an end-to-end VoiceOver/Quick Nav hardware audit.
