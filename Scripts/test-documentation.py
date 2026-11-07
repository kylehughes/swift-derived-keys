"""Exercise the Pages deployment guard without network access or publication."""
import json
import os
from pathlib import Path
import re
import tempfile
import textwrap
import unittest
from unittest.mock import patch


WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/documentation.yml"
MISSING = object()


class DocumentationDeploymentTests(unittest.TestCase):
    def setUp(self):
        blocks = re.findall(r"^        python3 -I - <<'PY'\n(.*?)^        PY$",
                            WORKFLOW.read_text(), re.MULTILINE | re.DOTALL)
        self.assertEqual(len(blocks), 1)
        self.guard = compile(textwrap.dedent(blocks[0]), str(WORKFLOW), "exec")
        self.candidate = "a" * 40
        self.repository = {"full_name": "kylehughes/swift-derived-keys",
                           "default_branch": "main", "private": True, "visibility": "private"}
        self.site = {"public": True, "build_type": "workflow",
                     "html_url": "https://kylehughes.github.io/swift-derived-keys/"}
        self.head = {"ref": "refs/heads/main",
                     "object": {"type": "commit", "sha": self.candidate}}

    def run_guard(self):
        with tempfile.TemporaryDirectory() as directory:
            for name, value in (("repository", self.repository), ("site", self.site),
                                ("head", self.head)):
                (Path(directory) / f"pages-{name}.json").write_text(json.dumps(value))
            with patch.dict(os.environ, {"RUNNER_TEMP": directory, "CANDIDATE": self.candidate}):
                exec(self.guard, {"__name__": "documentation_controls"})

    def test_private_and_public_repositories_can_publish_public_documentation(self):
        self.run_guard()
        self.repository.update(private=False, visibility="public")
        self.run_guard()

    def assert_rejected_changes(self, original, changes, message):
        baseline = original.copy()
        for field, value in changes:
            with self.subTest(field=field, value=value):
                original.clear()
                original.update(baseline)
                if value is MISSING:
                    original.pop(field)
                else:
                    original[field] = value
                with self.assertRaisesRegex(SystemExit, message):
                    self.run_guard()
        original.clear()
        original.update(baseline)

    def test_rejects_other_repository_or_default_branch(self):
        self.assert_rejected_changes(self.repository, [
            ("full_name", "someone/swift-derived-keys"), ("full_name", MISSING),
            ("default_branch", "develop"), ("default_branch", MISSING),
        ], "canonical repository")

    def test_requires_an_explicitly_public_site(self):
        self.assert_rejected_changes(self.site, [
            ("public", value) for value in (MISSING, False, None, 1, "true")
        ], "Pages destination")

    def test_rejects_other_pages_destination_or_build_type(self):
        self.assert_rejected_changes(self.site, [
            ("build_type", "legacy"), ("build_type", MISSING),
            ("html_url", "https://example.com/"), ("html_url", MISSING),
        ], "Pages destination")

    def test_rejects_other_ref_or_stale_candidate(self):
        self.assert_rejected_changes(self.head, [
            ("ref", "refs/heads/develop"), ("ref", MISSING), ("object", MISSING),
            ("object", {"type": "tag", "sha": self.candidate}),
            ("object", {"type": "commit", "sha": "b" * 40}),
            ("object", {"type": "commit"}),
        ], "current main commit")


if __name__ == "__main__":
    unittest.main()
