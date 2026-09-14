# Automated development previews

`.github/workflows/preview.yml` publishes an immutable development prerelease after successful `CI` on a push to `main` in this repository. Failed runs, pull requests and other repositories cannot publish through that workflow. Each release tag is `preview-` followed by the full source commit SHA.

The workflow checks out that exact successful commit and downloads only its `MacExplorer-universal` artifact by workflow-run ID. It verifies the artifact's checksums before preparing native ZIP/DMG, matching source/design ZIPs, installation instructions, source commit, build URL, manifest and complete SHA-256 checksums. Publication is draft-first; an already published preview is not rewritten. Previews do not become the repository's production `latest` release.

These native previews are ad-hoc signed and not Apple notarized. They do not publish a Sparkle appcast, use Apple signing secrets, change update trust, or certify full Explorer/Finder parity. The explicit version-tag production workflow remains responsible for signed update archives/feed and optional Developer ID/notarization using separately configured owner credentials.

The successful-build link and `manifest.json` are the provenance authority for each asset. Never infer that a newer `main` commit compiled merely because an older preview exists. An app's internal preview version currently follows the reusable build's `0.1.0` input; the release's full SHA distinguishes development snapshots.
