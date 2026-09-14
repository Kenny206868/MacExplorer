# Native screenshot review follow-through

The published design milestone is Alpha 73 (`6c1252df58b369c498f645a4103cf5711579ff46`): both macOS jobs, universal packaging, core checks and the exact-commit publication pipeline passed. The following inline-rename candidate (`8ec70ce8820b014fae121837855c6699902a7a9b`) passed macOS 26 and universal packaging but failed the Intel snapshot assertion for native field-editor focus. It was not promoted as a successful release.

## Corrections from reviewing native PNGs

- Archive browsing now disables native table zebra backgrounds, uses the shared canvas/chrome/dividers, and aligns action buttons with the rest of the app. The screenshot test inspects the actual NSTableView flag; no fake empty file rows are rendered.
- Settings gives its full navigation titles enough horizontal room without reducing content width. Updates shows the application's installed version only for an app bundle, not the XCTest harness's unrelated version.
- Compact combined auxiliary panes hide the redundant visual picker caption while keeping the accessible label.
- Grouped-selection fixtures use the listing's canonical URLs and assert the actual selected FileEntry count, rather than assuming four raw URLs are four resolved files.
- The snapshot renderer performs initial layout and drains native focus work after lazy row layout before checking the actual field editor. It does not set a first responder to make the test pass. Failed state checks retain the rendered PNG for diagnosis.

These are source changes awaiting the subsequent exact-commit CI result. The release manifest, not this document, is the authority for the published build's platform tests and capture count. Hardware drag/gesture/touch behavior and a complete VoiceOver audit remain separate evaluation work.
