"""Verify changed bundle content retains the same certificate-backed identity."""
import hashlib
import re
import subprocess
import tempfile
from pathlib import Path


def signature(app):
    result = subprocess.run(["codesign", "-d", "-r-", "--verbose=4", str(app)], text=True, capture_output=True, check=True)
    text = result.stdout + result.stderr
    requirement = re.search(r"designated => (.+)", text)[1]
    cdhash = re.search(r"CDHash=(\w+)", text)[1]
    assert "certificate" in requirement or "anchor" in requirement, "Certificate-backed identity required."
    return requirement, cdhash


if __name__ == "__main__":
    original = Path("build/package/SelAtRans.app").resolve()
    with tempfile.TemporaryDirectory(prefix="selatrans-signing-check-") as directory:
        copy = Path(directory) / "SelAtRans.app"
        subprocess.run(["ditto", str(original), str(copy)], check=True)
        subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Set CFBundleVersion 999.0.0", str(copy / "Contents/Info.plist")], check=True)
        subprocess.run(["scripts/sign-app.sh", str(copy)], check=True)
        first, first_hash = signature(original)
        second, second_hash = signature(copy)
        assert first == second, "Code identity changed between builds."
        assert first_hash != second_hash, "Probe did not change bundle content."
        print("PASS: different bundle content has the same certificate-backed designated requirement.")
        print("Requirement SHA-256:", hashlib.sha256(first.encode()).hexdigest())
