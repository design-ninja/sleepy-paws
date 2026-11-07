#!/usr/bin/env python3
"""Prints one CHANGELOG.md section as small, styled HTML for Sparkle's update window.

Usage: script/release_notes.py <version>
"""
import html
import re
import sys
from pathlib import Path

version = sys.argv[1]
text = Path(__file__).resolve().parent.parent.joinpath("CHANGELOG.md").read_text()
match = re.search(rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## \[|^\[[^\]]+\]: )", text, re.S | re.M)
if not match:
    sys.exit(f"No ## [{version}] section in CHANGELOG.md")


def inline(line: str) -> str:
    line = html.escape(line)
    line = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", line)
    line = re.sub(r"\*(.+?)\*", r"<i>\1</i>", line)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", line)


parts, item, in_list = [], None, False


def flush():
    global item
    if item is not None:
        parts.append(f"<li>{inline(item)}</li>")
        item = None


for raw in match.group(1).splitlines():
    line = raw.rstrip()
    if line.startswith("- "):
        flush()
        if not in_list:
            parts.append("<ul>")
            in_list = True
        item = line[2:]
    elif line.startswith("  ") and item is not None:
        item += " " + line.strip()
    else:
        flush()
        if in_list:
            parts.append("</ul>")
            in_list = False
        if line.startswith("### "):
            parts.append(f"<h3>{inline(line[4:])}</h3>")
        elif line:
            parts.append(f"<p>{inline(line)}</p>")
flush()
if in_list:
    parts.append("</ul>")

style = (
    "body{font:13px -apple-system,sans-serif;margin:12px 16px;color:#222}"
    "h3{font-size:13px;margin:14px 0 4px}ul{margin:0;padding-left:18px}li{margin:3px 0}"
    "code{font:12px ui-monospace,monospace}"
    "@media (prefers-color-scheme:dark){body{color:#ddd}}"
)
print(f"<html><head><meta charset='utf-8'><style>{style}</style></head><body>{''.join(parts)}</body></html>")
