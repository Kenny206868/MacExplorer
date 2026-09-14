# Native copy and transfer telemetry

`NativeFileCopy` wraps the public Darwin `copyfile` API. The caller supplies an unoccupied private staging destination and owns cleanup. The flags request data, POSIX metadata, ACLs, extended attributes, sparse-copy fallback, recursive enumeration, exclusive destination creation and no symlink following. APFS cloning is attempted by default and can be disabled for deterministic byte-copy fixtures. No quarantine flags are removed and setuid preservation is not enabled.

A retained Swift context lives for exactly the synchronous C invocation; the callback cannot throw across the ABI. Write errors quit rather than being retried indefinitely. Cooperative pause/cancellation checks run at native data callbacks and recursive boundaries. UI delivery is throttled to ten updates per second, independently of cancellation checks. The enclosing filesystem transaction must checkpoint again before installing a staged object.

Logical completion and copied data bytes are distinct: a successful clone can advance logical completion without a data callback. The speed estimator consumes data bytes only, is based on monotonic timestamps, rejects out-of-order samples, resets its baseline around pauses, uses time-weighted smoothing and retains at most 120 samples. A missing size/rate yields an indeterminate ETA rather than a fabricated number. Size enumeration is cancellable and refuses to present an incomplete traversal as an exact total.

The native backend and its fixtures are committed before integration into the transfer queue. This document does not claim a byte graph is already wired by this commit. `copyfile` is not a filesystem snapshot, may wait inside a kernel/network operation between callbacks, and recursive copies do not preserve hard-link relationships. The OS and target filesystem determine which metadata operations are supported.

Primary API contracts:
- https://github.com/apple-oss-distributions/copyfile/blob/main/copyfile.h
- https://github.com/apple-oss-distributions/copyfile/blob/main/copyfile.3

Fixtures cover byte content, POSIX mode/time, extended attributes, directory symlink loops, no-overwrite behavior, cancellation after data starts, pre-cancellation, throughput/ETA, pause baselines, stale samples and bounded history. CI results, not committed tests alone, establish execution status.
