#!/bin/bash
# Builds TiboDog.app (release, signed with a local identity or ad-hoc).
# Output goes to ./build, or $TIBODOG_APP_OUT; intermediate files to ./.build, or $TIBODOG_SCRATCH
# (`npx tibodog` points both into ~/.tibodog so nothing is written inside the npm cache).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
OUT="${TIBODOG_APP_OUT:-build}"
SCRATCH="${TIBODOG_SCRATCH:-.build}"
APP="$OUT/TiboDog.app"

swift build -c "$CONFIG" --scratch-path "$SCRATCH" 2>&1 | tail -n 3
BIN="$SCRATCH/$CONFIG/TiboDog"

# Now Playing helper (see Vendor/mediaremote-adapter/README.md). Built once, reused.
ADAPTER=Vendor/mediaremote-adapter
ADAPTER_BUILD="${TIBODOG_SCRATCH:+$SCRATCH/mediaremote-adapter}"
ADAPTER_BUILD="${ADAPTER_BUILD:-$ADAPTER/build}"
if [ ! -d "$ADAPTER_BUILD/MediaRemoteAdapter.framework" ]; then
  "$ADAPTER/build-framework.sh" "$ADAPTER_BUILD" 2>&1 | grep -vE "warning:|note:|^\s" || true
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TiboDog"
cp Resources/Info.plist "$APP/Contents/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp ../sounds/bark.wav "$APP/Contents/Resources/" # the bark (CC BY-SA 3.0, see ../sounds/CREDITS.md)
cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp -R "$ADAPTER_BUILD/MediaRemoteAdapter.framework" "$APP/Contents/Resources/"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# Signing: use $TIBODOG_SIGN_IDENTITY, else a local "TiboDog Dev" (or older "Islet Dev") certificate if one
# exists, else ad-hoc. A stable identity keeps the Keychain "Always Allow" grant across rebuilds
# (ad-hoc signatures change every build, so macOS asks again each time).
IDENTITY="${TIBODOG_SIGN_IDENTITY:-}"
for NAME in "TiboDog Dev" "Islet Dev"; do
  if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
    IDENTITY="$NAME"
  fi
done
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
