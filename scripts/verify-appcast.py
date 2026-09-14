#!/usr/bin/env python3
"""Verify feed metadata, archive size, bundled version/key, and the Ed25519 archive signature."""
from pathlib import Path
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

feed, archive, version, verifier = sys.argv[1:]
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
root = ET.parse(feed).getroot()
item = root.find("./channel/item")
if item is None:
    raise SystemExit("No appcast item")
enclosure = item.find("enclosure")
if enclosure is None:
    raise SystemExit("No appcast enclosure")
expected_url = f"https://github.com/wieslawsoltes/MacExplorer/releases/download/v{version}/MacExplorer-{version}-universal.zip"
if enclosure.get("url") != expected_url:
    raise SystemExit("Unexpected archive URL")
if int(enclosure.get("length", "-1")) != Path(archive).stat().st_size:
    raise SystemExit("Archive length does not match feed")
feed_version = item.findtext("sparkle:version", namespaces=ns) or enclosure.get("{" + ns["sparkle"] + "}version")
if feed_version != version:
    raise SystemExit("Feed version mismatch")
with zipfile.ZipFile(archive) as bundle:
    info = plistlib.loads(bundle.read("MacExplorer.app/Contents/Info.plist"))
if info.get("CFBundleVersion") != version or info.get("CFBundleIdentifier") != "com.wieslawsoltes.MacExplorer":
    raise SystemExit("Bundle identity/version mismatch")
if not info.get("SURequireSignedFeed") or not info.get("SUVerifyUpdateBeforeExtraction"):
    raise SystemExit("Required update verification settings are missing")
key = info.get("SUPublicEDKey")
signature = enclosure.get("{" + ns["sparkle"] + "}edSignature")
if not key or not signature:
    raise SystemExit("Missing archive signature or bundled verification key")
subprocess.run([verifier, key, signature, str(Path(archive).resolve())], check=True)
