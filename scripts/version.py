"""Check/bump the single version source and extract its committed release notes."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def parse(version):
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version):
        raise ValueError("Version must be MAJOR.MINOR.PATCH without a v prefix.")
    return tuple(map(int, version.split(".")))


def notes(version, changelog):
    match = re.search(r"^## " + re.escape(version) + r"\s*\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
    if not match or not match[1].strip():
        raise ValueError("Add nonempty release notes to CHANGELOG.md before releasing.")
    return match[1].strip()


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "check"
    current = (ROOT / "VERSION").read_text().strip()
    parse(current)
    if action == "bump":
        target = sys.argv[2]
        if parse(target) <= parse(current):
            raise ValueError("New version must increase monotonically.")
        notes(target, (ROOT / "CHANGELOG.md").read_text())
        (ROOT / "VERSION").write_text(target + "\n")
        print("Version updated to " + target)
    elif action in ("notes", "check"):
        content = notes(current, (ROOT / "CHANGELOG.md").read_text())
        print(content if action == "notes" else "Version and changelog are consistent: " + current)
    else:
        raise ValueError("Use check, notes, or bump VERSION.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, IndexError) as error:
        sys.exit(str(error))
