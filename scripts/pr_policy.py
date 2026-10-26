"""Enforce feature -> dev and dev -> main PR topology without executing PR metadata."""

import json
import os
import re
from pathlib import Path


def validate(event):
    pr = event.get("pull_request")
    if not pr:
        return
    base, head = pr["base"]["ref"], pr["head"]["ref"]
    same_repo = pr["head"]["repo"]["full_name"] == pr["base"]["repo"]["full_name"]
    if base == "main":
        assert head == "dev" and same_repo, "Only this repository's dev branch may target main."
    else:
        assert base == "dev", "Feature PRs must target dev."
        dependency_bot = same_repo and pr.get("user", {}).get("login") == "dependabot[bot]" and head.startswith("dependabot/github_actions/")
        assert dependency_bot or re.fullmatch(r"(feature|fix|hotfix|chore)/[a-zA-Z0-9._/-]+", head), "Use a feature/*, fix/*, hotfix/*, or chore/* branch."
    assert re.match(r"^(feat|fix|chore|docs|test|ci|release)(\([^\n]+\))?: .+", pr["title"]), "Use a conventional PR title."


if __name__ == "__main__":
    path = os.environ.get("GITHUB_EVENT_PATH")
    validate(json.loads(Path(path).read_text()) if path else {})
    print("PR policy passed.")
