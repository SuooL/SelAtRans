import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from agent_attribution import detect, normalize
from pr_policy import validate


class AttributionTests(unittest.TestCase):
    def test_supported_runtime_markers(self):
        for marker, agent in (("CODEX_THREAD_ID", "codex"), ("CLAUDECODE", "claude"), ("DEEPSEEK_AGENT_SESSION_ID", "deepseek")):
            self.assertEqual(detect({marker: "session"}), agent)

    def test_provider_configuration_is_not_agent_identity(self):
        self.assertIsNone(detect({"DEEPSEEK_API_KEY": "fake", "OPENAI_API_KEY": "fake"}))

    def test_ambiguous_markers_require_explicit_identity(self):
        env = {"CODEX_THREAD_ID": "session", "CLAUDECODE": "1"}
        with self.assertRaises(ValueError):
            detect(env)
        self.assertEqual(detect(dict(env, SELATRANS_AGENT="deepseek")), "deepseek")

    def test_replaces_stale_agent_and_preserves_human(self):
        message = "feat: change\n\nCo-authored-by: Claude <noreply@anthropic.com>\nCo-authored-by: Contributor <human@example.invalid>\n"
        result = normalize(message, "codex")
        self.assertNotIn("Claude", result)
        self.assertIn("Contributor", result)
        self.assertEqual(result.count("Co-authored-by: Codex"), 1)
        self.assertEqual(normalize(result, "codex"), result)

    def test_human_commit_unchanged(self):
        self.assertEqual(normalize("fix: manual\n", None), "fix: manual\n")

    def test_names_for_every_agent(self):
        for agent, name in (("codex", "Codex"), ("claude", "Claude"), ("deepseek", "DeepSeek")):
            self.assertIn("Co-authored-by: " + name + " <", normalize("feat: new", agent))


class PolicyTests(unittest.TestCase):
    @staticmethod
    def event(base, head, repo="SuooL/SelAtRans"):
        return {"pull_request": {"base": {"ref": base, "repo": {"full_name": "SuooL/SelAtRans"}}, "head": {"ref": head, "repo": {"full_name": repo}}, "title": "feat: valid"}}

    def test_valid_topology(self):
        validate(self.event("dev", "feature/work"))
        validate(self.event("dev", "hotfix/work"))
        validate(self.event("main", "dev"))

    def test_main_rejects_feature_or_fork(self):
        for event in (self.event("main", "feature/work"), self.event("main", "dev", "someone/fork")):
            with self.assertRaises(AssertionError):
                validate(event)

    def test_dev_rejects_release_branch(self):
        with self.assertRaises(AssertionError):
            validate(self.event("dev", "main"))
