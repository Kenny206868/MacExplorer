#!/usr/bin/env python3
"""Cancel only superseded, non-milestone CI runs belonging to this repository.

Milestone status comes from the full commit message, not GitHub's truncated
run display title. Missing commit metadata is preserved rather than guessed.
"""
from __future__ import annotations
import json
import os
import re
import urllib.error
import urllib.request


def superseded(runs: list[dict], repository: str, current_number: int, current_id: int) -> list[int]:
    result = set()
    for run in runs:
        commit = run.get('head_commit')
        message = commit.get('message') if isinstance(commit, dict) else None
        if (not isinstance(message, str) or not message.strip()
                or '[alpha]' in message.lower()
                or '[alpha]' in str(run.get('display_title', '')).lower()):
            continue
        if (run.get('id') == current_id or run.get('run_number', current_number) >= current_number
                or run.get('name') != 'CI' or run.get('event') != 'push' or run.get('head_branch') != 'main'
                or run.get('status') not in ('queued', 'in_progress', 'waiting', 'requested', 'pending')
                or run.get('head_repository', {}).get('full_name') != repository):
            continue
        if isinstance(run.get('id'), int) and not isinstance(run['id'], bool) and run['id'] > 0:
            result.add(run['id'])
    return sorted(result)


def main() -> None:
    repository = os.environ.get('GITHUB_REPOSITORY', '')
    token = os.environ.get('GH_TOKEN', '')
    if (not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository) or not token
            or os.environ.get('GITHUB_EVENT_NAME') != 'push' or os.environ.get('GITHUB_REF') != 'refs/heads/main'):
        raise ValueError('Expected an authenticated main-branch push')
    number, current = int(os.environ['GITHUB_RUN_NUMBER']), int(os.environ['GITHUB_RUN_ID'])
    base = f'https://api.github.com/repos/{repository}'

    def request(path: str, *, post: bool = False):
        req = urllib.request.Request(base + path, method='POST' if post else 'GET', data=b'' if post else None,
            headers={'Authorization': f'Bearer {token}', 'Accept': 'application/vnd.github+json',
                     'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'MacExplorer-CI'})
        with urllib.request.urlopen(req, timeout=15) as response:
            data = response.read()
            return json.loads(data) if data else None

    try:
        branch = request('/git/ref/heads/main')
        if branch['object']['sha'] != os.environ['GITHUB_SHA']:
            print('A newer commit owns main; leaving queue decisions to its run.')
            return
        runs = []
        for page in (1, 2):
            response = request(f'/actions/workflows/ci.yml/runs?branch=main&event=push&per_page=50&page={page}')
            runs += response.get('workflow_runs', [])
        for old in superseded(runs, repository, number, current):
            try:
                request(f'/actions/runs/{old}/cancel', post=True)
                print(f'Retired superseded integration run {old}.')
            except urllib.error.HTTPError as error:
                if error.code not in (409, 422):
                    print(f'::warning::Could not retire run {old}: HTTP {error.code}')
    except (urllib.error.URLError, TimeoutError, ValueError, KeyError) as error:
        print(f'::warning::Queue prioritization unavailable ({type(error).__name__}); native validation still runs.')


if __name__ == '__main__':
    main()
