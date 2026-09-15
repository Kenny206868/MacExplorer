# Native performance gate provenance

Optimized native execution and performance-report validation are separate CI steps. `measure-native-performance.py` records the exact Swift command, source SHA, process exit code and elapsed duration in `optimized-performance/execution.json`. It writes the complete native log directly to the artifact rather than conflating the Swift exit code with a console tee pipeline. A nonzero native process remains a failing step.

`validate-performance.py` checks the exact commit, successful process exit, schema/build identity, 2,000-file fixture, every workload's sample count, finite ordered quantiles, nonzero rendering counters and the existing mounted-row/localized-selection budgets. It writes `performance-validation.json` with the report's SHA-256. Missing evidence cannot be silently accepted. Unit tests exercise valid, stale, failed, nonfinite and missing-counter reports.

Both steps preserve their diagnostics in the native review artifact. This does not relax any native screenshot/state or performance structural gate. Timing values are CPU-side shared-runner diagnostics, not a physical input-to-photon, display refresh, GPU completion or assistive-technology certification.
