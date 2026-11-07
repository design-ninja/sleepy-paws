#!/usr/bin/env bash
# Publishes a release: notarized ZIP + Sparkle appcast on GitHub, notes from CHANGELOG.md.
#
# Before running: bump CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist
# (Sparkle compares CFBundleVersion, so it must grow), add a "## [x.y.z] - date" section to
# CHANGELOG.md, commit and push. Needs the variables script/notarize.sh needs.
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
grep -q "^## \[$version\]" CHANGELOG.md || { echo "Add a ## [$version] section to CHANGELOG.md" >&2; exit 2; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first" >&2; exit 2; }

zip="$(./script/notarize.sh | tail -1)"
./script/appcast.sh "$zip" >/dev/null

notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT
awk -v v="$version" '$0 ~ "^## \\[" v "\\]" {on=1; next} on && /^## \[/ {exit} on && /^\[/ {exit} on' CHANGELOG.md > "$notes"
printf '\nSHA-256: `%s`\n' "$(shasum -a 256 "$zip" | cut -d' ' -f1)" >> "$notes"

git tag -a "v$version" -m "Sleepy Paws $version"
git push origin "v$version"
gh release create "v$version" "$zip" dist/appcast.xml --title "Sleepy Paws $version" --notes-file "$notes"
