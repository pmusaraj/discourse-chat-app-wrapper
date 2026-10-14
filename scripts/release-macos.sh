#!/bin/bash
# Build a release locally or in CI. Publishing is a separate, explicit step.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TINYJS_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set a notarytool Keychain profile}"
if [[ "$(uname -m)" != arm64 ]]; then
  echo 'Releases currently require an Apple Silicon host.' >&2
  exit 1
fi
version=$(node -p 'JSON.parse(require("fs").readFileSync("tinyjs.json")).version')
if [[ "${GITHUB_REF_TYPE:-}" == tag && "${GITHUB_REF_NAME}" != "v$version" ]]; then
  echo "Tag must match tinyjs.json: v$version" >&2
  exit 1
fi
npm test
npm run build
app='dist/Discourse Chat App.app'
# Do not accidentally distribute the development-signed build.
signature=$(codesign -dv --verbose=4 "$app" 2>&1)
if ! printf '%s\n' "$signature" | grep -q '^Authority=Developer ID Application:' ||
   ! printf '%s\n' "$signature" | grep -q '^TeamIdentifier=M4XMDAF939$'; then
  echo 'Release requires a Developer ID Application certificate from personal team M4XMDAF939.' >&2
  exit 1
fi
mkdir -p .build/notarization
notary_zip='.build/notarization/Discourse-Chat.zip'
ditto -c -k --sequesterRsrc --keepParent "$app" "$notary_zip"
notary_args=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
  notary_args+=(--keychain "$NOTARY_KEYCHAIN")
fi
xcrun notarytool submit "$notary_zip" "${notary_args[@]}" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
release_dir="dist/release"
mkdir -p "$release_dir"
archive="Discourse-Chat-$version-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$release_dir/$archive"
# Seed from the published feed so older compatible releases remain available.
feed_url=$(node -p 'JSON.parse(require("fs").readFileSync("tinyjs.json")).updates.feedURL')
curl --fail --location --retry 3 "$feed_url" -o "$release_dir/appcast.xml"
appcast_args=(--maximum-deltas 0 --maximum-versions 0
  --download-url-prefix "https://github.com/pmusaraj/discourse-chat-app-wrapper/releases/download/v$version/"
  --link 'https://github.com/pmusaraj/discourse-chat-app-wrapper'
  "$release_dir")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | .runtime/sparkle/2.10.0/bin/generate_appcast --ed-key-file - "${appcast_args[@]}"
else
  keychain_account=$(node -p 'JSON.parse(require("fs").readFileSync("tinyjs.json")).updates.keychainAccount')
  .runtime/sparkle/2.10.0/bin/generate_appcast --account "$keychain_account" "${appcast_args[@]}"
fi
python3 scripts/validate-appcast.py "$release_dir/appcast.xml" "$version" "$release_dir/$archive"
(cd "$release_dir" && shasum -a 256 "$archive" > SHA256SUMS)
echo "Release prepared in $release_dir; nothing has been published."
