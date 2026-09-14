#!/usr/bin/env python3
"""Produce the bundle manifest without interpolating shell text into XML."""
import base64
import os
from pathlib import Path
import plistlib
import re
import sys

version = os.environ.get("VERSION", "0.1.0")
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
    raise SystemExit("Invalid version")
key = os.environ.get("SPARKLE_PUBLIC_KEY", "").strip()
if key:
    try:
        if len(base64.b64decode(key, validate=True)) != 32:
            raise ValueError("Wrong public key length")
    except ValueError as error:
        raise SystemExit(f"Invalid SPARKLE_PUBLIC_KEY: {error}")
info = {
    "CFBundleExecutable": "MacExplorer",
    "CFBundleIdentifier": "com.wieslawsoltes.MacExplorer",
    "CFBundleName": "MacExplorer",
    "CFBundleDisplayName": "MacExplorer",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": version,
    "CFBundleIconFile": "AppIcon",
    "LSMinimumSystemVersion": "14.0",
    "NSHighResolutionCapable": True,
    "NSSupportsAutomaticTermination": False,
    "NSSupportsSuddenTermination": False,
    "NSHumanReadableCopyright": "Copyright © 2026 Wiesław Šoltés",
    "NSLocalNetworkUsageDescription": "Discover local SMB file servers so you can browse and connect to your shared folders.",
    "NSBonjourServices": ["_smb._tcp"],
    "CFBundleDocumentTypes": [{"CFBundleTypeName": "Folder", "CFBundleTypeRole": "Viewer", "LSHandlerRank": "Alternate", "LSItemContentTypes": ["public.folder", "public.directory"]}],
    "CFBundleURLTypes": [{"CFBundleURLName": "MacExplorer folder links", "CFBundleURLSchemes": ["macexplorer"], "CFBundleTypeRole": "Viewer"}],
    "NSServices": [{"NSMenuItem": {"default": "Open in MacExplorer"}, "NSMessage": "openInMacExplorer", "NSPortName": "MacExplorer", "NSSendTypes": ["public.file-url"], "NSRequiredContext": {}}],
    "SUFeedURL": "https://github.com/wieslawsoltes/MacExplorer/releases/latest/download/appcast.xml",
    "SUEnableAutomaticChecks": bool(key),
    "SUAutomaticallyUpdate": False,
    "SUVerifyUpdateBeforeExtraction": True,
    "SURequireSignedFeed": True,
    "SUEnableSystemProfiling": False,
    "SUEnableJavaScript": False,
}
if key:
    info["SUPublicEDKey"] = key
output = Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
with output.open("wb") as stream:
    plistlib.dump(info, stream, sort_keys=True)
