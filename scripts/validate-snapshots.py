#!/usr/bin/env python3
"""Validate native coverage, dimensions and compositing; build an offline gallery."""
import argparse
import hashlib
import html
import json
import pathlib
import struct


def validate(root: pathlib.Path) -> dict:
    captures = json.loads((root / 'captures.json').read_text())
    captures += json.loads((root / 'archive-captures.json').read_text())
    expected = {'extra-large-icons', 'large-icons', 'medium-icons', 'small-icons',
                'list', 'details', 'tiles', 'content', 'gallery', 'grouped-selection',
                'panes-800', 'panes-1024', 'panes-1600', 'empty', 'permission-denied',
                'dialog-newFolder', 'dialog-newFile', 'dialog-rename', 'dialog-tags',
                'dialog-connect', 'transfers', 'preferences', 'archive-browser'}
    required = {f'{theme}-{case}' for theme in ('light', 'dark') for case in expected}
    names = [item['name'] for item in captures]
    if len(set(names)) != len(names) or set(names) != required:
        raise ValueError(f'Coverage mismatch. Missing: {sorted(required - set(names))}; unexpected: {sorted(set(names) - required)}')
    checksums = {}
    cards = []
    for item in captures:
        name = item['name']
        data = (root / (name + '.png')).read_bytes()
        if data[:16] != b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR':
            raise ValueError(f'Invalid PNG: {name}')
        width, height = struct.unpack('>II', data[16:24])
        if (width, height) != (item['pixelsWide'], item['pixelsHigh']):
            raise ValueError(f'Header/manifest mismatch: {name}')
        scale = width / item['width']
        if scale not in (1, 2) or height != item['height'] * scale:
            raise ValueError(f'Unexpected render dimensions: {name}')
        if item.get('minimumAlpha', 0) < 0.99:
            raise ValueError(f'Uncomposited transparent render: {name}')
        if item['luminanceRange'] <= 0.15 or item['distinctSamples'] <= 12:
            raise ValueError(f'Blank or incomplete render: {name}')
        checksums[name + '.png'] = hashlib.sha256(data).hexdigest()
        label = html.escape(name)
        cards.append(f'<article><h2>{label}</h2><a href="{label}.png"><img loading="lazy" src="{label}.png" alt="Native {label} capture" width="{width}" height="{height}"></a></article>')
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>MacExplorer native visual review</title><style>body{font:14px system-ui;margin:32px;background:#17191d;color:#eef0f4}header{max-width:900px;margin-bottom:30px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(500px,100%),1fr));gap:24px}article{min-width:0}h2{font-size:14px}img{width:100%;height:auto;border:1px solid #454951;border-radius:10px}a{color:inherit}</style><header><h1>MacExplorer · native visual review</h1><p>Production SwiftUI views rendered by macOS AppKit. Fixed fixture data, light/dark themes and responsive widths. Click a capture for full resolution. This report checks coverage, dimensions, compositing and nonblank rendering; it is not a pixel-baseline or accessibility certification.</p></header><main>'''
    (root / 'index.html').write_text(page + ''.join(cards) + '</main></html>')
    report = {'schemaVersion': 1, 'captures': len(captures), 'sha256': checksums, 'checks': ['coverage', 'PNG dimensions', 'nonblank rendering', 'opaque compositing']}
    (root / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=pathlib.Path)
    args = parser.parse_args()
    print(json.dumps(validate(args.directory), indent=2))
