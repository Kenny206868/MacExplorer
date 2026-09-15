#!/usr/bin/env python3
"""Fail closed on incomplete, stale or malformed native performance evidence."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import pathlib
import re

SAMPLES = {'selectionLayout': 12, 'scrollLayout': 16, 'continuousScrollLayout': 120, 'keyDispatch': 200}


def validate(root: pathlib.Path, commit: str) -> dict:
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Expected the exact 40-character source commit')
    if (root / 'COMMIT.txt').read_text().strip() != commit:
        raise ValueError('Performance evidence belongs to another commit')
    path = root / 'large-directory-performance.json'
    if path.is_symlink() or path.stat().st_size > 64 * 1024:
        raise ValueError('Unsafe or oversized performance report')
    data = path.read_bytes()
    report = json.loads(data)
    if report.get('schemaVersion') != 2 or report.get('buildConfiguration') != 'release-instrumented':
        raise ValueError('Expected version 2 optimized, instrumented evidence')
    if type(report.get('entries')) is not int or report['entries'] != 2000:
        raise ValueError('The 2,000-file native fixture did not run')
    for field, ceiling in [('selectionBodyEvaluations', 240), ('maximumLiveRowAnchors', 500)]:
        value = report.get(field)
        if type(value) is not int or not 0 < value < ceiling:
            raise ValueError(f'Missing counters or exceeded structural budget: {field}={value!r}')
    for phase, samples in SAMPLES.items():
        timing = report.get(phase, {})
        if type(timing.get('samples')) is not int or timing['samples'] != samples:
            raise ValueError(f'Missing native workload samples: {phase}')
        values = [timing.get(field) for field in ('medianMilliseconds', 'p95Milliseconds', 'maximumMilliseconds')]
        if any(type(value) not in (int, float) or not math.isfinite(value) or value < 0 for value in values):
            raise ValueError(f'Invalid timing data: {phase}')
        if values != sorted(values):
            raise ValueError(f'Inconsistent timing quantiles: {phase}')
    execution = json.loads((root / 'execution.json').read_text())
    if execution.get('sourceCommit') != commit or execution.get('testExitCode') != 0:
        raise ValueError('The exact optimized test process did not exit successfully')
    evidence = {'schemaVersion': 1, 'sourceCommit': commit, 'status': 'passed',
                'reportSHA256': hashlib.sha256(data).hexdigest(),
                'checks': ['optimized build', 'exact commit', 'successful test process', 'all workload sample counts',
                           'finite ordered timings', 'lazy row budget', 'localized selection budget'],
                'timingScope': 'CPU-side test diagnostics, not physical frame cadence or input-to-photon latency'}
    (root / 'performance-validation.json').write_text(json.dumps(evidence, indent=2) + '\n')
    return evidence


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=pathlib.Path)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    print(json.dumps(validate(args.directory, args.commit), indent=2))
