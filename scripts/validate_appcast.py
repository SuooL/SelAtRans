"""Fail publication if the update feed is unsigned or references the wrong build."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def validate(path, version, repository="SuooL/SelAtRans"):
    root = ET.parse(path).getroot()
    item = root.find("channel/item")
    assert item is not None, "Appcast has no update item."
    assert item.findtext("{" + SPARKLE + "}version") == version, "Appcast version mismatch."
    enclosure = item.find("enclosure")
    assert enclosure is not None, "Appcast has no archive."
    assert enclosure.attrib.get("{" + SPARKLE + "}edSignature"), "Unsigned update."
    expected = f"https://github.com/{repository}/releases/download/v{version}/SelAtRans.zip"
    assert enclosure.attrib.get("url") == expected, "Unexpected update download URL."
    assert int(enclosure.attrib["length"]) > 0, "Empty archive."


if __name__ == "__main__":
    validate(sys.argv[1], Path("VERSION").read_text().strip())
    print("Signed update feed metadata passed.")
