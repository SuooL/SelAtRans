import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from version import parse, notes
from validate_appcast import validate


class VersionTests(unittest.TestCase):
    def test_numeric_versions_sort_correctly(self):
        self.assertGreater(parse("0.10.0"), parse("0.9.9"))

    def test_invalid_versions_rejected(self):
        for version in ("v1.0.0", "1.0", "01.0.0", "1.0.0-beta", "1.0.0\nextra"):
            with self.assertRaises(ValueError):
                parse(version)

    def test_extracts_only_matching_notes(self):
        self.assertEqual(notes("0.1.0", "# Changelog\n\n## 0.2.0\nnew\n\n## 0.1.0\nold\n"), "old")

    def test_missing_or_empty_notes_rejected(self):
        for changelog in ("# Changelog", "## 0.1.0\n\n## 0.0.1\nold"):
            with self.assertRaises(ValueError):
                notes("0.1.0", changelog)


class AppcastTests(unittest.TestCase):
    def test_rejects_unsigned_wrong_version_or_wrong_origin(self):
        template = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>{version}</sparkle:version><enclosure url="{url}" length="123" {signature}/></item></channel></rss>'''
        expected_url = "https://github.com/SuooL/SelAtRans/releases/download/v0.1.0/SelAtRans.zip"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            for version, url, signature in (("0.1.0", expected_url, ""), ("0.0.1", expected_url, 'sparkle:edSignature="synthetic"'), ("0.1.0", "https://elsewhere.invalid/app.zip", 'sparkle:edSignature="synthetic"')):
                path.write_text(template.format(version=version, url=url, signature=signature))
                with self.assertRaises(AssertionError):
                    validate(path, "0.1.0")
            path.write_text(template.format(version="0.1.0", url=expected_url, signature='sparkle:edSignature="synthetic"'))
            validate(path, "0.1.0")
