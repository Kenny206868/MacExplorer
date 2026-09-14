# Build, signing, release, and update operations

## Workflows

- **Source and design bundles** runs on main/PR changes and exports exact committed source plus the standalone design. It does not require a Mac runner or successful native compilation.
- **CI** checks repository scripts and calls the reusable **Universal macOS build** on a macOS 15 runner. That workflow resolves Sparkle, runs core tests, builds arm64/x86_64, packages ZIP/DMG, checks bundle/signature structure, and publishes artifacts.
- **Publish interactive design** uploads `Design/` to GitHub Pages, including a ZIP download. Enable **Settings → Pages → Source: GitHub Actions** once. A workflow cannot silently acquire repository administration permissions. If Pages is not enabled, the separate initial preview and downloadable design remain usable.
- **Release** runs for tags exactly matching `vMAJOR.MINOR.PATCH`. Build, optional Apple signing, and publishing are separate jobs. The final release is made public only after assets and the signed appcast are present in a draft.

## Sparkle keys (required for publishing)

Resolve the pinned Sparkle package on a trusted Mac:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.wieslawsoltes.MacExplorer
```

Consult the tool's `--help` for exporting a key for your CI environment. Keep the private key in your Keychain and an appropriately protected backup. Configure:

| Name | Kind | Meaning |
|---|---|---|
| `SPARKLE_PUBLIC_KEY` | Repository variable | Base64 32-byte Ed25519 public key embedded in MacExplorer.app |
| `SPARKLE_PRIVATE_KEY` | Secret in the `release` environment or repository | Corresponding exported private key accepted by Sparkle's `--ed-key-file -` |

Do not reuse ActivityMonitor's public key without intentionally managing its corresponding private key; this repository has no such access and includes no private key. Never commit private key material. The application refuses to start updater checks when its public key is absent. Release version preparation refuses publication without the public-key variable, and feed generation refuses a missing private key. Independent archive verification rejects a private/public key mismatch.

The package opts into `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction`. `generate_appcast` creates the feed and embedded release notes; no post-signing mutation of those bytes is permitted. The feed is served at `releases/latest/download/appcast.xml`; versioned archives are immutable release assets. Do not overwrite an already-published version. Delta updates are disabled initially; full universal ZIP updates are signed.

## Apple signing (recommended for public distribution)

Set repository variable `APPLE_SIGNING_ENABLED=true`. Configure these secrets in the protected **apple-signing** environment:

| Secret | Meaning |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Base64 Developer ID Application certificate and private key in P12 form |
| `DEVELOPER_ID_P12_PASSWORD` | P12 password |
| `DEVELOPER_ID_IDENTITY` | Full identity beginning `Developer ID Application:` |
| `APP_STORE_CONNECT_KEY_P8` | App Store Connect API private key contents |
| `APP_STORE_CONNECT_KEY_ID` | API key identifier |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer identifier |

Restrict the `apple-signing` and `release` environments to approved maintainers and release refs. Signing jobs verify the downloaded bundle before loading credentials, use an ephemeral keychain, never rebuild the app with Apple signing secrets loaded, sign embedded Sparkle code inside-out with hardened runtime, notarize/staple the app and DMG, and remove temporary secrets in an always-run cleanup step. Notarization diagnostic JSON excludes credentials and is preserved on failure.

Without `APPLE_SIGNING_ENABLED=true`, the release path is explicitly ad-hoc signed and not notarized. It still requires authenticated Sparkle signatures. Such a build is not presented as a notarized production app. Do not ask users to disable platform security as a substitute for signing.

## Publish a version

Review CI, update `.github/RELEASE_NOTES.md`, configure the keys/certificates above, and tag a reviewed commit that is reachable from main:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The pipeline accepts a draft retry but refuses to overwrite a public release. A version bump is required for an already-published version. Assets include universal ZIP/DMG, source ZIP, design ZIP, appcast, INSTALL, and checksums. Check the release job's actual status before announcing availability.

## Manual development packaging

```sh
VERSION=0.1.0 SPARKLE_PUBLIC_KEY='YOUR_PUBLIC_KEY' bash scripts/package.sh
bash scripts/verify-package.sh
```

Omit the key for a deliberately updater-disabled development build. Running the standalone executable does not exercise app-bundle Services, URL handlers, embedded-framework layout, Gatekeeper, or Sparkle installation.

## Operational checks before a production release

Use representative Apple Silicon and Intel machines; verify fresh install and older-to-newer signed updates; verify privacy denial and recovery; test local/APFS and remote/cross-volume operations; test corrupted/hostile archives, conflict/cancel flows, Unicode and case-only renames; verify VoiceOver, focus, and keyboard behavior. A green compile/test workflow is not a substitute for those filesystem and OS integration checks.
