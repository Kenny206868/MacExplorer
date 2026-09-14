#!/usr/bin/env python3
"""Validate native render evidence against an explicit, versioned view contract."""
import argparse
import hashlib
import html
import json
import math
import pathlib
import struct

MANIFESTS = ('captures.json', 'archive-captures.json', 'design-captures.json', 'dual-captures.json')
CASES = {'extra-large-icons', 'large-icons', 'medium-icons', 'small-icons', 'list', 'details',
         'tiles', 'content', 'gallery', 'grouped-selection', 'panes-800', 'panes-1024', 'panes-1600',
         'empty', 'permission-denied', 'dialog-newFolder', 'dialog-newFile', 'dialog-rename',
         'dialog-tags', 'dialog-connect', 'transfers', 'preferences', 'archive-browser',
         'reference-home', 'reference-details', 'reference-computer', 'dual-side-by-side',
         'dual-secondary', 'dual-stacked', 'dual-narrow', 'dual-inspector', 'dual-touch',
         'touch-file-actions', 'keyboard-help'}
REQUIRED = {f'{theme}-{case}' for theme in ('light', 'dark') for case in CASES}


def validate(root: pathlib.Path) -> dict:
    captures = []
    for manifest in MANIFESTS:
        captures += json.loads((root / manifest).read_text())
    names = [item['name'] for item in captures]
    if len(set(names)) != len(names) or set(names) != REQUIRED:
        raise ValueError(f'Coverage mismatch. Missing: {sorted(REQUIRED - set(names))}; unexpected: {sorted(set(names) - REQUIRED)}')
    reference = json.loads((root / 'design-assertions.json').read_text())
    expected_reference = {f'{theme}-reference-{view}' for theme in ('light', 'dark') for view in ('home', 'details', 'computer')}
    if len(reference) != 6 or {item['capture'] for item in reference} != expected_reference:
        raise ValueError('Missing populated design assertion evidence')
    dual = json.loads((root / 'dual-assertions.json').read_text())
    expected_dual = {name for name in REQUIRED if '-dual-' in name}
    if len(dual) != len(expected_dual) or {item['capture'] for item in dual} != expected_dual:
        raise ValueError('Missing dual-pane geometry and state evidence')
    checksums, cards = {}, []
    captures.sort(key=lambda item: (0 if '-dual-' in item['name'] else 1 if '-reference-' in item['name'] else 2, item['name']))
    for item in captures:
        name = item['name']
        image_path = root / (name + '.png')
        if image_path.is_symlink():
            raise ValueError(f'Capture cannot be a symlink: {name}')
        data = image_path.read_bytes()
        if data[:16] != b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR':
            raise ValueError(f'Invalid PNG: {name}')
        width, height = struct.unpack('>II', data[16:24])
        if (width, height) != (item['pixelsWide'], item['pixelsHigh']) or item['width'] <= 0 or item['height'] <= 0:
            raise ValueError(f'Header/manifest mismatch: {name}')
        scale = width / item['width']
        if scale not in (1, 2) or height != item['height'] * scale:
            raise ValueError(f'Unexpected render dimensions: {name}')
        for field in ('minimumAlpha', 'luminanceRange', 'distinctSamples'):
            if not math.isfinite(item.get(field, float('nan'))):
                raise ValueError(f'Invalid render metric: {name}: {field}')
        if item['minimumAlpha'] < 0.99 or item['luminanceRange'] <= 0.15 or item['distinctSamples'] <= 12:
            raise ValueError(f'Blank, low-contrast or uncomposited render: {name}')
        checksums[name + '.png'] = hashlib.sha256(data).hexdigest()
        label = html.escape(name)
        cards.append(f'<article data-name="{label}"><h2>{label}</h2><a href="{label}.png"><img loading="lazy" src="{label}.png" alt="Native {label} capture" width="{width}" height="{height}"></a></article>')
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>MacExplorer native review</title><style>body{font:14px system-ui;margin:32px;background:#17191d;color:#eef0f4}header{max-width:940px;margin-bottom:30px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(580px,100%),1fr));gap:24px}h2{font-size:14px}img{width:100%;height:auto;border:1px solid #454951;border-radius:10px}input{font:inherit;padding:12px;width:min(500px,85%);border-radius:8px;border:1px solid #596273;background:#252930;color:inherit}a{color:inherit}[hidden]{display:none}</style><header><h1>MacExplorer · native design review</h1><p>Actual SwiftUI views rendered by macOS, including independent dual browsers, touch density and keyboard help. Geometry, palette, selection, bitmap and state checks supplement visual review; they do not certify all interactions or physical input devices.</p><input id="filter" type="search" aria-label="Filter captures" placeholder="Filter: dual, touch, home, dark…"></header><main>'''
    script = '''<script>document.getElementById('filter').addEventListener('input',e=>{const q=e.target.value.toLowerCase();for(const card of document.querySelectorAll('article'))card.hidden=!card.dataset.name.includes(q)})</script>'''
    (root / 'index.html').write_text(page + ''.join(cards) + '</main>' + script + '</html>')
    report = {'schemaVersion': 3, 'captures': len(captures), 'sha256': checksums,
              'checks': ['coverage', 'PNG dimensions', 'nonblank rendering', 'opaque sRGB compositing',
                         'reference pane/chrome geometry', 'reference palette', 'selected-row palette',
                         'empty canvas palette', 'dual-pane containment and non-overlap', 'independent pane selection',
                         'responsive orientation intent', 'touch and keyboard action coverage']}
    (root / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=pathlib.Path)
    print(json.dumps(validate(parser.parse_args().directory), indent=2))
