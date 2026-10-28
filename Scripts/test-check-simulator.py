"""Standard-library controls for Simulator identity, status, and cleanup validation."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

spec = importlib.util.spec_from_file_location("check_simulator", Path(__file__).with_name("check-simulator.py"))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class SimulatorValidationTests(unittest.TestCase):
    def setUp(self):
        self.targets = ["CoreTests", "UITests"]
        self.selection = ["CoreTests/Suite/plain()", "UITests/Suite/parameter(value:)"]
        self.device = "owned-device"
        self.enumeration = {"errors": [], "values": [{"disabledTests": [], "enabledTests": [
            {"identifier": identity} for identity in self.selection]}]}
        self.plain = {"nodeType": "Test Case", "name": "plain()", "nodeIdentifier": "Suite/plain()",
                      "nodeIdentifierURL": "test://com.apple.xcode/Package/CoreTests/Suite/plain()", "result": "Passed"}
        address = "test://com.apple.xcode/Package/UITests/Suite/parameter(value:)"
        self.parameter = {"nodeType": "Test Case", "name": "parameter(value:)", "result": "Passed",
                          "nodeIdentifier": "Suite/parameter(value:)", "nodeIdentifierURL": address,
                          "children": [{"nodeType": "Arguments", "result": "Passed", "name": str(i),
                                        "nodeIdentifierURL": address + "?args=" + str(i)} for i in (1, 2)]}
        self.report = {"devices": [{"deviceId": self.device}], "testNodes": [{"nodeType": "Test Plan",
            "result": "Passed", "children": [
                {"nodeType": "Unit test bundle", "name": "CoreTests", "result": "Passed", "children": [self.plain]},
                {"nodeType": "Unit test bundle", "name": "UITests", "result": "Passed", "children": [self.parameter]}]}]}
        self.summary = {"result": "Passed", "totalTestCount": 2, "passedTests": 2, "failedTests": 0,
                        "skippedTests": 0, "expectedFailures": 0, "testFailures": [],
                        "devicesAndConfigurations": [{"device": {"deviceId": self.device}, "passedTests": 3,
                            "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}]}

    def observe(self):
        return check.observe_results(self.selection, self.targets, self.report, self.summary, self.device)

    def test_valid_individual_and_parameter_results(self):
        self.assertEqual(check.selected_tests(self.enumeration, self.targets), self.selection)
        result = self.observe()
        self.assertEqual((result["caseCount"], result["argumentCount"], result["leafExecutionCount"]), (2, 2, 3))

    def test_xctest_url_may_omit_empty_parentheses(self):
        self.plain["nodeIdentifierURL"] = self.plain["nodeIdentifierURL"].removesuffix("()")
        self.observe()
        self.selection[0] = self.selection[0].removesuffix("()")
        self.observe()

    def test_xctest_url_still_requires_exact_target_suite_and_method(self):
        original = self.plain["nodeIdentifierURL"]
        for value in (original.replace("CoreTests", "WrongTests"), original.replace("Suite", "WrongSuite"),
                      original.replace("plain()", "other"), original + "extra", original + "?args=1",
                      original + "#fragment", original.replace("com.apple.xcode", "example.com")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.plain["nodeIdentifierURL"] = value
                self.observe()

    def test_parameterized_url_does_not_omit_signature(self):
        self.parameter["nodeIdentifierURL"] = self.parameter["nodeIdentifierURL"].replace("parameter(value:)", "parameter")
        with self.assertRaises(ValueError):
            self.observe()

    def test_empty_enumeration(self):
        self.enumeration["values"][0]["enabledTests"] = []
        with self.assertRaises(ValueError):
            check.selected_tests(self.enumeration, self.targets)

    def test_disabled_enumeration(self):
        self.enumeration["values"][0]["disabledTests"] = [{"identifier": self.selection[0]}]
        with self.assertRaises(ValueError):
            check.selected_tests(self.enumeration, self.targets)

    def test_missing_manifest_target_in_discovery(self):
        with self.assertRaises(ValueError):
            check.selected_tests(self.enumeration, self.targets + ["AbsentTests"])

    def test_empty_execution(self):
        self.report["testNodes"] = []
        with self.assertRaises(ValueError):
            self.observe()

    def test_failed_case(self):
        self.plain["result"] = "Failed"
        with self.assertRaises(ValueError):
            self.observe()

    def test_skipped_case(self):
        self.plain["result"] = "Skipped"
        with self.assertRaises(ValueError):
            self.observe()

    def test_skipped_and_failed_arguments(self):
        for status in ("Skipped", "Failed", "Not Run"):
            with self.subTest(status=status):
                self.parameter["children"][0]["result"] = status
                with self.assertRaises(ValueError):
                    self.observe()

    def test_missing_case(self):
        self.report["testNodes"][0]["children"][0]["children"] = []
        with self.assertRaises(ValueError):
            self.observe()

    def test_missing_target(self):
        self.report["testNodes"][0]["children"].pop()
        with self.assertRaises(ValueError):
            self.observe()

    def test_missing_all_parameter_arguments(self):
        self.parameter["children"] = []
        with self.assertRaises(ValueError):
            self.observe()

    def test_missing_argument_disagrees_with_leaf_summary(self):
        self.parameter["children"].pop()
        with self.assertRaises(ValueError):
            self.observe()

    def test_duplicate_argument(self):
        self.parameter["children"].append(copy.deepcopy(self.parameter["children"][0]))
        with self.assertRaises(ValueError):
            self.observe()

    def test_summary_count_or_status_must_agree(self):
        for key, value in (("totalTestCount", 0), ("passedTests", 1), ("skippedTests", 1), ("failedTests", 1)):
            with self.subTest(key=key):
                original = self.summary[key]
                self.summary[key] = value
                with self.assertRaises(ValueError):
                    self.observe()
                self.summary[key] = original

    def test_wrong_device(self):
        self.summary["devicesAndConfigurations"][0]["device"]["deviceId"] = "existing-device"
        with self.assertRaises(ValueError):
            self.observe()


class CleanupTests(unittest.TestCase):
    def cleanup(self, delete_code=0, remains=False, shutdown_raises=False):
        self.commands = []

        def execute(arguments, name, **_kwargs):
            self.commands.append(arguments)
            if name == "cleanup-shutdown" and shutdown_raises:
                raise RuntimeError("shutdown unavailable")
            if name == "cleanup-inventory":
                devices = [{"udid": "existing-device"}]
                if remains:
                    devices.append({"udid": "owned-device"})
                return subprocess.CompletedProcess(arguments, 0, json.dumps({"devices": {"runtime": devices}}), "")
            return subprocess.CompletedProcess(arguments, delete_code if name == "cleanup-delete" else 0, "", "")

        return check.cleanup_owned_device("owned-device", execute)

    def test_deletes_only_owned_device_and_confirms_absence(self):
        self.assertTrue(self.cleanup()["passed"])
        self.assertEqual(self.commands[1], ["xcrun", "simctl", "delete", "owned-device"])
        self.assertNotIn("existing-device", [item for command in self.commands for item in command])

    def test_delete_failure_is_not_success(self):
        self.assertFalse(self.cleanup(delete_code=1)["passed"])

    def test_device_remaining_is_not_success(self):
        self.assertFalse(self.cleanup(remains=True)["passed"])

    def test_shutdown_exception_still_attempts_delete(self):
        self.assertTrue(self.cleanup(shutdown_raises=True)["passed"])
        self.assertEqual(self.commands[1][2], "delete")

    def test_no_created_device_needs_no_cleanup(self):
        self.assertEqual(check.cleanup_owned_device(None, None),
                         {"deviceId": None, "attempted": False, "passed": True})


class RuntimeTests(unittest.TestCase):
    def test_latest_available_runtime_and_supported_phone(self):
        runtimes = [{"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0", "version": "26.0", "isAvailable": True},
                    {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "version": "27.0", "isAvailable": True,
                     "supportedDeviceTypes": [{"identifier": "phone"}]}]
        types = [{"identifier": "future", "productFamily": "iPhone", "minRuntimeVersionString": "28.0.0"},
                 {"identifier": "phone", "productFamily": "iPhone", "minRuntimeVersionString": "26.0.0"}]
        runtime, device = check.choose_device(runtimes, types)
        self.assertEqual(runtime["version"], "27.0")
        self.assertEqual(device["identifier"], "phone")
        self.assertEqual(check.choose_device(runtimes, types, "26.0")[0]["version"], "26.0")

    def test_unavailable_runtime_is_rejected(self):
        with self.assertRaises(ValueError):
            check.choose_device([], [])


if __name__ == "__main__":
    unittest.main()
