# Rename-cycle recovery and transfer completion

## Reversible batch rename

A batch can contain swaps or longer cycles. Applying the inverse as a sequence of moves is incorrect: the first destination is still occupied by another member. New receipts therefore carry an optional `renameBatch` flag. It is optional to preserve decoding of older receipts.

Undo validates every recorded file fingerprint and parent directory before mutation, then feeds the entire inverse mapping through the same two-phase staging/install algorithm used for the original rename. The generated receipt is itself a rename batch, so Redo preserves cycle semantics. The engine serialization gate is acquired once; its synchronous helper never recursively awaits the same gate.

Rollback failures report the original/staging paths instead of silently implying that recovery completed. A receipt still is not a backup of file content or a complete write-ahead crash journal. External modifications or lost volumes can prevent reversal. Existing v1 receipts without the batch marker retain their previous sequential behavior.

## Exact completed-source reporting

`FileJobResult.completedSources` reports sources whose individual operations actually finished. It is independent of the existence of a source path and is populated before recovery-log persistence, because a logging failure does not undo an already completed transfer. Clipboard reconciliation can consequently retain cut items on cancellation, skip, and partial failure without inferring success from missing paths.

Disposable-fixture regression cases cover a cancelled move, a successful move, and a three-node rename cycle through Undo and Redo. Committed tests do not imply a completed macOS test run; use the corresponding CI result.
