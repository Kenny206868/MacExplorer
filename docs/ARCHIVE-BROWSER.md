# Native archive browsing and extraction

The Browse / Extract Archive action opens a SwiftUI archive browser backed by real libarchive headers, not a fabricated file list. The table supports implicit and explicit folders, parent/breadcrumb navigation, name filtering, multiselection, size/date/encryption metadata, a destination picker and a secure password field. Extract Selected includes selected directory subtrees; Extract All uses the same bounded extractor. The normal serialized operation center supplies cancellation, progress history and a recovery receipt for the installed extraction directory. Successful extraction offers Open Folder in a normal MacExplorer tab.

## Passwords and format support

Passwords pass directly to `archive_read_add_passphrase`. They are never serialized into preferences, operation receipts, manifests, logs or subprocess arguments. `ArchiveReadOptions` intentionally does not conform to Codable. The UI clears its password after success and dismissal. Swift strings and system-library buffers do not provide a guaranteed secure-memory-erasure contract. Actual encryption/codec support depends on the system libarchive; the regression fixture exercises password-protected ZIP, not every encrypted archive format. Incorrect or absent passwords leave the original archive untouched and no installed partial extraction directory.

## Filesystem boundaries

Extraction stages into an exclusively created private directory and installs only after cancellation, source fingerprint and destination identity checks. It rejects traversal, absolute names, alternate separators, duplicate paths, links, special nodes, more than 100,000 headers, expanded data above 20 GB, excessive path length and excessive nesting. These defaults are explicit read options. Conventional leading ./ tar paths are normalized; internal dot or parent components are not silently reinterpreted. Unsafe members remain grounds for rejecting an extraction even when another subtree was selected.

The extractor preserves representable modification dates, normalizes permissions to keep owner management possible while removing set-id and group/world write bits, and does not restore archived ownership. macOS quarantine properties, when present on the archive, propagate to the extraction root and its descendants before installation. Nothing is automatically executed. AppleDouble metadata reconstruction, arbitrary archive links, encrypted archive creation and in-place archive mutation are not implemented by this browser.

## Verification

`ArchiveCatalogTests` uses small synthetic unencrypted, encrypted and traversal ZIP fixtures. It verifies real catalog projection, implicit folders, dates, selective extraction, correct/incorrect passwords, size/count/path limits, cancellation and throwing-reader cleanup. `ArchiveOperationTests` verifies that queued encrypted extraction creates a recoverable output without persisting the fixture password. `ArchiveViewSnapshotTests` renders the production browser in both appearances. The native matrix now requires 46 captures per macOS runner; the alpha assembler verifies both the main and supplemental archive capture manifests before packaging the review galleries.

This sheet is a native archive navigation workflow, not yet a virtual archive location integrated into every main file-manager operation. Live cross-process file promise transport, full crash write-ahead recovery and other remaining parity boundaries continue to be tracked separately.

Primary API references: https://github.com/libarchive/libarchive/blob/master/libarchive/archive.h and https://github.com/libarchive/libarchive/blob/master/libarchive/archive_entry.h
