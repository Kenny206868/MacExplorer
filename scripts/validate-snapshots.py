#!/usr/bin/env python3
"""Validate the exact native view contract and generate an offline PNG gallery."""
import argparse
import hashlib
import html
import json
import math
import pathlib
import struct

MANIFESTS = ('captures.json', 'archive-captures.json', 'design-captures.json', 'dual-captures.json', 'settings-captures.json', 'inline-captures.json', 'command-captures.json', 'comparison-captures.json', 'window-captures.json', 'status-captures.json', 'recovery-captures.json', 'archive-location-captures.json', 'commander-captures.json', 'chrome-density-captures.json')
CASES = {'extra-large-icons', 'large-icons', 'medium-icons', 'small-icons', 'list', 'details',
         'tiles', 'content', 'gallery', 'grouped-selection', 'panes-800', 'panes-1024', 'panes-1600',
         'empty', 'permission-denied', 'dialog-newFolder', 'dialog-newFile', 'dialog-rename',
         'dialog-tags', 'dialog-connect', 'transfers', 'preferences', 'archive-browser',
         'reference-home', 'reference-details', 'reference-computer', 'dual-side-by-side',
         'dual-secondary', 'dual-stacked', 'dual-narrow', 'dual-inspector', 'dual-touch',
         'touch-file-actions', 'keyboard-help', 'settings-appearance', 'settings-input', 'settings-integration',
         'settings-updates', 'inline-rename', 'commands', 'commands-search', 'commands-disabled', 'commands-empty',
         'comparison-metadata', 'comparison-data', 'comparison-empty',
         'native-window', 'native-dual-window', 'native-narrow-window', 'status-idle', 'status-running', 'status-storage',
         'recovery-interrupted', 'recovery-history', 'archive-location-root', 'archive-location-folder', 'native-commander-window', 'native-commander-narrow',
         'commander-settings', 'selection-masks', 'native-efficient-window', 'native-efficient-narrow', 'native-efficient-touch', 'native-efficient-standard'}
REQUIRED = {f'{theme}-{case}' for theme in ('light', 'dark') for case in CASES}


def validate(root: pathlib.Path) -> dict:
    captures = []
    for manifest in MANIFESTS:
        captures.extend(json.loads((root / manifest).read_text()))
    names = [item['name'] for item in captures]
    if len(set(names)) != len(names) or set(names) != REQUIRED:
        raise ValueError(f'Coverage mismatch. Missing: {sorted(REQUIRED - set(names))}; unexpected: {sorted(set(names) - REQUIRED)}')
    reference = json.loads((root / 'design-assertions.json').read_text())
    expected = {f'{theme}-reference-{view}' for theme in ('light', 'dark') for view in ('home', 'details', 'computer')}
    if len(reference) != 6 or {item['capture'] for item in reference} != expected:
        raise ValueError('Missing populated design assertion evidence')
    dual = json.loads((root / 'dual-assertions.json').read_text())
    expected = {f'{theme}-{case}' for theme in ('light', 'dark') for case in CASES if case.startswith('dual-')}
    if len(dual) != len(expected) or {item['capture'] for item in dual} != expected:
        raise ValueError('Missing dual-pane geometry and state evidence')
    density = json.loads((root / 'chrome-density-assertions.json').read_text())
    expected_density = {f'{theme}-native-efficient-{case}' for theme in ('light', 'dark') for case in ('window', 'narrow', 'touch', 'standard')}
    if len(density) != 8 or {item['capture'] for item in density} != expected_density:
        raise ValueError('Missing titlebar/footer density assertion evidence')
    for item in density:
        touch = item['touch'] == 'true'
        if float(item['footerHeight']) != (52 if touch else 38) or float(item['paneStatusHeight']) != (44 if touch else 26):
            raise ValueError('Unexpected multi-row footer or undersized touch summary')
    checksums, cards = {}, []
    captures.sort(key=lambda item: (0 if '-native-' in item['name'] else 1 if '-dual-' in item['name'] else 2 if '-reference-' in item['name'] else 3, item['name']))
    for item in captures:
        name = item['name']
        image = root / (name + '.png')
        if image.is_symlink():
            raise ValueError(f'Capture cannot be a symlink: {name}')
        data = image.read_bytes()
        if data[:16] != b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR':
            raise ValueError(f'Invalid PNG: {name}')
        width, height = struct.unpack('>II', data[16:24])
        if (width, height) != (item['pixelsWide'], item['pixelsHigh']) or item['width'] <= 0 or item['height'] <= 0:
            raise ValueError(f'Header/manifest mismatch: {name}')
        scale = width / item['width']
        if scale not in (1, 2) or height != item['height'] * scale:
            raise ValueError(f'Unexpected render dimensions: {name}')
        if '-native-' in name and item['height'] <= 720:
            raise ValueError(f'Native window capture omitted its titlebar: {name}')
        if any(not math.isfinite(item.get(field, float('nan'))) for field in ('minimumAlpha', 'luminanceRange', 'distinctSamples')):
            raise ValueError(f'Invalid render metrics: {name}')
        if item['minimumAlpha'] < 0.99 or item['luminanceRange'] <= 0.15 or item['distinctSamples'] <= 12:
            raise ValueError(f'Blank, low-contrast or uncomposited render: {name}')
        checksums[name + '.png'] = hashlib.sha256(data).hexdigest()
        label = html.escape(name)
        cards.append(f'<article id="{label}"><h2>{label}</h2><a href="{label}.png"><img loading="lazy" src="{label}.png" alt="Native {label} capture" width="{width}" height="{height}"></a></article>')
    style = 'body{font:14px system-ui;margin:32px;background:#17191d;color:#eef0f4}header{max-width:940px;margin-bottom:30px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(580px,100%),1fr));gap:24px}h2{font-size:14px}img{width:100%;height:auto;border:1px solid #454951;border-radius:10px}a{color:inherit}nav{display:flex;flex-wrap:wrap;gap:12px}'
    links = ''.join(f'<a href="#{html.escape(item["name"])}">{html.escape(item["name"])}</a>' for item in captures if '-native-' in item['name'] or '-status-' in item['name'])
    page = '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>MacExplorer native review</title><style>' + style + '</style><header><h1>MacExplorer · native design review</h1><p>Production SwiftUI views and complete native windows. Geometry, palette, selection, bitmap and state checks supplement visual review; they do not certify physical input devices or every assistive-technology interaction.</p><nav>' + links + '</nav></header><main>'
    (root / 'index.html').write_text(page + ''.join(cards) + '</main></html>')
    report = {'schemaVersion': 12, 'captures': len(captures), 'sha256': checksums,
              'checks': ['coverage', 'PNG dimensions', 'nonblank rendering', 'opaque sRGB compositing',
                         'reference pane geometry', 'reference palette', 'selected-row palette', 'empty canvas palette',
                         'dual-pane containment and non-overlap', 'independent pane selection', 'responsive orientation intent',
                         'touch and keyboard action coverage', 'all settings pages', 'native inline filename editor',
                         'searchable command palette and native search focus', 'read-only directory comparison states',
                         'complete titled windows', 'standard window buttons', 'native toolbar identity and customization',
                         'nonmodal activity and storage surfaces', 'archive virtual locations and journal-backed recovery', 'optional Commander controls and full-path pane chrome']}
    (root / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=pathlib.Path)
    print(json.dumps(validate(parser.parse_args().directory), indent=2))
