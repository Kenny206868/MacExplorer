# Native design and input completion pass

## Dual-pane workspace

The previous dual layout repeated the active pane's global address, pane name, and a second raw path before the files. The revised layout has a shared window title and command bar, then two independent tab strips and location/search controls. This removes duplicate global navigation, exposes the second pane's tabs directly, and gives file content more vertical space. Path menus show ancestors without filling the toolbar with temporary or deep directory prefixes. Each pane retains its own editor and query focus. Search is expandable per pane; keyboard search opens that pane's field.

A shared bottom transfer bar shows the source-to-destination direction, Copy as the primary action, Move with confirmation, operation history, and explicit layout actions. A narrow layout uses the same stacked fallback and preserves orientation intent. The inactive pane retains readable filenames and visible selection; accent edges and pane numbers indicate command focus.

Existing single-pane reference colors, layout geometry, file transactions, drag safety and password-aware extraction are unchanged by this visual pass. Native screenshots remain mandatory; the new layout must pass the existing containment matrix before publication. This document records source changes, not an assertion that a not-yet-finished CI run passed.
