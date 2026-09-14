#!/usr/bin/env python3
"""Syntax-check the self-contained design scripts without adding npm dependencies."""
from pathlib import Path
import re
import subprocess
import tempfile

html = Path("Design/index.html").read_text(encoding="utf-8")
assert "<!doctype html>" in html.lower(), "Missing HTML document"
assert 'lang="en"' in html, "Missing language declaration"
for index, script in enumerate(re.findall(r"<script\b[^>]*>(.*?)</script>", html, re.S | re.I)):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / f"design-{index}.js"
        path.write_text(script, encoding="utf-8")
        subprocess.run(["node", "--check", str(path)], check=True)
print("Interactive design JavaScript syntax is valid")
