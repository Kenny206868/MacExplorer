# Large-selection operation setup

Constructing a `FileJob` previously called `FileNames.independentRoots`, including repeated filesystem-backed parent checks before the job reached the serialized engine. A large selection could therefore stall the UI even when directory browsing itself was asynchronous.

A job now captures the requested URL array and metadata only. After acquiring the existing operation gate, the engine performs source planning on a bounded read lane. It resolves each candidate parent once, inspects the leaf without treating symlinks as traversable directories, sorts path components and removes covered descendants in a linear sweep. Duplicate aliases are identified at the canonical parent/leaf path, not by following a selected symlink to its target. Disjoint roots preserve input order. Cancellation is checked during scanning and sorting; missing or inaccessible inputs remain visible to ordinary per-item error reporting. Journaled mutation, collision, exclusive-install and source-identity checks remain authoritative after planning.

Completed cut-source reconciliation uses a component-prefix index rather than comparing every clipboard item to every completed root. This is a pure in-memory lookup; it does not change clipboard generation validation, reservation ownership or partial-completion semantics.

Tests cover parent/child duplicates, prefix-neighbor names, symlink objects versus targets, parent aliases, cancellation, nonfilesystem input rejection, 4,000 disjoint inputs, 20,000 coverage roots and actual queued copy behavior. An input-thread test verifies that job construction preserves raw intent rather than synchronously planning filesystem roots. Core tests and crash probes continue to run on macOS CI before publication.

The read executor cannot forcibly interrupt a blocked kernel call. Cross-pane confirmation snapshots and explicit property actions still perform their existing identity checks; this change is not a claim that every OS/provider interaction is latency-free.
