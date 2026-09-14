# Installing MacExplorer

## Requirements

macOS 14 Sonoma or later, on Apple Silicon or Intel. Install the complete `.app` bundle, not its internal executable. Local builds require Xcode with command-line tools; libarchive, Quick Look, AppKit, and the other operating-system frameworks are supplied by macOS.

## Install a distribution

Download the universal DMG or ZIP and `SHA256SUMS` from the same release. Check the checksum before opening the download:

```sh
shasum -a 256 -c SHA256SUMS
```

The full checksum manifest covers all assets; missing assets are reported when only some files were downloaded. Compare the hash for the particular asset you downloaded, or download every listed asset for a full manifest check.

Open the DMG, then drag **MacExplorer.app** to **Applications**. For a ZIP, extract the app and move it to **Applications**. Eject the DMG before launching the installed app. This avoids running the updater from a read-only disk image.

Read the signing status in the release and at the beginning of the artifact's `INSTALL.md`. A development build is ad-hoc signed and is **not Apple notarized**. A notarized release is explicitly labeled as such. Do not disable Gatekeeper or System Integrity Protection to install this application. Build from source with your own signing configuration when evaluating an unnotarized build.

## First launch

MacExplorer does not request administrator privileges, install a privileged helper, or silently replace Finder. It starts at Home and shows your actual pinned folders. Recent files initially remain empty; they are populated by opening documents through MacExplorer.

macOS may request access to Desktop, Documents, Downloads, removable storage, network volumes, or local-network discovery when those capabilities are used. Denied access is reported, not bypassed. Full Disk Access is optional and must be granted by the user in System Settings for protected locations. MacExplorer cannot grant that permission to itself.

Use **MacExplorer → Settings → Integration** to opt into opening folders with MacExplorer or launching at login. Restore Finder using the corresponding button. Folder-type association changes do not replace the desktop, Dock, private Finder services, or the open/save panels of other applications.

## Updates

Release builds use a MacExplorer-specific Sparkle public key and an HTTPS signed appcast. Use **Check for Updates…** or enable automatic checks. Development builds without the public key disable updater startup. Installing an app without that key does not make it an automatically updatable release later; install a correctly configured distribution.

## Remove

Restore Finder as the folder handler and turn off the login item before removing MacExplorer.app. Preferences are under the `com.wieslawsoltes.MacExplorer` defaults domain. Recovery receipts are in `~/Library/Application Support/MacExplorer/Recovery/`.

Do not delete recovery receipts or `.MacExplorer-replaced-*` files while you still need to restore replaced items. Inspect those backups before manual cleanup. Removing the app does not delete your files or replacement backups.
