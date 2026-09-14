# Group-aware grid navigation

Vertical arrows follow visual rows, including partial final rows and transitions across group headers. `GridNavigation` operates on group counts and the actual rendered column count without allocating a row per file. It preserves the column when possible and clamps only to an existing item in a short row. Empty groups, boundaries, invalid geometry and overflowing counts are covered by core tests.

The native keyboard router uses this topology for icon/tile grids, and linear navigation for Details, List, Content and Gallery. It retains the existing independent focus/anchor semantics, Shift extension and Control/Command focus-only navigation. The pointer marquee uses the separately implemented native edge-autoscroll bridge; no global input interception is introduced.
