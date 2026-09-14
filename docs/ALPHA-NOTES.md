# Alpha development track

Alpha snapshots are published from successful `main` CI after the universal app, core tests, native integration tests, and both macOS visual matrices pass. Each release includes the two native screenshot galleries, source, interactive design, ZIP/DMG, toolchain provenance and checksums. No production signing credentials are used.

The current track includes recursive copy/move merging with partial-completion recovery, measured transfer graphs, Gallery previews, a redesigned inspector, responsive auxiliary panes, indexed listing/selection projections, native promise imports/exports and marquee edge scrolling. Further parity work is tracked explicitly in `docs/CAPABILITIES.md`; an alpha is not a declaration that every Windows or Finder feature is complete.

Application signatures are ad-hoc. Developer ID/notarization and the production Sparkle feed remain separate owner-configured release steps. Installing an alpha never silently opts the user into an unsigned auto-update channel.
