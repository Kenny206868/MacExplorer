# Implementation log

## 2026-09-14 — Design and native foundation

- Published the interactive browser design before beginning the native app. The browser is explicitly a sample-data interaction prototype; native filesystem access is not represented as working in a web page.
- Native implementation targets macOS 14 and later, SwiftUI, Swift Package Manager, and universal arm64/x86_64 distributions.
- Audited ActivityMonitor's Package.swift, release.yml, package.sh, and generate-appcast.sh. Adopted its pinned Sparkle 2.9.6 dependency and separated build, signing, notarization, and publishing concepts. MacExplorer must have its own update signing configuration.
- Added immutable file snapshots, per-folder view/sort/group options, persistent navigation types and bookmarks, cancellable enumeration/search, metadata inspection, SHA-256 checksums, and iCloud download/eviction APIs.
- Added a cross-window serialized operation actor, staging before installation, replacement backups, collision decisions, reversible receipts, a durable recovery log, Trash integration, pause/cancel checkpoints, and two-phase rename.
- Added metadata-preserving ZIP creation using macOS ditto and isolated libarchive extraction with traversal/link/special-file rejection and expanded-size limits.

## Validation status

This implementation session does not claim a completed macOS validation run. CI and release automation are delivered as source, and their actual run status must be checked independently. API support does not imply complete Windows shell or Finder subsystem replacement. See CAPABILITIES.md for the explicit boundary.
