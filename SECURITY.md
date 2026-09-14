# Security policy

MacExplorer is a filesystem tool. Errors can affect valuable data. Keep independent backups and exercise new builds on disposable fixtures before production use.

## Boundaries

The app is distributed outside the Mac App Store without the App Sandbox so it can operate on user-accessible filesystem locations. It still respects POSIX permissions, ACLs, TCC, protected volumes, and the operating system's security model. It does not install a privileged helper, invoke sudo, disable SIP/Gatekeeper, or grant itself Full Disk Access. The optional folder association and login item require deliberate user actions and have reversal controls.

No global keyboard hook or input logger is installed. Keyboard routing is a local application event monitor and excludes text editors. No browsing telemetry, server-password store, or remote-control service is included. System authentication is delegated to macOS.

## File operations

Copies/moves use explicit URL arguments, staged destinations, collision decisions, and replacement backups. Permanent deletion requires explicit confirmation and is not secure erase. Recovery validates recorded identity/size/modification metadata and does not overwrite occupied targets. Receipts store local filenames/paths and may therefore be sensitive; protect the user's account and disk. They are not uploaded.

The recovery model records completed steps, not all pre-crash intents. Abrupt termination can leave hidden `.MacExplorer-stage-*`, `.MacExplorer-rename-*`, `.MacExplorer-extract-*`, or `.MacExplorer-replaced-*` artifacts. Inspect them; do not blindly delete a stage that might contain the only remaining moved data. Cross-volume/network/provider behavior must be tested independently.

Archives are extracted to an isolated private staging directory with path/link/device rejection, duplicate rejection, entry and expanded-size caps. ZIP creation invokes ditto with an argument array, never an interpolated shell command. Archives requiring links, encryption, or special metadata restoration should be handled by a trusted specialized utility instead of weakening extraction controls.

## Update supply chain

Sparkle is exactly pinned. Updates require Ed25519 archive signatures and signed feeds; verification occurs before extraction. Public keys are embedded at build time; private keys are CI secrets or trusted Mac Keychain entries. Apple signing uses an ephemeral keychain and optional protected environments. Release jobs reject tags outside main's history and publish complete draft releases. GitHub Actions are pinned to commit SHAs and updated through reviewed dependency changes.

## Reporting

Do not post private paths, credentials, keys, or file contents in public issues. Use GitHub private vulnerability reporting when enabled, or contact the maintainer privately before publishing an exploit. Include the build commit, macOS version, filesystem/provider type, a minimal disposable reproduction, and whether any data was changed. Avoid testing suspected data-loss defects against original files.
