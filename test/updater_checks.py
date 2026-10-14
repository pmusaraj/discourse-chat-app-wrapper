import base64
import importlib.util
from pathlib import Path
import tempfile
import unittest


def module(filename):
    spec = importlib.util.spec_from_file_location(filename, Path(__file__).parent.parent / "scripts" / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


embed = module("embed-updater.py")
appcast = module("validate-appcast.py")


class UpdateChecks(unittest.TestCase):
    def config(self):
        return {"version": "0.2.6", "updates": {"feedURL": "https://example.com/appcast.xml",
                "publicKey": base64.b64encode(bytes(32)).decode()}}

    def test_feed_and_key_validation(self):
        for feed in ["http://example.com/appcast.xml", "file:///tmp/feed", "https://user:secret@example.com/feed"]:
            config = self.config()
            config["updates"]["feedURL"] = feed
            with self.assertRaises(ValueError):
                embed.update_plist({}, config)
        for key in ["", "not base64", base64.b64encode(bytes(64)).decode()]:
            config = self.config()
            config["updates"]["publicKey"] = key
            with self.assertRaises(ValueError):
                embed.update_plist({}, config)
        plist = embed.update_plist({"CFBundleIdentifier": "existing.app"}, self.config())
        self.assertEqual(plist["CFBundleIdentifier"], "existing.app")
        self.assertNotIn("SUEnableAutomaticChecks", plist)
        self.assertTrue(plist["SUVerifyUpdateBeforeExtraction"])

    def test_rejects_incorrect_release_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory, "Discourse-Chat-0.2.6-arm64.zip")
            archive.write_bytes(b"archive")
            feed = Path(directory, "appcast.xml")
            signature = base64.b64encode(bytes(64)).decode()
            valid = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
              <sparkle:version>0.2.6</sparkle:version>
              <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
              <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
              <enclosure url="https://github.com/pmusaraj/discourse-chat-wrapper/releases/download/v0.2.6/{archive.name}"
                sparkle:edSignature="{signature}" length="7" />
              </item></channel></rss>'''
            feed.write_text(valid)
            appcast.validate(feed, "0.2.6", archive)
            for broken in [valid.replace(signature, ""), valid.replace('length="7"', 'length="8"'),
                           valid.replace('v0.2.6/', 'v0.2.5/'), valid.replace('>arm64<', '>x86_64<'),
                           valid.replace('>15.0<', '>14.0<'), valid.replace('>0.2.6<', '>0.2.5<')]:
                feed.write_text(broken)
                with self.assertRaises(ValueError):
                    appcast.validate(feed, "0.2.6", archive)
