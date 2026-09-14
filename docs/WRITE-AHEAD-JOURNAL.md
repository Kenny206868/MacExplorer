# Filesystem write-ahead recovery

`ExplorerJournal` is an isolated storage/recovery layer. It uses the system SQLite library with `journal_mode=WAL`, `synchronous=FULL`, `fullfsync=ON`, and `checkpoint_fullfsync=ON`. The settings are read back and checked, not assumed. A mode-0700 user-owned directory and a non-following, mode-0600, process-exclusive writer lock protect recovery files. Unknown schema versions and invalid files fail closed rather than replacing the database.

Each rename has a durable intent before the OS call, a durable applied record afterward, source/parent identities, and an exclusive destination operation. Parent descriptors anchor both endpoints; `renameatx_np(RENAME_EXCL)` on macOS enforces no clobber atomically. Completed staging data and parent directories are synchronized before installation. Cross-volume work must be explicitly staged; the rename primitive does not silently degrade into copy-and-delete.

Receipt checkpoints identify completed work that should survive interruption. Recovery reverses only mutations after that checkpoint, using inverse-intent/applied phases so recovery can itself be interrupted and resumed. New files at old paths, changed objects, and changed parents stop compensation without overwriting anything. Private staging is retained for inspection rather than recursively deleted based on a path recorded in a database. Recovery receipts also live inside the SQLite checkpoint, eliminating the rename-to-JSON-receipt gap.

Native Trash and permanent deletion are explicitly external/irreversible operations. An interrupted OS call whose destination/outcome was not returned is a manual-review record, not guessed or blindly retried. A permanent deletion cannot be made undoable by a journal. Storage hardware, remote filesystems and external concurrent changes remain separate from SQLite's consistency guarantees; these tests do not certify power-cut behavior on every device.

`RecoveryCrashProbe` is a test-only command-line product, not bundled with the application. Tests use real `_exit(73)` in a separate process with no cleanup/destructors at prepared/applied/checkpoint and inverse-recovery boundaries, then reopen the database and verify file contents and idempotence. The isolated journal tests also run on Linux against system SQLite, while macOS CI exercises the production platform adapter. The test fixtures never operate on user documents.

Primary references: https://www.sqlite.org/pragma.html#pragma_synchronous , https://www.sqlite.org/pragma.html#pragma_fullfsync , https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html .

This first journal commit introduces and tests the isolated component; application-operation integration is a separate commit, so presence of this file alone is not a claim that all existing operations are journaled.
