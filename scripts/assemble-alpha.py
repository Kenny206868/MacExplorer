#!/usr/bin/env python3
"""Assemble an exact-commit alpha from verified build and native-view artifacts.

No code in downloaded artifacts is executed. A visual report is accepted only
when its commit and every recorded PNG digest match the successful CI snapshot.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import zipfile


def digest(path: pathlib.Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def validate_views(root: pathlib.Path, commit: str) -> dict:
    if (root / 'COMMIT.txt').read_text().strip() != commit:
        raise ValueError(f'Native-view artifact is from another commit: {root}')
    report = json.loads((root / 'validation.json').read_text())
    captures = json.loads((root / 'captures.json').read_text())
    captures += json.loads((root / 'archive-captures.json').read_text())
    hashes = report.get('sha256', {})
    expected = {item['name'] + '.png' for item in captures}
    if not expected or len(expected) != len(captures) or set(hashes) != expected or report['captures'] != len(captures):
        raise ValueError(f'Incomplete visual report: {root}')
    for name, checksum in hashes.items():
        if pathlib.PurePosixPath(name).name != name or not name.endswith('.png'):
            raise ValueError('Unsafe artifact entry')
        if digest(root / name) != checksum:
            raise ValueError(f'Native capture checksum mismatch: {name}')
    if not (root / 'index.html').is_file():
        raise ValueError('Missing offline visual gallery')
    return {'captures': len(captures), 'checks': report['checks'],
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
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if head != commit:
        raise ValueError('Checkout is not the verified source commit')
    if output.exists():
        raise ValueError('Refusing to mix a release with pre-existing output')
    output.mkdir(parents=True)
    for line in (native / 'SHA256SUMS').read_text().splitlines():
        checksum, name = line.split(maxsplit=1)
        name = name.lstrip('*')
        if pathlib.PurePosixPath(name).name != name or digest(native / name) != checksum:
            raise ValueError(f'Native package checksum mismatch: {name}')
    packages = sorted(list(native.glob('*.zip')) + list(native.glob('*.dmg')))
    if len(packages) != 2 or not any(p.suffix == '.dmg' for p in packages):
        raise ValueError('Expected exactly one universal ZIP and one DMG')
    for path in packages + [native / 'INSTALL.md']:
        shutil.copy2(path, output / path.name)
    visual = {}
    for platform in ('macos-15-intel', 'macos-26'):
        directory = views / f'MacExplorer-native-views-{platform}'
        visual[platform] = validate_views(directory, commit)
        zip_tree(directory, output / f'MacExplorer-native-review-{platform}.zip')
    subprocess.run(['git', 'archive', '--format=zip', '--prefix=MacExplorer/',
                    f'--output={output / "MacExplorer-source.zip"}', commit], check=True)
    zip_tree(pathlib.Path('Design'), output / 'MacExplorer-design.zip')
    (output / 'COMMIT.txt').write_text(commit + '\n')
    (output / 'BUILD.txt').write_text(build + '\n')
    manifest = {'schemaVersion': 2, 'channel': 'alpha', 'alphaNumber': number,
                'sourceCommit': commit, 'buildURL': build, 'architectures': ['arm64', 'x86_64'],
                'minimumMacOS': '14.0', 'signing': 'ad-hoc', 'notarized': False,
                'automaticUpdateFeed': False, 'nativeVisualValidation': visual}
    manifest['sha256'] = {p.name: digest(p) for p in sorted(output.iterdir()) if p.is_file()}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (output / 'SHA256SUMS').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in sorted(output.iterdir()) if p.is_file()))
    notes = pathlib.Path('docs/ALPHA-NOTES.md').read_text() if pathlib.Path('docs/ALPHA-NOTES.md').is_file() else ''
    pathlib.Path('alpha-notes.md').write_text(
        f'# MacExplorer alpha {number}\n\nSource: `{commit}`. [Successful native CI]({build}).\n\n'
        '**Development build: ad-hoc signed, not Apple notarized. Read `INSTALL.md` before opening.**\n\n'
        'The native ZIP/DMG, source, interactive design and both native screenshot galleries match this exact commit. '
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
