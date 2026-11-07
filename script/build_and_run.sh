#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-run}"
case "$mode" in
    run|--debug|--logs|--telemetry|--verify)
        build=(--configuration debug --arch arm64)
        bundle="$PWD/dist/Sleepy Paws.app"
        ;;
    --package)
        build=(--configuration release --arch arm64 --scratch-path .build/package)
        bundle="$PWD/dist/Release/Sleepy Paws.app"
        ;;
    *) echo "Usage: $0 [run|--debug|--logs|--telemetry|--verify|--package]" >&2; exit 2 ;;
esac

swift build "${build[@]}"
bin="$(swift build "${build[@]}" --show-bin-path)/SleepyPaws"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/AppIcon.iconset"
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        name="icon_${size}x${size}"
        if [[ $scale == 2 ]]; then name="${name}@2x"; fi
        pixels=$((size * scale))
        /usr/bin/sips -z "$pixels" "$pixels" Resources/AppIcon.png --out "$tmp/AppIcon.iconset/$name.png" >/dev/null
    done
done
/usr/bin/iconutil --convert icns "$tmp/AppIcon.iconset" --output "$tmp/AppIcon.icns"
if [[ $mode != --package ]]; then
    # Unload the background agent so it doesn't restart the old copy; the new app loads it again.
    /bin/launchctl bootout "gui/$UID/pro.lirik.sleepypaws.agent" 2>/dev/null || true
    /usr/bin/pkill -u "$UID" -x SleepyPaws 2>/dev/null || true
fi
mkdir -p "$bundle/Contents/"{MacOS,Resources}
install -m 755 "$bin" "$bundle/Contents/MacOS/SleepyPaws"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp Resources/{AppIcon.png,TimeIsUp.wav} "$tmp/AppIcon.icns" "$bundle/Contents/Resources/"
if [[ $mode == --package && -n ${SLEEPYPAWS_SIGNING_IDENTITY:-} ]]; then
    /usr/bin/codesign --force --options runtime --timestamp --entitlements Resources/SleepyPaws.entitlements --sign "$SLEEPYPAWS_SIGNING_IDENTITY" "$bundle"
else
    # Sign development builds with a stable identity when there is one (ad hoc otherwise), so
    # macOS permissions such as Automation survive rebuilds.
    identity="${SLEEPYPAWS_DEV_IDENTITY:-$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
        | /usr/bin/sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | /usr/bin/head -1)}"
    /usr/bin/codesign --force --entitlements Resources/SleepyPaws.entitlements --sign "${identity:--}" "$bundle"
fi
/usr/bin/codesign --verify --strict "$bundle"

case "$mode" in
    --package)
        /usr/bin/lipo -verify_arch arm64 "$bundle/Contents/MacOS/SleepyPaws"
        [[ "$(/usr/bin/lipo -archs "$bundle/Contents/MacOS/SleepyPaws")" == arm64 ]]
        echo "$bundle"
        ;;
    --debug) xcrun lldb -- "$bundle/Contents/MacOS/SleepyPaws" ;;
    *)
        /usr/bin/open -n "$bundle"
        case "$mode" in
            --logs|--telemetry) /usr/bin/log stream --info --style compact --predicate 'subsystem == "pro.lirik.sleepypaws"' ;;
            --verify) sleep 1; /usr/bin/pgrep -u "$UID" -x SleepyPaws ;;
        esac
        ;;
esac
