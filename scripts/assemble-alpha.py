#!/usr/bin/env python3
"""Assemble exact-commit alphas from native packages and verified design evidence."""
from __future__ import annotations
import argparse
import hashlib
import json
import pathlib
import re
import runpy
import shutil
import subprocess
import zipfile


def digest(path: pathlib.Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def validate_views(root: pathlib.Path, commit: str) -> dict:
    if (root / 'COMMIT.txt').read_text().strip() != commit:
        raise ValueError(f'Native-view artifact is from another commit: {root}')
    recorded = json.loads((root / 'validation.json').read_text())
    # Re-run the exact commit's contract; never infer complete coverage merely
    # because every entry in an incomplete manifest happens to have a PNG.
    validator = runpy.run_path(str(pathlib.Path(__file__).with_name('validate-snapshots.py')))['validate']
    verified = validator(root)
    if recorded != verified:
        raise ValueError(f'Native review contract or checksum mismatch: {root}')
    return {'captures': verified['captures'], 'checks': verified['checks'],
            'toolchain': (root / 'toolchain.txt').read_text().strip()}


def zip_tree(source: pathlib.Path, target: pathlib.Path) -> None:
    with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(source.rglob('*')):
            if path.is_symlink():
                raise ValueError(f'Unexpected symlink in review artifact: {path}')
            if path.is_file():
                archive.write(path, path.relative_to(source).as_posix())


def assemble(native: pathlib.Path, views: pathlib.Path, output: pathlib.Path, commit: str, build: str, number: int) -> None:
    if not re.fullmatch(r'[0-9a-f]{40}', commit) or number < 1:
        raise ValueError('Invalid build identity')
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() != commit:
        raise ValueError('Checkout is not the verified source commit')
    if output.exists():
        raise ValueError('Refusing to mix a release with pre-existing output')
    expected_native = {}
    for line in (native / 'SHA256SUMS').read_text().splitlines():
        checksum, name = line.split(maxsplit=1); name = name.lstrip('*')
        if pathlib.PurePosixPath(name).name != name or not re.fullmatch(r'[0-9a-f]{64}', checksum):
            raise ValueError('Malformed native checksum manifest')
        if name in expected_native or digest(native / name) != checksum:
            raise ValueError(f'Native package checksum mismatch: {name}')
        expected_native[name] = checksum
    packages = sorted(list(native.glob('*.zip')) + list(native.glob('*.dmg')))
    if len(packages) != 2 or not any(p.suffix == '.dmg' for p in packages) or any(p.name not in expected_native for p in packages):
        raise ValueError('Expected checksummed universal ZIP and DMG')
    visual = {}
    for platform in ('macos-15-intel', 'macos-26'):
        visual[platform] = validate_views(views / f'MacExplorer-native-views-{platform}', commit)
    output.mkdir(parents=True)
    for path in packages + [native / 'INSTALL.md']:
        shutil.copy2(path, output / path.name)
    for platform in visual:
        zip_tree(views / f'MacExplorer-native-views-{platform}', output / f'MacExplorer-native-review-{platform}.zip')
    subprocess.run(['git', 'archive', '--format=zip', '--prefix=MacExplorer/',
                    f'--output={output / "MacExplorer-source.zip"}', commit], check=True)
    zip_tree(pathlib.Path('Design'), output / 'MacExplorer-design.zip')
    (output / 'COMMIT.txt').write_text(commit + '\n'); (output / 'BUILD.txt').write_text(build + '\n')
    manifest = {'schemaVersion': 3, 'channel': 'alpha', 'alphaNumber': number,
                'sourceCommit': commit, 'buildURL': build, 'architectures': ['arm64', 'x86_64'],
                'minimumMacOS': '14.0', 'signing': 'ad-hoc', 'notarized': False,
                'automaticUpdateFeed': False, 'nativeVisualValidation': visual}
    manifest['sha256'] = {p.name: digest(p) for p in sorted(output.iterdir()) if p.is_file()}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (output / 'SHA256SUMS').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in sorted(output.iterdir()) if p.is_file()))
    notes = pathlib.Path('docs/ALPHA-NOTES.md').read_text() if pathlib.Path('docs/ALPHA-NOTES.md').is_file() else ''
    coverage = ', '.join(f'{platform}: {value["captures"]} captures' for platform, value in visual.items())
    pathlib.Path('alpha-notes.md').write_text(
        f'# MacExplorer alpha {number}\n\nSource: `{commit}`. [Successful native CI]({build}).\n\n'
        '**Development build: ad-hoc signed, not Apple notarized. Read `INSTALL.md` before opening.**\n\n'
        f'The native ZIP/DMG, source, interactive design and screenshot galleries match this exact commit. Native coverage: {coverage}. '
        '`manifest.json` records toolchains, view coverage and SHA-256 checksums. '
        'Native UI checks are not a claim of complete Explorer parity or an accessibility certification.\n\n'
        'This alpha does not modify the signed production Sparkle feed or the stable latest release.\n\n' + notes)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--native', type=pathlib.Path, required=True)
    parser.add_argument('--views', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--number', type=int, required=True)
    args = parser.parse_args()
    assemble(args.native, args.views, args.output, args.commit, args.build, args.number)
