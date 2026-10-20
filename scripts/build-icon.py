"""Compile the app icon for macOS system surfaces, including notifications."""
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile


def build_icon(app, source):
    resources = app / "Contents/Resources"
    with tempfile.TemporaryDirectory(prefix="chat-icon-") as directory:
        staging = Path(directory)
        catalog = staging / "Assets.xcassets"
        icon = catalog / "AppIcon.appiconset"
        icon.mkdir(parents=True)
        images = []
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                filename = f"icon_{size}x{size}@{scale}x.png"
                pixels = str(size * scale)
                subprocess.run(["sips", "-z", pixels, pixels, str(source),
                                "--out", str(icon / filename)],
                               check=True, stdout=subprocess.DEVNULL)
                images.append({"idiom": "mac", "size": f"{size}x{size}",
                               "scale": f"{scale}x", "filename": filename})
        info = {"version": 1, "author": "xcode"}
        (catalog / "Contents.json").write_text(json.dumps({"info": info}))
        (icon / "Contents.json").write_text(json.dumps({"images": images, "info": info}))
        partial = staging / "icon.plist"
        subprocess.run(["xcrun", "actool", str(catalog), "--compile", str(resources),
                        "--platform", "macosx", "--minimum-deployment-target", "15.0",
                        "--app-icon", "AppIcon", "--output-partial-info-plist", str(partial)],
                       check=True)
        # Use actool's metadata so the icon name and compiled resources agree.
        plist_path = app / "Contents/Info.plist"
        plist = plistlib.loads(plist_path.read_bytes())
        plist.update(plistlib.loads(partial.read_bytes()))
        plist_path.write_bytes(plistlib.dumps(plist))


if __name__ == "__main__":
    config = json.loads(Path("tinyjs.json").read_text())
    build_icon(Path("dist") / (config["title"] + ".app"), Path(config["icon"]))
