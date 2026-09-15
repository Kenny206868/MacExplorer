#!/usr/bin/env python3
"""Run the optimized native test and preserve its exact exit status and log."""
from __future__ import annotations
import json
import os
import pathlib
import re
import subprocess
import sys
import time


def main() -> int:
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if not re.fullmatch(r'[0-9a-f]{40}', commit) or commit != os.environ.get('GITHUB_SHA'):
        raise ValueError('Performance checkout must match the CI source commit')
    output = pathlib.Path(os.environ['MACEXPLORER_SNAPSHOT_DIR'])
    output.mkdir(parents=True, exist_ok=True)
    for name in ('execution.json', 'performance-validation.json', 'large-directory-performance.json'):
        (output / name).unlink(missing_ok=True)
    (output / 'COMMIT.txt').write_text(commit + '\n')
    # The selected workload is XCTestCase. Do not launch an additional empty
    # Swift Testing run whose discovery/exit path is outside this benchmark.
    command = ['swift', 'test', '--configuration', 'release', '--enable-xctest',
               '--disable-swift-testing', '-Xswiftc', '-DMACEXPLORER_PERFORMANCE_DIAGNOSTICS',
               '--filter', 'LargeDirectoryScrollTests']
    started = time.monotonic()
    status = 125
    try:
        # Write directly to the artifact. A tee or console-pipe failure must not
        # be confused with the native test's exit code. CI displays the tail.
        with (output / 'test.log').open('wb') as log:
            status = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False).returncode
    finally:
        evidence = {'schemaVersion': 1, 'sourceCommit': commit, 'command': command,
                    'testFramework': 'XCTest', 'testExitCode': status,
                    'elapsedSeconds': time.monotonic() - started}
        (output / 'execution.json').write_text(json.dumps(evidence, indent=2) + '\n')
        print(json.dumps(evidence, indent=2), flush=True)
        log = output / 'test.log'
        if log.exists():
            with log.open('rb') as stream:
                stream.seek(max(0, log.stat().st_size - 24000))
                print(stream.read().decode('utf-8', errors='replace'), flush=True)
    return status if 0 <= status <= 255 else 1


if __name__ == '__main__':
    sys.exit(main())
