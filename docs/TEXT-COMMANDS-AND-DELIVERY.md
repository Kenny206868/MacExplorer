# Text commands and delivery

The native field editor and the filesystem operation engine have independent undo domains. Edit-menu Cut, Copy, Paste, Select All, Undo and Redo first resolve the current NSTextView responder. Even an unsupported read-only text action remains owned by the editor: failure to send a text action must never cause a file mutation. This change preserves the existing focused-object observation, detached windows and tab commands.

## Interactive design

Published preview: https://dazzling-mote-5pufc49.shipstatic.com

This anonymous preview expires three days after deployment unless claimed. The ownership claim token is supplied privately to the requester rather than committed to this public repository. The preview renders `Design/index.html` from immutable commit `3910f0e7b329164a3466d047c29ef5abc8c9a202`. The design uses fictional browser data; native file operations are implemented in SwiftUI and the filesystem services, not the browser preview.

`.github/workflows/source.yml` produces standalone design and complete-source ZIPs. `.github/workflows/build.yml` produces native universal ARM64/Intel application ZIPs and DMGs. On 2026-09-14, CI run 34831246767 completed the core tests, universal app build and package/signature checks successfully for commit 3910f0e7b329164a3466d047c29ef5abc8c9a202. Subsequent commits must be associated with their own CI outcomes; this earlier success does not validate newer source changes.

A CI artifact is not a notarized public release. Developer ID, Apple notarization and Sparkle update signing require the separately documented deployment configuration in `docs/RELEASING.md`. No signing credential or automatic-update private key belongs in source control.
