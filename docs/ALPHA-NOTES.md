# Native design alpha track

This revision prioritizes the original interactive design in the real SwiftUI application. It introduces reference light/dark colors, explicit chrome hierarchy, 211-point sidebar and 254-point inspector defaults, accessible user-resizable dividers, a custom SwiftUI Details table without empty zebra rows, fitted default columns, sortable/resizable/reorderable headers, compact Home cards, populated recent-file columns, redesigned file information, tags, native preview artwork and path-aware breadcrumbs.

CI now includes **52 real native captures on each of macOS 15 Intel and macOS 26 Apple Silicon**, including populated Home, Details and This Mac reference views. Native assertions check actual pane/chrome geometry and sampled palette/selection colors, in addition to existing layout, rendering and integration checks. The artifacts include all PNGs and an offline gallery. Passing a sampled palette test does not certify every interaction or replace visual review.

Existing recursive merge, copy progress graphs, cancellation, undo/recovery, archive browsing and password-aware selective extraction, file-promise import/export, Gallery, selection, window-session persistence and macOS integrations remain independent of visual styling. The capability matrix records remaining parity boundaries; no complete Windows/Finder equivalence is asserted.

Alpha snapshots publish only after the exact commit passes universal packaging, core tests and both native UI jobs. Native ZIP/DMG, source, design and screenshot archives carry matching provenance and checksums. Alphas are ad-hoc signed, not Apple notarized, and do not update the stable Sparkle feed. Apple signing and production updater keys require owner configuration.
