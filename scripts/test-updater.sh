#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Requires npm run build. Uses an isolated app identity and never installs an update.
fixture=$(mktemp -d "${TMPDIR:-/tmp}/chat-updater-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
app="$fixture/Updater Test.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
ditto 'dist/Discourse Chat App.app/Contents/Frameworks/Sparkle.framework' "$app/Contents/Frameworks/Sparkle.framework"
python3 - "$app" <<'PY'
from pathlib import Path
import plistlib, sys, uuid
plist = plistlib.loads(Path('dist/Discourse Chat App.app/Contents/Info.plist').read_bytes())
plist.update(CFBundleIdentifier='org.discourse.chat.updater-test.' + uuid.uuid4().hex,
             CFBundleExecutable='updater-test', CFBundleName='Updater Test',
             SUEnableAutomaticChecks=False)
Path(sys.argv[1], 'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
PY
c++ -std=c++17 -x objective-c++ -mmacosx-version-min=15.0 \
  -F .runtime/sparkle/2.10.0 -framework AppKit \
  test/native-updater.mm -o "$app/Contents/MacOS/updater-test"
codesign --force --sign - "$app"
"$app/Contents/MacOS/updater-test"
