# Read-only folder comparison

Open a folder in each pane, clear any pane searches, and choose **Window → Compare Pane Folders…**, or search for `compare` in the command palette. The report compares the current folder level, not entire directory trees. Hidden-item visibility follows the workspace setting captured when the report is opened.

**Size & date** compares names, regular-file sizes and nanosecond modification times without reading file data. Its positive result is **Matching metadata**, not “identical”. **File data** reads regular files and compares their main data streams byte for byte. Its positive result is **Matching file data**, not a guarantee that resource forks, extended attributes, permissions or every filesystem property match.

A report distinguishes one-sided names, differing metadata/data, type conflicts, matching metadata/data, ambiguous names, unavailable files and items not compared. Exact-name and ignore-case matching are explicit choices. Canonically equivalent or folded names that map multiple entries to one key become ambiguous; no entry is silently overwritten or arbitrarily paired. Subdirectories, packages, symbolic links and special files are never traversed. Detected dataless files are not opened for content comparison. This does not invent provider-independent cloud behavior.

## Interaction

Filter by differences, first-only, second-only or unverified status; search the report by filename. Mark individual rows or mark visible differences, then choose **Select in First** or **Select in Second**. That action only highlights the corresponding paths in the original pane. Actual transfers use the existing Copy/Move controls, collision decisions and recovery engine afterward. There is no automatic synchronization, deletion, timestamp copying or silent replacement.

Results cannot be redirected by changing tabs, root folders, searches, hidden-item visibility or companion panes. Selection revalidates folder and file observations off MainActor, then re-checks the original window/pane before applying. Existing reload logic expands selected groups. Changing comparison options invalidates the old result. Cancellation never returns a success report and never rolls back or modifies files, because the comparison itself writes nothing.

## Filesystem contract

The engine uses pinned directory descriptors, `fstatat(..., AT_SYMLINK_NOFOLLOW)` metadata, and `openat` with `O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC` for regular-file data. It checks descriptor identity, type, size, nanosecond modification/change times and macOS flags before and after reading. `O_NONBLOCK` prevents a substituted FIFO from turning the regular-file path into a blocking pipe read; revalidation rejects the changed object. Symbolic links are reported, never followed as comparison edges.

Default resource limits are 25,000 entries per folder and 2 GiB of aggregate data reads across both sides, using two 128 KiB buffers. A listing limit stops the whole report rather than presenting an incomplete directory as complete. Data-budget exclusions remain **Not compared**. Reads and enumeration run off MainActor. Cancellation is cooperative between system calls; an unresponsive network filesystem can still delay a call. The report is a series of guarded observations, not an atomic filesystem snapshot or immunity to every possible concurrent mutation. A read may update filesystem access time.

The API definitions follow Apple's public Darwin interfaces: [open(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html) and [stat flags / fstatat](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/stat.h). No private Finder interfaces are used.

## Tests and native evidence

`DirectoryComparisonTests` covers false metadata matches, actual byte equality despite different dates, FIFO/link/folder exclusions, hidden and case policies, ambiguous names, read/list limits, changed files/root folders, symlink substitution and cancellation. The Foundation/POSIX implementation is also exercised in an isolated Linux harness; macOS CI additionally tests the Darwin flags and application integration.

`ComparisonViewTests` runs real fixture comparisons, checks report filtering and marks, rejects tab changes, and verifies that applying a one-sided result changes selection without transferring files. Six mandatory light/dark native captures show metadata, data and filtered-empty reports. They extend, rather than replace, the existing view/command/input contracts.
