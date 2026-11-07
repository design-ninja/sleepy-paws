#!/usr/bin/env bash
# Writes dist/appcast.xml for a notarized release ZIP, signed with the Sparkle EdDSA key kept in
# the login keychain (account "sleepy-paws"; create it with generate_keys --account sleepy-paws).
# Usage: script/appcast.sh dist/Sleepy-Paws-<version>-macOS-arm64.zip
set -euo pipefail
cd "$(dirname "$0")/.."

zip="${1:?Pass the release ZIP}"
repo="design-ninja/sleepy-paws"
tools=".build/artifacts/sparkle/Sparkle/bin"
[[ -x $tools/sign_update ]] || swift package resolve >/dev/null

info="Resources/Info.plist"
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$info")"
build="$(/usr/bin/plutil -extract CFBundleVersion raw "$info")"
minimum="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw "$info")"
signature="$("$tools/sign_update" --account sleepy-paws "$zip")" # sparkle:edSignature="…" length="…"
name="$(basename "$zip")"
date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
# The update window shows these notes (this version's CHANGELOG section) instead of a web page.
notes="$(python3 -I script/release_notes.py "$version")"

cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Sleepy Paws</title>
    <link>https://github.com/$repo</link>
    <item>
      <title>Sleepy Paws $version</title>
      <pubDate>$date</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <description><![CDATA[$notes]]></description>
      <sparkle:fullReleaseNotesLink>https://github.com/$repo/blob/main/CHANGELOG.md</sparkle:fullReleaseNotesLink>
      <enclosure url="https://github.com/$repo/releases/download/v$version/$name" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
XML
echo "dist/appcast.xml"
