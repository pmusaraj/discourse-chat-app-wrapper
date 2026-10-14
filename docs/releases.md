# macOS updates and releases

Packaged builds starting with 0.2.6 embed Sparkle 2.10.0. The application menu
contains **Check for Updates…** and **Automatically Check for Updates**. Sparkle
asks for automatic-check consent and remembers the user's preference. The dev
launcher (`npm start`) never loads the updater. Updates replace the app bundle;
site preferences and WebKit session storage remain outside it.

Users of 0.2.6 and earlier must manually install 0.2.7 or later because the
repository rename changed the update-feed address. Releases currently support Apple Silicon on macOS 15 or later.

## Signing and hosting

- Apple team: **M4XMDAF939** (personal account).
- Feed: https://pmusaraj.github.io/discourse-chat-app-wrapper/appcast.xml
- Downloads: https://github.com/pmusaraj/discourse-chat-app-wrapper/releases
- Sparkle public key and feed URL: `tinyjs.json` under `updates`.
- Sparkle private key: macOS login Keychain, service **Private key for signing
  Sparkle updates**, account **org.discourse.dev.chat.tinyjs.poc**.

Keep a secure backup of this private key. Never regenerate it for each release
or commit it. The public key must stay consistent across installed versions.
Apple signing and Sparkle archive signing are separate requirements.

The normal `npm run build` command creates a locally signed app. Public releases
require a **Developer ID Application** certificate with its private key from
team M4XMDAF939, and Apple notarization credentials. Apple Development and
Apple Distribution certificates are not substitutes for Developer ID.

## One-time GitHub configuration

Set **Settings → Pages → Source** to **GitHub Actions**, then run the
**Initialize update feed** workflow. It preserves an existing feed and otherwise
publishes an empty feed. Do not add unpublished builds to it.

Configure these Actions secrets for the repository:

| Secret | Contents |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64-encoded export of the personal team's Developer ID Application certificate and private key |
| `DEVELOPER_ID_P12_PASSWORD` | Password protecting that export |
| `APPLE_ID` | Apple ID belonging to team M4XMDAF939 |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |
| `SPARKLE_PRIVATE_KEY` | Sparkle signing key exported by `generate_keys` |

To copy the app's Sparkle key into its GitHub secret without printing it:

```sh
sh scripts/setup-sparkle.sh
key_dir=$(mktemp -d)
chmod 700 "$key_dir"
.runtime/sparkle/2.10.0/bin/generate_keys \
  --account org.discourse.dev.chat.tinyjs.poc -x "$key_dir/sparkle.key"
gh secret set SPARKLE_PRIVATE_KEY --repo pmusaraj/discourse-chat-app-wrapper < "$key_dir/sparkle.key"
rm -rf "$key_dir"
```

Protect release-tag creation and repository write access: release jobs can use
signing credentials. The workflow imports Apple credentials into a temporary
Keychain and removes it after the build.

## Publish a release

Run **Release macOS app** manually on main to validate credentials and produce
a notarized artifact without publishing. Only a pushed version tag publishes.

1. Set a strictly newer version in `tinyjs.json`, commit it, and push main.
2. Tag that commit with the matching version, e.g. `v0.2.7`, and push the tag.
3. The **Release macOS app** workflow runs tests, builds, checks the Developer ID
   identity and team, notarizes, staples, and creates a signed ZIP and appcast.
4. It verifies the archive signature against the public key shipped in the app,
   then publishes the GitHub Release before deploying the updated Pages feed.

The workflow preserves older feed entries and publishes complete archives;
delta updates are disabled. It serializes releases and feed initialization.
A missing credential, failed notarization, signature mismatch, or wrong platform
stops publication. Do not move an existing release tag or overwrite its ZIP.
If Pages deployment fails after release publication, rerun only the failed `publish` job. It checks that existing release assets
match the saved build artifact before retrying deployment; do not rebuild or
replace the published archive. The feed must reference the exact signed ZIP.

## Prepare a release locally

After importing the Developer ID certificate and storing a notarization profile
with `xcrun notarytool store-credentials`, run:

```sh
TINYJS_SIGN_IDENTITY='Developer ID Application: YOUR NAME (M4XMDAF939)' \
NOTARY_PROFILE=discourse-chat-release npm run release
```

This prepares `dist/release/` without publishing. The script uses the app-specific
Sparkle key in your Keychain, or `SPARKLE_PRIVATE_KEY` on standard input in CI.
It downloads the current feed first, so initialize Pages before releasing.

## Verification

```sh
npm test
npm run build
bash scripts/test-updater.sh
```

The native smoke test uses an isolated app identity to verify framework loading,
menu actions, the saved automatic-check toggle, and the dev-launcher guard. It
never installs an update or changes the real app's update preferences.

For a real download/install/relaunch test using isolated apps and a loopback feed:

```sh
TINYJS_SIGN_IDENTITY='Developer ID Application: YOUR NAME (M4XMDAF939)' \
NOTARY_PROFILE=discourse-chat-release python3 scripts/test-updater-install.py
```

This test signs and notarizes two fixture apps with a unique bundle ID, updates
the older one through Sparkle, and verifies its replacement, relaunch, preference
retention, and persistent WebKit cookie. The fixture initializes a webview and
allows the seeded cookie to reach disk before updating. It does not access real
site sessions or publish test builds. Results are saved under `.build/updater-install/`.
A successful build or smoke test alone does not exercise installation/relaunch.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[publishing updates](https://sparkle-project.org/documentation/publishing/).
