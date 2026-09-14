# MacExplorer

**Explorer conventions. Native Mac expression.**

MacExplorer is a SwiftUI file manager for macOS 14 and later. Its application layout follows Windows Explorer: tabs, command bar, breadcrumb/address field, search, expandable navigation tree, file views, preview/details panes, and status bar. It uses macOS file APIs and native system integration rather than embedding a web interface in the application.

## Interactive design

Open [`Design/index.html`](Design/index.html) directly in a browser. It is a self-contained, light/dark, interactive sample-data prototype with folder navigation, tabs, sorting, selection, clipboard operations, undo/redo, context menus, and dialogs. It does **not** access the host filesystem. The initially published preview is https://arcane-shard-58g99m3.shipstatic.com (temporary hosting; the repository contains the durable source).

The **Source and design bundles** workflow publishes `MacExplorer-source.zip` and `MacExplorer-design.zip` for every main-branch change, independently of native compilation.

## Native application

The implementation includes actual filesystem browsing, nine view choices, per-folder layout/sort/group persistence, table column customization, Quick Access bookmarks, multiple windows and tabs, history, file URL drag/drop, copy/cut/paste, collision handling, staged transfers and replacement recovery, Trash and permanent deletion confirmation, rename and bulk rename, symbolic links, ZIP creation and guarded archive extraction, properties, tags, checksums, permissions, iCloud download controls, recursive/Spotlight search, Gallery, volume capacity/eject, Bonjour SMB discovery, OS server connection, Quick Look, sharing/AirDrop, Open With, Services, URL routing, and opt-in login/folder associations.

**This is not a claim of 100% Windows Explorer or Finder subsystem parity.** Windows-only shell extensions and filesystem features do not translate into public macOS APIs. Finder's desktop, protected system services, and other applications' open/save dialogs are not replaced. Review [capabilities and boundaries](docs/CAPABILITIES.md) before deploying against important files.

## Build

Install Xcode and its command-line tools, then open `Package.swift` in Xcode, or run:

```sh
swift package resolve
swift build
swift test
VERSION=0.1.0 bash scripts/package.sh
open dist/MacExplorer.app
```

The distributable bundle embeds Sparkle; running the loose SwiftPM executable is not a substitute for testing the installed app bundle. Release builds support Apple Silicon and Intel. This session does not claim a completed macOS build or validation run; CI exposes the actual status.

## Distribution and updates

CI, packaging, optional Developer ID signing/notarization, and Sparkle update publishing are based on the repository conventions of [ActivityMonitor](https://github.com/wieslawsoltes/ActivityMonitor). MacExplorer requires its **own** Sparkle key configuration. No Apple certificate or private update key is included or inferred from another project. Development builds without a configured public key keep update checks disabled.

See [installation](INSTALL.md), [user guide](docs/USER-GUIDE.md), [architecture](docs/ARCHITECTURE.md), [release operations](docs/RELEASING.md), [security](SECURITY.md), and [implementation log](docs/IMPLEMENTATION-LOG.md).

## License

MIT. Apple system frameworks and Sparkle retain their own licenses. No Microsoft or Apple artwork is redistributed; the native app uses system icons and SF Symbols at runtime.
