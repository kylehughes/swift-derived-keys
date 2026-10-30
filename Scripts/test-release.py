"""Standard-library controls for the release workflow's prerelease classification."""
import contextlib
import hashlib
import io
from pathlib import Path
import re
import tempfile
import textwrap
import unittest
from unittest.mock import patch


WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/release.yml"
MISSING = object()


def release_sources():
    blocks = re.findall(r"^        python3 -I - <<'PY'\n(.*?)^        PY$",
                        WORKFLOW.read_text(), re.MULTILINE | re.DOTALL)
    return [textwrap.dedent(block) for block in blocks
            if block.startswith("        # This workflow embeds the source below;")]


class FakeAPI:
    def __init__(self, unknown, archive, candidate, *, draft_flag=None, published_flag=None,
                 readback_flag=None, lose_patch=False):
        self.unknown = unknown
        self.archive = archive
        self.candidate = candidate
        self.draft_flag = draft_flag
        self.published_flag = published_flag
        self.readback_flag = readback_flag
        self.lose_patch = lose_patch
        self.calls = []
        self.release = None

    def response(self, flag):
        result = dict(self.release)
        if flag is MISSING:
            result.pop("prerelease", None)
        elif flag is not None:
            result["prerelease"] = flag
        return result

    def __call__(self, method, path, body=None, *, missing=False, upload=False):
        self.calls.append((method, path, body))
        if method == "GET" and path.startswith("/git/ref/tags/"):
            return None if missing else {"object": {"sha": self.candidate}}
        if method == "GET" and path == "/releases?per_page=100&page=1":
            return []
        if method == "POST" and path == "/releases":
            # GitHub defaults an omitted prerelease field to false.
            self.release = dict(body, id=123, prerelease=body.get("prerelease", False),
                                html_url="https://example.invalid/releases/123")
            return self.response(self.draft_flag)
        if method == "POST" and path == "/releases/123/assets?name=" + self.archive.name:
            if not upload or body != self.archive.read_bytes():
                raise AssertionError("Unexpected asset upload")
            return {"name": self.archive.name, "size": len(body),
                    "digest": "sha256:" + hashlib.sha256(body).hexdigest()}
        if method == "PATCH" and path == "/releases/123":
            self.release.update(body)
            if self.lose_patch:
                raise self.unknown("Simulated lost publication response")
            return self.response(self.published_flag)
        if method == "GET" and path == "/releases/123":
            return self.response(self.readback_flag)
        raise AssertionError(f"Unexpected API request: {method} {path}")


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.network = patch("urllib.request.build_opener",
                             side_effect=AssertionError("Release controls must never use the network"))
        self.network.start()
        self.addCleanup(self.network.stop)
        sources = release_sources()
        self.assertEqual(len(sources), 2)
        self.release = {"__name__": "release_controls"}
        exec(compile(sources[0], str(WORKFLOW), "exec"), self.release)
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.archive = Path(directory.name) / "source.tar.gz"
        self.archive.write_bytes(b"release regression archive bytes\n")
        self.digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.candidate = "a" * 40

    def publish(self, version, **options):
        tag = self.release["validate_inputs"](version, self.candidate, self.candidate, "Release notes", False)
        api = FakeAPI(self.release["Unknown"], self.archive, self.candidate, **options)
        self.api = api
        with contextlib.redirect_stdout(io.StringIO()):
            self.release["publish"](api, tag=tag, candidate=self.candidate, notes="Release notes",
                                    generated=False, archive=self.archive, expected_digest=self.digest)
        return api

    def assert_one_patch(self, api):
        self.assertEqual(sum(method == "PATCH" for method, _, _ in api.calls), 1)

    def test_embedded_release_sources_are_identical(self):
        sources = release_sources()
        self.assertEqual(len(sources), 2)
        self.assertEqual(sources[0], sources[1])

    def test_stable_and_prerelease_versions_publish_with_explicit_boolean(self):
        for version, expected in (("1.2.3", False), ("1.2.3+build-with-hyphen", False),
                                  ("1.0.0-beta.1", True), ("1.0.0-beta.1+build.7", True)):
            with self.subTest(version=version):
                api = self.publish(version)
                create = next(body for method, path, body in api.calls
                              if method == "POST" and path == "/releases")
                update = next(body for method, _, body in api.calls if method == "PATCH")
                self.assertIs(create.get("prerelease"), expected)
                self.assertIs(update.get("prerelease"), expected)
                self.assertIs(api.release["prerelease"], expected)
                self.assertIs(api.release["draft"], False)
                self.assert_one_patch(api)

    def test_invalid_draft_prerelease_response_stops_before_upload(self):
        for version, expected in (("1.2.3", False), ("1.0.0-beta.1", True)):
            for flag in (not expected, MISSING, int(expected), str(expected).lower()):
                with self.subTest(version=version, flag=flag):
                    with self.assertRaises(self.release["Unknown"]):
                        self.publish(version, draft_flag=flag)
                    self.assertFalse(any("/assets" in path or method == "PATCH"
                                         for method, path, _ in self.api.calls))

    def test_invalid_publication_prerelease_response_is_rejected(self):
        for version, expected in (("1.2.3", False), ("1.0.0-beta.1", True)):
            for flag in (not expected, MISSING, int(expected), str(expected).lower()):
                with self.subTest(version=version, flag=flag):
                    with self.assertRaises(self.release["Unknown"]):
                        self.publish(version, published_flag=flag)
                    self.assert_one_patch(self.api)

    def test_lost_publication_response_accepts_matching_readback_without_retry(self):
        for version in ("1.2.3", "1.0.0-beta.1"):
            with self.subTest(version=version):
                api = self.publish(version, lose_patch=True)
                self.assert_one_patch(api)
                self.assertEqual(sum(method == "GET" and path == "/releases/123"
                                     for method, path, _ in api.calls), 1)

    def test_lost_publication_response_rejects_invalid_readback_without_retry(self):
        for version, expected in (("1.2.3", False), ("1.0.0-beta.1", True)):
            for flag in (not expected, MISSING, int(expected), str(expected).lower()):
                with self.subTest(version=version, flag=flag):
                    with self.assertRaises(self.release["Unknown"]):
                        self.publish(version, lose_patch=True, readback_flag=flag)
                    self.assert_one_patch(self.api)
                    self.assertEqual(sum(method == "GET" and path == "/releases/123"
                                         for method, path, _ in self.api.calls), 1)


if __name__ == "__main__":
    unittest.main()
