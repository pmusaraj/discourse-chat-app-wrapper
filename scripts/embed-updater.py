"""Embed Sparkle and sign nested code before sealing the app bundle."""
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
from urllib.parse import urlparse


def update_plist(plist, config):
    updates = config["updates"]
    url = urlparse(updates["feedURL"])
    if url.scheme != "https" or not url.hostname or url.username or url.password:
        raise ValueError("The update feed must use HTTPS without credentials")
    if len(base64.b64decode(updates["publicKey"], validate=True)) != 32:
        raise ValueError("Sparkle requires a 32-byte Ed25519 public key")
    plist.update({
        "CFBundleShortVersionString": config["version"],
        "LSMinimumSystemVersion": "15.0",
        "SUFeedURL": updates["feedURL"],
        "SUPublicEDKey": updates["publicKey"],
        "SUVerifyUpdateBeforeExtraction": True,
        "SUSendProfileInfo": False,
    })
    # Leave automatic-check consent to Sparkle; don't override user preferences.
    return plist


def main():
    config = json.loads(Path("tinyjs.json").read_text())
    app = Path("dist") / (config["title"] + ".app")
    plist_path = app / "Contents/Info.plist"
    plist = update_plist(plistlib.loads(plist_path.read_bytes()), config)
    framework = app / "Contents/Frameworks/Sparkle.framework"
    framework.parent.mkdir(exist_ok=True)
    subprocess.run(["ditto", ".runtime/sparkle/2.10.0/Sparkle.framework", str(framework)], check=True)
    licenses = app / "Contents/Resources/Sparkle-LICENSE.txt"
    licenses.write_bytes(Path(".runtime/sparkle/2.10.0/LICENSE").read_bytes())
    plist_path.write_bytes(plistlib.dumps(plist))
    identity = os.environ.get("TINYJS_SIGN_IDENTITY", "-")
    flags = [] if identity == "-" else ["--options", "runtime", "--timestamp"]
    version = framework / "Versions/B"
    # Sign inside-out, retaining the sandbox entitlements of Sparkle's helpers.
    targets = [version / "XPCServices/Downloader.xpc", version / "XPCServices/Installer.xpc",
               version / "Autoupdate", version / "Updater.app", framework, app]
    for target in targets:
        subprocess.run(["codesign", "--force", "--preserve-metadata=entitlements", *flags,
                        "--sign", identity, str(target)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)


if __name__ == "__main__":
    main()
