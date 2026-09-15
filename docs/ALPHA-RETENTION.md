# Preserving exact-commit alpha evidence

CI concurrency retains commits marked `[alpha]` while ordinary main integration runs collapse to the newest revision. The explicit queue-prioritization script must follow the same rule. GitHub truncates `display_title`, which can remove a marker at the end of a long commit title. Checking that display field alone incorrectly cancelled the first merged power-user milestone's main build despite its marker.

The prioritizer now inspects `head_commit.message`, matching `[alpha]` case-insensitively, and preserves runs without a full commit message rather than guessing. A marker visible in `display_title` remains a supplementary protection. Only older, unfinished, main-branch push runs of this repository's CI workflow are eligible for retirement. PRs, other workflows/repositories, newer runs and completed evidence remain untouched.

Regression tests cover a truncated long title with a marker only in the full commit, a marker in the commit body, unavailable metadata, malformed IDs, and the existing scope/ordering guards. Retrying or cancelling a run does not establish a successful release: publication still requires the exact main commit's successful native, crash-recovery and visual checks.
