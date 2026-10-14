"""Exercise real Sparkle installation with isolated, notarized test apps.

Requires a built app, TINYJS_SIGN_IDENTITY, and NOTARY_PROFILE. Only a loopback
feed is served. No production preferences, sessions, or releases are changed.
"""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import subprocess
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
identity = os.environ["TINYJS_SIGN_IDENTITY"]
profile = os.environ["NOTARY_PROFILE"]
config = json.loads(Path("tinyjs.json").read_text())
run_id = uuid.uuid4().hex
work = ROOT / ".build" / "updater-install" / run_id
work.mkdir(parents=True)
result_file = work / "result.json"
feed = work / "feed"
feed.mkdir()


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(feed)))
threading.Thread(target=server.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{server.server_port}"
source_app = ROOT / "dist" / (config["title"] + ".app")
apps = []
try:
    for role, version in [("old", "1.0.0"), ("new", "2.0.0")]:
        app = work / "apps" / role / "Updater Install Test.app"
        apps.append(app)
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Frameworks").mkdir()
        run("ditto", source_app / "Contents/Frameworks/Sparkle.framework", app / "Contents/Frameworks/Sparkle.framework")
        plist = {
            "CFBundleIdentifier": "org.discourse.chat.updater-install-test." + run_id,
            "CFBundleName": "Updater Install Test", "CFBundleExecutable": "updater-install",
            "CFBundleVersion": version, "CFBundleShortVersionString": version,
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "15.0",
            "LSUIElement": True, "SUEnableAutomaticChecks": False,
            "SUVerifyUpdateBeforeExtraction": True,
            "SUPublicEDKey": config["updates"]["publicKey"],
            "SUFeedURL": url + "/appcast.xml", "TestResultPath": str(result_file),
            "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True},
        }
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(plist))
        run("c++", "-std=c++17", "-x", "objective-c++", "-mmacosx-version-min=15.0",
            "-F", ".runtime/sparkle/2.10.0", "-framework", "AppKit", "-framework", "WebKit",
            "-framework", "Sparkle", "-Wl,-rpath,@executable_path/../Frameworks",
            "test/updater-install.mm", "-o", app / "Contents/MacOS/updater-install")
        run("codesign", "--force", "--options", "runtime", "--timestamp", "--sign", identity, app)
        run("codesign", "--verify", "--deep", "--strict", app)
    submission = work / "notarization.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", work / "apps", submission)
    run("xcrun", "notarytool", "submit", submission, "--keychain-profile", profile, "--wait")
    for app in apps:
        run("xcrun", "stapler", "staple", app)
        run("spctl", "--assess", "--type", "execute", app)
    archive = feed / "Updater-Test-2.0.0.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", apps[1], archive)
    run(".runtime/sparkle/2.10.0/bin/generate_appcast", "--account", config["updates"]["keychainAccount"],
        "--maximum-deltas", "0", "--download-url-prefix", url + "/", feed)
    print("Launching isolated old app; waiting for download, installation, and relaunch.", flush=True)
    run("open", "-n", apps[0])
    deadline = time.monotonic() + 180
    while not result_file.exists() and time.monotonic() < deadline:
        time.sleep(1)
    if not result_file.exists():
        raise RuntimeError(f"Update test timed out; artifacts: {work}")
    result = json.loads(result_file.read_text())
    print(json.dumps(result, indent=2))
    if not result["success"]:
        raise RuntimeError("Update installation test failed")
    installed = plistlib.loads((apps[0] / "Contents/Info.plist").read_bytes())
    assert installed["CFBundleVersion"] == "2.0.0", "Old app bundle was not replaced"
    run("codesign", "--verify", "--deep", "--strict", apps[0])
    print(f"Update installation passed. Result: {result_file}")
finally:
    server.shutdown()
