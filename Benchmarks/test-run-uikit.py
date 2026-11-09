"""Local parser controls; does not invoke Xcode or operate any device."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

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
            attachment["suggestedHumanReadableName"] = "DerivedKeysUIBenchmarks_0_32176F42-F0F5-4CE2-B6BC-F6E467807E5E.json"
            manifest[0]["testIdentifier"] = runner.TEST.split("/", 1)[1] + "()"
            (directory / "manifest.json").write_text(json.dumps(manifest))
            self.assertEqual(runner.read_attachment(directory, "device")[0], {"schemaVersion": 1})
            for invalid_name in ("DerivedKeysUIBenchmarks_arbitrary.json", "DerivedKeysUIBenchmarks_0_wrong.json"):
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

    def valid_string_payload(self):
        rows = []
        for content in runner.STRING_CONTENTS:
            for scenario in runner.STRING_SCENARIOS:
                for strategy_index, strategy in enumerate(runner.STRING_STRATEGIES):
                    counts = runner.STRING_COUNTS["direct" if strategy == "direct" else scenario]
                    rows.append({"content": content, "scenario": scenario, "strategy": strategy,
                                 "iterations": 128, "capacity": 16, "resultsValidated": True,
                                 "timingBoundary": runner.STRING_TIMING_BOUNDARIES[scenario],
                                 "diagnostics": dict(zip(("hits", "misses", "measurementCount", "entryCount",
                                                           "evictionObserved", "returnHitValidated"), counts),
                                                     resultsValidated=True, iterations=128,
                                                     distinctHeightsObserved=scenario != "repeated-warm",
                                                     restoredResultValidated=scenario == "mutation-return"),
                                 "trials": [{"index": index, "orderIndex": (strategy_index - index) % 4,
                                             "elapsedNanoseconds": 256, "nanosecondsPerOperation": 2,
                                             "checksum": 100, "expectedChecksum": 100, "resultsValidated": True}
                                            for index in range(9)]})
        phases = [{"content": content, "strategy": strategy, "phase": phase, "iterations": 512,
                   "timingBoundary": runner.STRING_PHASE_BOUNDARIES[phase], "resultsValidated": True,
                   "trials": [{"index": index, "elapsedNanoseconds": 1024, "nanosecondsPerOperation": 2,
                               "checksum": "0", "expectedChecksum": "0", "resultsValidated": True}
                              for index in range(5)]}
                  for content in runner.STRING_CONTENTS for strategy in runner.STRING_STRATEGIES[1:]
                  for phase in runner.STRING_PHASES]
        return {"schemaVersion": 1, "benchmarkEnabled": True, "iterations": 128, "trials": 9, "capacity": 16,
                "runtime": self.valid_payload()["runtime"], "rows": rows,
                "fixtureOwnership": runner.STRING_FIXTURE_OWNERSHIP, "warmupIterationsPerView": 8,
                "width": 180, "fontPointSize": 17, "costDiagnostics": phases,
                "phaseIterations": 512, "phaseTrials": 5, "phaseOrder": list(runner.STRING_PHASES),
                "phaseInterpretation": runner.STRING_PHASE_INTERPRETATION,
                "representations": [{"content": content, "strategy": strategy,
                                     "utf8Length": {"short-ascii": 8, "long-ascii": 2048, "long-non-ascii": 4096}[content], "isContiguousUTF8": True,
                                     "rawUIKitIsContiguousUTF8": False, "sourceIsContiguousUTF8": True}
                                    for content in runner.STRING_CONTENTS for strategy in runner.STRING_STRATEGIES[1:]]}

    def test_string_suite_exact_contract_and_observed_representations(self):
        payload = self.valid_string_payload()
        self.assertEqual(runner.validate_payload(payload, 128, 9, "strings")["rowCount"], 36)
        for item in payload["representations"]:
            item["isContiguousUTF8"] = False
        runner.validate_payload(payload, 128, 9, "strings")
        with self.assertRaises(ValueError):
            runner.validate_payload(payload, 128, 9)
        with self.assertRaises(ValueError):
            runner.validate_payload(self.valid_payload(), 128, 3, "strings")

    def test_string_payload_rejects_incomplete_or_changed_contract(self):
        corruptions = {
            "row": lambda p: p["rows"].pop(),
            "arm": lambda p: p["rows"][0].update(strategy="other"),
            "duplicate": lambda p: p["rows"].__setitem__(-1, p["rows"][0]),
            "trial": lambda p: p["rows"][0]["trials"].pop(),
            "trial-index": lambda p: p["rows"][0]["trials"][0].update(index=True),
            "order": lambda p: p["rows"][0]["trials"][0].update(orderIndex=3),
            "zero": lambda p: p["rows"][0]["trials"][0].update(elapsedNanoseconds=0),
            "nonfinite": lambda p: p["rows"][0]["trials"][0].update(nanosecondsPerOperation=float("inf")),
            "division": lambda p: p["rows"][0]["trials"][0].update(nanosecondsPerOperation=3),
            "checksum": lambda p: p["rows"][0]["trials"][0].update(checksum=101),
            "equivalence": lambda p: p["rows"][1]["trials"][0].update(checksum=101, expectedChecksum=101),
            "flag": lambda p: p["rows"][0]["trials"][0].update(resultsValidated=False),
            "count": lambda p: p["rows"][1]["diagnostics"].update(hits=127),
            "measurement": lambda p: p["rows"][1]["diagnostics"].update(measurementCount=1),
            "mutation": lambda p: p["rows"][5]["diagnostics"].update(misses=0),
            "eviction": lambda p: p["rows"][9]["diagnostics"].update(evictionObserved=False),
            "phase": lambda p: p["costDiagnostics"].pop(),
            "phase-trial": lambda p: p["costDiagnostics"][0]["trials"].pop(),
            "phase-timing": lambda p: p["costDiagnostics"][0]["trials"][0].update(elapsedNanoseconds=-1),
            "phase-checksum": lambda p: p["costDiagnostics"][0]["trials"][0].update(checksum="NaN", expectedChecksum="NaN"),
            "phase-order": lambda p: p["phaseOrder"].reverse(),
            "phase-boundary": lambda p: p["costDiagnostics"][0].update(timingBoundary="other"),
            "representation": lambda p: p["representations"].pop(),
            "representation-identity": lambda p: p["representations"][0].update(strategy="direct"),
            "representation-length": lambda p: p["representations"][0].update(utf8Length=1),
            "representation-raw-flag": lambda p: p["representations"][0].update(rawUIKitIsContiguousUTF8="false"),
            "representation-source-flag": lambda p: p["representations"][0].update(sourceIsContiguousUTF8=None),
            "restored-result": lambda p: p["rows"][4]["diagnostics"].update(restoredResultValidated=False),
            "distinct-heights": lambda p: p["rows"][4]["diagnostics"].update(distinctHeightsObserved=False),
            "representation-flag": lambda p: p["representations"][0].update(isContiguousUTF8=1),
        }
        for corruption, mutate in corruptions.items():
            payload = self.valid_string_payload()
            mutate(payload)
            with self.subTest(corruption=corruption), self.assertRaises(ValueError):
                runner.validate_payload(payload, 128, 9, "strings")

    def test_both_suites_route_only_their_selected_test_and_attachment(self):
        for suite, (selected_test, attachment_name) in runner.SUITES.items():
            with self.subTest(suite=suite), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                attachment = {"suggestedHumanReadableName": attachment_name, "deviceId": "device",
                              "isAssociatedWithFailure": False, "exportedFileName": "payload.json"}
                manifest = [{"testIdentifier": selected_test + "()", "attachments": [attachment],
                             "testIdentifierURL": "test://com.apple.xcode/DerivedKeys/" + selected_test}]
                (directory / "payload.json").write_text('{"ok": true}')
                def write_manifest():
                    (directory / "manifest.json").write_text(json.dumps(manifest))
                write_manifest()
                self.assertEqual(runner.read_attachment(directory, "device", suite)[0], {"ok": True})
                attachment["suggestedHumanReadableName"] = (Path(attachment_name).stem
                    + "_0_32176F42-F0F5-4CE2-B6BC-F6E467807E5E.json")
                write_manifest()
                runner.read_attachment(directory, "device", suite)
                other_suite = "strings" if suite == "sizing" else "sizing"
                with self.assertRaises(ValueError):
                    runner.read_attachment(directory, "device", other_suite)
                attachment["suggestedHumanReadableName"] = runner.SUITES[other_suite][1]
                write_manifest()
                with self.assertRaises(ValueError):
                    runner.read_attachment(directory, "device", suite)
                attachment["suggestedHumanReadableName"] = attachment_name
                manifest[0]["attachments"].append(attachment.copy())
                write_manifest()
                with self.assertRaises(ValueError):
                    runner.read_attachment(directory, "device", suite)

    def test_strings_suite_rejects_nonfixed_parameters_before_any_device_work(self):
        for arguments in (("--iterations", "129"), ("--trials", "3")):
            with self.subTest(arguments=arguments), mock.patch("sys.argv", ["run-uikit.py", "--suite", "strings", *arguments]), \
                    mock.patch("sys.stderr"), mock.patch.object(runner, "simulator_tools") as support:
                with self.assertRaises(SystemExit) as error:
                    runner.main()
                self.assertEqual(error.exception.code, 2)
                support.assert_not_called()

    def test_json_rejects_duplicate_keys_and_nonfinite_constants(self):
        for text in ('{"x":1,"x":2}', '{"x":NaN}', '{"x":Infinity}', '{"x":-Infinity}'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                runner.strict_json(text)


if __name__ == "__main__":
    unittest.main()
