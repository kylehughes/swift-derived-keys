"""Local parser controls; does not invoke Xcode or operate any device."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("run_uikit", Path(__file__).with_name("run-uikit.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerParserTests(unittest.TestCase):
    def test_destination_requires_exact_platform_and_id(self):
        self.assertEqual(runner.destination("platform=iOS,id=device"), {"platform": "iOS", "id": "device"})
        for invalid in ("platform=iOS", "platform=iOS,id=", "platform=macOS,id=device",
                        "platform=iOS,id=device,name=extra", "platform=iOS,platform=iOS"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                runner.destination(invalid)

    def test_environment_changes_only_selected_modern_target(self):
        other = {"BlueprintName": "Other", "EnvironmentVariables": {"existing": "value"}}
        target = {"BlueprintName": runner.TARGET, "EnvironmentVariables": {"preserved": "yes"}}
        document = {"TestConfigurations": [{"TestTargets": [other, target]}]}
        before = copy.deepcopy(other)
        runner.inject_environment(document, {"DERIVEDKEYS_UIKIT_BENCHMARK": "1"})
        self.assertEqual(other, before)
        self.assertEqual(target["EnvironmentVariables"],
                         {"preserved": "yes", "DERIVEDKEYS_UIKIT_BENCHMARK": "1"})

    def test_environment_requires_exactly_one_target(self):
        for targets in ([], [{"BlueprintName": runner.TARGET}] * 2):
            with self.assertRaises(ValueError):
                runner.inject_environment({"TestConfigurations": [{"TestTargets": targets}]}, {})
        document = {runner.TARGET: {}, "Other": {}}
        runner.inject_environment(document, {"enabled": "1"})
        self.assertEqual(document["Other"], {})
        self.assertEqual(document[runner.TARGET]["EnvironmentVariables"], {"enabled": "1"})

    def valid_payload(self):
        rows = []
        for workload in ("UILabel-single-line", "UILabel-multiline", "UILabel-attributed", "UITextView",
                         "DocumentContentView-text", "DocumentContentView-button", "DocumentContentView-parent"):
            scenarios = ["warm-one-view", "equivalent-pool-views", "width-changes", "content-font-changes", "mixed-bounded"]
            if workload.endswith("parent"):
                scenarios[0] = "warm-parent"
                scenarios.append("parent-only-spacing-miss")
            for scenario in scenarios:
                hits = dict.fromkeys(("parent", "text", "button", "leaf"), 0)
                misses = hits.copy()
                cache = ("parent" if workload.endswith("parent") else "text" if workload.endswith("text")
                         else "button" if workload.endswith("button") else "leaf")
                hits[cache] = 128
                if scenario == "parent-only-spacing-miss":
                    hits.update(parent=0, text=128, button=128)
                    misses["parent"] = 128
                if scenario == "mixed-bounded":
                    hits[cache] = 127
                    misses[cache] = 1
                    if cache == "parent":
                        hits.update(text=1, button=1)
                entries = dict.fromkeys(hits, 1)
                if workload == "DocumentContentView-button":
                    entries["button"] = {"content-font-changes": 3, "mixed-bounded": 6}.get(scenario, 1)
                samples = [{"index": i, "directFirst": i % 2 == 0, "resultsValidated": True,
                            "directNanoseconds": 256, "cachedNanoseconds": 128,
                            "directNanosecondsPerOperation": 2, "cachedNanosecondsPerOperation": 1,
                            "checksum": 10, "expectedChecksum": 10} for i in range(3)]
                rows.append({"workload": workload, "scenario": scenario, "timingBoundary": "complete operation",
                             "iterations": 128, "capacity": 16, "resultsValidated": True, "trials": samples,
                             "diagnostics": {"resultsValidated": True, "ownership": "local",
                                             "measurementCountsInferredFromMisses": workload.startswith("DocumentContentView-"),
                                             "observedMembershipHits": hits, "observedMembershipMisses": misses,
                                             "entryCounts": entries, "evictionObserved": workload != "DocumentContentView-button"}})
        return {"schemaVersion": 1, "benchmarkEnabled": True, "iterations": 128, "trials": 3,
                "capacity": 16, "warmupIterationsPerView": 4, "rows": rows,
                "costDiagnosticsInterpretation": runner.COST_INTERPRETATION,
                "costDiagnostics": self.valid_cost_rows(),
                "runtime": {"deviceName": "fixture", "model": "iPhone", "systemName": "iOS",
                            "systemVersion": "27.1", "isSimulator": True}}

    def valid_cost_rows(self):
        rows = []
        for workload in ("UILabel-single-line", "UILabel-multiline", "UILabel-attributed", "UITextView"):
            for phase, boundary in runner.COST_BOUNDARIES.items():
                if phase == "text-getter-64-slots" and workload != "UITextView":
                    continue
                rows.append({"workload": workload, "phase": phase, "iterations": 512,
                             "timingBoundary": boundary, "resultsValidated": True,
                             "trials": [{"index": index, "elapsedNanoseconds": 1024,
                                         "nanosecondsPerOperation": 2, "checksum": "0" if "hash" in phase else "123.5",
                                         "expectedChecksum": "0" if "hash" in phase else "123.5",
                                         "resultsValidated": True} for index in range(5)]})
        return rows

    def test_cost_diagnostics_require_exact_contract(self):
        payload = self.valid_payload()
        self.assertEqual(runner.validate_payload(payload, 128, 3)["costDiagnostics"]["rowCount"], 17)
        corruptions = ("missing", "duplicate", "append", "iterations", "trials", "index", "nan", "zero",
                       "per-operation", "checksum", "nonfinite-checksum", "negative-checksum", "flag",
                       "boundary", "interpretation")
        for corruption in corruptions:
            payload = self.valid_payload()
            rows = payload["costDiagnostics"]
            sample = rows[0]["trials"][0]
            if corruption == "missing":
                payload.pop("costDiagnostics")
            elif corruption == "duplicate":
                rows[-1] = rows[0]
            elif corruption == "append":
                rows.append(rows[0])
            elif corruption == "iterations":
                rows[0]["iterations"] = 128
            elif corruption == "trials":
                rows[0]["trials"].pop()
            elif corruption == "index":
                sample["index"] = 1
            elif corruption == "nan":
                sample["nanosecondsPerOperation"] = float("nan")
            elif corruption == "zero":
                sample["elapsedNanoseconds"] = 0
            elif corruption == "per-operation":
                sample["nanosecondsPerOperation"] = 3
            elif corruption == "checksum":
                sample["checksum"] = "7"
            elif corruption == "nonfinite-checksum":
                sample.update(checksum="NaN", expectedChecksum="NaN")
            elif corruption == "negative-checksum":
                sample.update(checksum="-1", expectedChecksum="-1")
            elif corruption == "flag":
                sample["resultsValidated"] = False
            elif corruption == "boundary":
                rows[0]["timingBoundary"] = "unsupported"
            else:
                payload["costDiagnosticsInterpretation"] = "unsupported"
            with self.subTest(corruption=corruption), self.assertRaises(ValueError):
                runner.validate_payload(payload, 128, 3)

    def test_exact_rows_and_valid_checksums_pass(self):
        self.assertEqual(runner.validate_payload(self.valid_payload(), 128, 3)["rowCount"], 36)

    def test_invalid_rows_checksums_timings_and_diagnostics_fail(self):
        for corruption in ("missing", "duplicate", "checksum", "nonfinite", "eviction", "warmmiss", "empty"):
            payload = self.valid_payload()
            if corruption == "missing":
                payload["rows"].pop()
            elif corruption == "duplicate":
                payload["rows"][-1] = payload["rows"][0]
            elif corruption == "checksum":
                payload["rows"][0]["trials"][0]["checksum"] = 11
            elif corruption == "nonfinite":
                payload["rows"][0]["trials"][0]["cachedNanoseconds"] = float("nan")
            elif corruption == "eviction":
                payload["rows"][4]["diagnostics"]["evictionObserved"] = False
            elif corruption == "warmmiss":
                payload["rows"][0]["diagnostics"]["observedMembershipMisses"]["leaf"] = 1
            else:
                payload["rows"] = []
            with self.subTest(corruption=corruption), self.assertRaises(ValueError):
                runner.validate_payload(payload, 128, 3)

    def test_only_small_button_mixed_workload_may_avoid_eviction(self):
        payload = self.valid_payload()
        row = next(row for row in payload["rows"] if row["workload"] == "DocumentContentView-button"
                   and row["scenario"] == "mixed-bounded")
        self.assertFalse(row["diagnostics"]["evictionObserved"])
        runner.validate_payload(payload, 128, 3)
        row["diagnostics"]["entryCounts"]["button"] = 7
        with self.assertRaises(ValueError):
            runner.validate_payload(payload, 128, 3)
        payload = self.valid_payload()
        row = next(row for row in payload["rows"] if row["workload"] == "DocumentContentView-text"
                   and row["scenario"] == "mixed-bounded")
        row["diagnostics"]["evictionObserved"] = False
        with self.assertRaises(ValueError):
            runner.validate_payload(payload, 128, 3)

    def test_membership_counts_conserve_leaf_and_parent_requests(self):
        for workload, cache in (("UILabel-single-line", "leaf"), ("DocumentContentView-parent", "parent"),
                                ("DocumentContentView-parent", "text"), ("DocumentContentView-parent", "button")):
            for delta in (-1, 1):
                payload = self.valid_payload()
                row = next(row for row in payload["rows"] if row["workload"] == workload
                           and row["scenario"] == "mixed-bounded")
                row["diagnostics"]["observedMembershipHits"][cache] += delta
                with self.subTest(workload=workload, cache=cache, delta=delta), self.assertRaises(ValueError):
                    runner.validate_payload(payload, 128, 3)
        payload = self.valid_payload()
        payload["rows"][0]["diagnostics"]["observedMembershipHits"]["text"] = 1
        with self.assertRaises(ValueError):
            runner.validate_payload(payload, 128, 3)

    def test_attachment_requires_nonempty_matching_device(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            attachment = {"suggestedHumanReadableName": runner.ATTACHMENT, "deviceId": "device",
                          "isAssociatedWithFailure": False, "exportedFileName": "payload.json"}
            manifest = [{"testIdentifier": runner.TEST + "()", "attachments": [attachment],
                         "testIdentifierURL": "test://com.apple.xcode/DerivedKeys/" + runner.TEST}]
            (directory / "payload.json").write_text('{"schemaVersion": 1}')
            (directory / "manifest.json").write_text(json.dumps(manifest))
            self.assertEqual(runner.read_attachment(directory, "device")[0], {"schemaVersion": 1})
            attachment["suggestedHumanReadableName"] = "DerivedKeysUIKitBenchmarks_0_32176F42-F0F5-4CE2-B6BC-F6E467807E5E.json"
            manifest[0]["testIdentifier"] = runner.TEST.split("/", 1)[1] + "()"
            (directory / "manifest.json").write_text(json.dumps(manifest))
            self.assertEqual(runner.read_attachment(directory, "device")[0], {"schemaVersion": 1})
            for invalid_name in ("DerivedKeysUIKitBenchmarks_arbitrary.json", "DerivedKeysUIKitBenchmarks_0_wrong.json"):
                attachment["suggestedHumanReadableName"] = invalid_name
                (directory / "manifest.json").write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    runner.read_attachment(directory, "device")
            attachment["suggestedHumanReadableName"] = runner.ATTACHMENT
            (directory / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                runner.read_attachment(directory, "wrong-device")
            original_url = manifest[0]["testIdentifierURL"]
            for wrong_url in (original_url.replace(runner.TARGET, "WrongTarget"),
                              original_url.replace("testSizingBenchmarks", "otherMethod"), original_url + "?args=1"):
                manifest[0]["testIdentifierURL"] = wrong_url
                (directory / "manifest.json").write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    runner.read_attachment(directory, "device")
            manifest[0]["testIdentifierURL"] = original_url
            (directory / "manifest.json").write_text(json.dumps(manifest))
            manifest[0]["attachments"].append(attachment.copy())
            (directory / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                runner.read_attachment(directory, "device")
            manifest[0]["attachments"].pop()
            manifest[0]["testIdentifier"] = "OtherSuite/testSizingBenchmarks()"
            (directory / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                runner.read_attachment(directory, "device")
            manifest[0]["testIdentifier"] = runner.TEST + "()"
            (directory / "manifest.json").write_text(json.dumps(manifest))
            (directory / "payload.json").write_text("")
            with self.assertRaises(ValueError):
                runner.read_attachment(directory, "device")


if __name__ == "__main__":
    unittest.main()
