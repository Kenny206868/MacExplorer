# Fast iteration and immutable alpha checkpoints

Ordinary CI revisions use branch concurrency and cancel superseded integration runs. A main-branch commit whose message includes `[alpha]` has an immutable concurrency group and is retained while the next edit is pushed. Both kinds still publish an exact-commit alpha only when universal packaging, all core tests, both native visual jobs and repository checks succeed.

The small Linux prioritization job retires older non-milestone `CI` runs on this repository's main push track, including obsolete per-SHA groups left by the previous policy. It cannot cancel PRs, other workflows, other repositories, completed runs, newer commits or explicitly marked alpha milestones. Only this job receives Actions write permission; build and screenshot jobs remain read-only. The filtering function has regression tests. Failure to cancel a superseded run never bypasses validation.

This policy prevents frequent source commits from consuming the macOS runner queue indefinitely while preserving explicit alpha milestones and their native screenshot evidence.
