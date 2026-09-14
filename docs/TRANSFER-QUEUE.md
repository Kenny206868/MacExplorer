# Transfer queue, progress and recovery

## Copy workflow

A copy now inventories logical size with cancellable traversal, then uses `NativeFileCopy` inside a private `0700` staging directory. UI progress carries separate cumulative data bytes, logical completion, clone counts, an optional size estimate, successful top-level item count, phase, monotonic timestamp and delivery sequence. Native callbacks deliver at most ten normal updates per second; cancellation is checked independently at each callback. The final progress snapshot is part of the operation result, so completion cannot race and discard the last UI update.

The SwiftUI operation card renders measured throughput history, logical bytes completed, selected size, clone count and an estimated remaining time. Missing totals, insufficient samples, pauses, prompts and stale filesystem callbacks do not produce invented rates or ETAs. The chart retains at most 120 samples. Its data counter is what `copyfile` reports, not a physical disk/network utilization meter. Clone acceleration and sparse files can make logical progress diverge from copied data.

The serialized gate, queue, progress/cancel controls and durable recovery receipts are shared across all windows. A cancellation action is associated with its operation ID; it resumes only that operation's pending collision prompt. A queued job cannot dismiss an unrelated job's prompt. Skipped sources remain explicit in the result and UI, separate from completed sources used by cut-paste consumption.

## Commit and rollback safety

Before copying, the engine captures source and replacement identities. After copying it checks source identity again and checks any occupied replacement immediately before displacement. A newer destination is never silently substituted for the originally observed replacement. Source/destination hard-link identity is rejected for replacement. New fingerprints include device identity as well as inode, size and modification date; old receipts still decode because device identity is optional.

Partial copies are not installed under their requested names. The destination is committed only after a cooperative checkpoint. Replaced objects are retained as hidden sibling backups, never automatically purged. If creating the inverse receipt fails after installation, the engine first moves the newly installed object back to staging before restoring its predecessor. Every failed rollback step reports the retained path; nonempty staging directories are not silently recursively deleted when they might contain an unrecovered moved source.

These are application-level safeguards, not a filesystem-wide snapshot or an exclusive lock on uncoordinated external software. A directory root fingerprint is not a cryptographic digest of every descendant. Cross-volume moves still use FileManager and do not yet share byte-level copy callbacks; their system calls may not pause immediately. Archives likewise retain their existing operation boundaries. Recursive folder merge remains distinct from whole-folder replacement.

Integration fixtures cover a completed copy's logical total, cancellation after staged data exists, a destination modified during copying, cleanup of unused stage containers and truthful skipped-item counts. Native execution/build status is available in CI; source syntax checks are not macOS validation.
