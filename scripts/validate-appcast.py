"""Fail publication if an unsigned or incorrectly targeted update was generated."""
import base64
import json
import subprocess
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


def validate(feed, version, archive):
    sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    items = ET.parse(feed).findall("./channel/item")
    matches = [item for item in items if item.findtext(sparkle + "version") == version]
    if len(matches) != 1:
        raise ValueError("Feed must contain exactly one entry for the release version")
    item = matches[0]
    enclosure = item.find("enclosure")
    expected = f"https://github.com/pmusaraj/discourse-chat-app-wrapper/releases/download/v{version}/{archive.name}"
    if enclosure is None or enclosure.get("url") != expected:
        raise ValueError("Update download does not match this GitHub release")
    if len(base64.b64decode(enclosure.get(sparkle + "edSignature", ""), validate=True)) != 64:
        raise ValueError("Missing or malformed Ed25519 update signature")
    if int(enclosure.get("length", "0")) != archive.stat().st_size:
        raise ValueError("Update archive size mismatch")
    if item.findtext(sparkle + "minimumSystemVersion") != "15.0":
        raise ValueError("Release must declare macOS 15.0 as its minimum")
    if item.findtext(sparkle + "hardwareRequirements") != "arm64":
        raise ValueError("Release must require Apple Silicon")
    return enclosure.get(sparkle + "edSignature")


if __name__ == "__main__":
    archive = Path(sys.argv[3])
    signature = validate(Path(sys.argv[1]), sys.argv[2], archive)
    public_key = json.loads(Path("tinyjs.json").read_text())["updates"]["publicKey"]
    subprocess.run(["swift", "scripts/verify-update.swift", public_key, signature, str(archive)], check=True)
