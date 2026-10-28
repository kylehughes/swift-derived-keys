"""Verify discovered package tests on a newly created, disposable iOS Simulator."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
from urllib.parse import parse_qs, unquote, urlsplit
import uuid


def selected_tests(enumeration, targets):
    if not targets or len(targets) != len(set(targets)):
        raise ValueError("Manifest has missing or duplicate test targets")
    if enumeration.get("errors") != [] or not enumeration.get("values"):
        raise ValueError("Enumeration has errors or no test plans")
    selected = []
    for plan in enumeration["values"]:
        if plan.get("disabledTests") != []:
            raise ValueError("Enumeration contains disabled tests")
        for test in plan.get("enabledTests", []):
            identity = test.get("identifier", "")
            if len(identity.split("/")) < 3:
                raise ValueError("Enumeration contains an invalid individual identity")
            selected.append(identity)
    if not selected or len(selected) != len(set(selected)):
        raise ValueError("Enumeration has zero or duplicate individual tests")
    if {case.split("/", 1)[0] for case in selected} != set(targets):
        raise ValueError("Enumeration differs from manifest test targets")
    return sorted(selected)


def observe_results(selection, targets, report, summary, device_id):
    cases = []
    arguments = []
    bundles = []
    parameter_parents = 0

    def visit(node, target=None):
        nonlocal parameter_parents
        kind = node.get("nodeType")
        if kind not in {"Test Plan", "Unit test bundle", "Test Suite", "Test Case", "Arguments"}:
            raise ValueError(f"Unsupported result node type: {kind!r}")
        if node.get("result") != "Passed":
            raise ValueError(f"A result node was skipped, failed, or unexecuted: {node.get('name')}")
        if kind == "Unit test bundle":
            target = node.get("name")
            bundles.append(target)
        if kind == "Arguments":
            raise ValueError("Argument result is not a direct child of a test case")
        children = node.get("children", [])
        if kind == "Test Case":
            identifier = node.get("nodeIdentifier", "")
            identity = f"{target}/{identifier}"
            address = urlsplit(node.get("nodeIdentifierURL", ""))
            if (not target or not identifier or address.scheme != "test" or address.netloc != "com.apple.xcode"
                    or not unquote(address.path).endswith("/" + identity)):
                raise ValueError("Result identity has no matching bundle and URL")
            cases.append(identity)
            parameterized = ":" in identifier.rsplit("/", 1)[-1]
            if parameterized and not children:
                raise ValueError(f"Parameterized test has no argument results: {identity}")
            if children:
                parameter_parents += 1
            for child in children:
                argument_url = urlsplit(child.get("nodeIdentifierURL", ""))
                if (child.get("nodeType") != "Arguments" or child.get("result") != "Passed"
                        or child.get("children") or argument_url.path != address.path
                        or argument_url.scheme != address.scheme or argument_url.netloc != address.netloc
                        or len(parse_qs(argument_url.query).get("args", [])) != 1):
                    raise ValueError(f"Missing, failed, skipped, or malformed argument result: {identity}")
                arguments.append(child["nodeIdentifierURL"])
            return
        for child in children:
            visit(child, target)

    if not selection or not report.get("testNodes"):
        raise ValueError("No selected tests or execution nodes")
    for node in report["testNodes"]:
        visit(node)
    if Counter(bundles) != Counter(targets):
        raise ValueError("Execution is missing or repeating a manifest test target")
    if Counter(cases) != Counter(selection):
        raise ValueError("Executed individual test identities differ from enumeration")
    if len(arguments) != len(set(arguments)):
        raise ValueError("Execution has duplicate argument identities")
    if (summary.get("result") != "Passed" or summary.get("totalTestCount") != len(cases)
            or summary.get("passedTests") != len(cases)
            or any(summary.get(key) != 0 for key in ("failedTests", "skippedTests", "expectedFailures"))
            or summary.get("testFailures") != []):
        raise ValueError("Summary is empty, failed, skipped, or disagrees with individual cases")
    leaf_count = len(cases) - parameter_parents + len(arguments)
    configurations = summary.get("devicesAndConfigurations", [])
    if len(configurations) != 1:
        raise ValueError("Expected exactly one destination and test configuration")
    configuration = configurations[0]
    if (configuration.get("device", {}).get("deviceId") != device_id
            or configuration.get("passedTests") != leaf_count
            or any(configuration.get(key) != 0 for key in ("failedTests", "skippedTests", "expectedFailures"))
            or [device.get("deviceId") for device in report.get("devices", [])] != [device_id]):
        raise ValueError("Device summary disagrees with executed cases and parameter arguments")
    return {
        "caseCount": len(cases), "argumentCount": len(arguments), "leafExecutionCount": leaf_count,
        "expected": selection, "observed": sorted(cases), "argumentIdentities": sorted(arguments),
        "targets": sorted(targets),
        "argumentDiscoveryLimit": "Flat discovery lists methods, not dynamic arguments; argument results are "
                                  "checked for nonemptiness, unique identities, success, and device-summary agreement.",
    }


def version(value):
    return tuple(int(part) for part in re.findall(r"\d+", value))


def choose_device(runtimes, device_types, requested_runtime=None):
    available = [runtime for runtime in runtimes if runtime.get("isAvailable") is True
                 and ".iOS-" in runtime.get("identifier", "")]
    if requested_runtime:
        available = [runtime for runtime in available if requested_runtime in
                     (runtime.get("identifier"), runtime.get("version"), runtime.get("name"))]
    if not available:
        raise ValueError("No matching available iOS Simulator runtime")
    runtime = max(available, key=lambda item: version(item["version"]))
    supported = runtime.get("supportedDeviceTypes")
    supported_ids = {item["identifier"] for item in supported} if supported else None
    runtime_version = version(runtime["version"]) + (0,) * (3 - len(version(runtime["version"])))
    candidates = [device for device in device_types if device.get("productFamily") == "iPhone"
                  and (supported_ids is None or device["identifier"] in supported_ids)
                  and version(device.get("minRuntimeVersionString", "0.0.0")) <= runtime_version
                  and version(device.get("maxRuntimeVersionString", "65535.255.255")) >= runtime_version]
    if not candidates:
        raise ValueError("Runtime has no supported iPhone device type")
    return runtime, candidates[0]


def cleanup_owned_device(device_id, execute):
    cleanup = {"deviceId": device_id, "attempted": device_id is not None, "passed": True}
    if device_id is None:
        return cleanup
    try:
        shutdown = execute(["xcrun", "simctl", "shutdown", device_id], "cleanup-shutdown", check=False)
        cleanup["shutdownReturncode"] = shutdown.returncode
    except Exception as error:
        cleanup["shutdownError"] = str(error)
    try:
        deletion = execute(["xcrun", "simctl", "delete", device_id], "cleanup-delete", check=False)
        inventory = execute(["xcrun", "simctl", "list", "devices", "-j"], "cleanup-inventory")
        devices = json.loads(inventory.stdout)["devices"]
        absent = not any(device.get("udid") == device_id for group in devices.values() for device in group)
        cleanup.update(deleteReturncode=deletion.returncode, confirmedAbsent=absent,
                       passed=deletion.returncode == 0 and absent)
    except Exception as error:
        cleanup.update(passed=False, error=str(error))
    return cleanup


def source_digests(root):
    paths = [root / "Package.swift", *sorted((root / "Sources").rglob("*.swift")),
             *sorted((root / "Tests").rglob("*.swift"))]
    return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


class Commands:
    def __init__(self, root, directory):
        self.root = root
        self.directory = directory
        self.records = []

    def run(self, arguments, name, timeout=120, check=True):
        print(f"Simulator check: {name}", flush=True)
        start = time.monotonic()
        record = {"name": name, "arguments": arguments}
        self.records.append(record)
        try:
            result = subprocess.run(arguments, cwd=self.root, capture_output=True, text=True, timeout=timeout)
            record["returncode"] = result.returncode
            (self.directory / f"{name}.stdout.log").write_text(result.stdout)
            (self.directory / f"{name}.stderr.log").write_text(result.stderr)
        except subprocess.TimeoutExpired as error:
            record["timedOut"] = True
            for stream in ("stdout", "stderr"):
                content = getattr(error, stream) or b""
                (self.directory / f"{name}.{stream}.log").write_bytes(
                    content.encode() if isinstance(content, str) else content)
            raise
        finally:
            record["elapsedSeconds"] = time.monotonic() - start
        if check and result.returncode != 0:
            raise RuntimeError(f"{name} exited {result.returncode}; see retained logs")
        return result

    def json(self, arguments, name):
        result = self.run(arguments, name)
        value = json.loads(result.stdout)
        (self.directory / f"{name}.json").write_text(json.dumps(value, indent=2) + "\n")
        return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", help="Available iOS runtime identifier, exact name, or version; default latest")
    parser.add_argument("--timeout", type=int, default=1200, help="Timeout in seconds for each xcodebuild phase")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    root = Path(__file__).resolve().parent.parent
    (root / ".build").mkdir(exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix="simulator-check-", dir=root / ".build"))
    commands = Commands(root, directory)
    receipt = {"schemaVersion": 1, "startedUTC": datetime.now(timezone.utc).isoformat(),
               "evidenceDirectory": str(directory), "status": "failed"}
    device_id = None
    device_name = "DerivedKeys-Check-" + str(uuid.uuid4())
    creation_attempted = False
    existing_devices = set()
    error = None

    def interrupted(_signal, _frame):
        raise InterruptedError("Simulator verification interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    try:
        receipt["sourcesBefore"] = source_digests(root)
        manifest = commands.json(["swift", "package", "dump-package"], "package")
        targets = [target["name"] for target in manifest["targets"] if target["type"] == "test"]
        if not targets:
            raise ValueError("Package has no test targets")
        commands.run(["xcodebuild", "-version"], "xcode-version")
        commands.run(["swift", "--version"], "swift-version")
        runtimes = commands.json(["xcrun", "simctl", "list", "runtimes", "-j"], "runtimes")["runtimes"]
        types = commands.json(["xcrun", "simctl", "list", "devicetypes", "-j"], "device-types")["devicetypes"]
        devices = commands.json(["xcrun", "simctl", "list", "devices", "-j"], "devices-before")["devices"]
        existing_devices = {device["udid"] for group in devices.values() for device in group}
        runtime, device_type = choose_device(runtimes, types, args.runtime)
        creation_attempted = True
        created = commands.run(["xcrun", "simctl", "create", device_name, device_type["identifier"],
                                runtime["identifier"]], "create")
        candidate = str(uuid.UUID(created.stdout.strip())).upper()
        if candidate in existing_devices:
            raise ValueError("Simulator creation returned an existing device")
        device_id = candidate
        receipt["ownedSimulator"] = {"id": device_id, "name": device_name, "runtime": runtime["identifier"],
                                     "deviceType": device_type["identifier"]}
        scheme = manifest["name"] + "-Package"
        common = ["xcodebuild", "test", "-scheme", scheme, "-destination",
                  "platform=iOS Simulator,id=" + device_id, "-derivedDataPath", str(directory / "DerivedData")]
        enumeration_path = directory / "enumeration.json"
        commands.run([*common, "-enumerate-tests", "-test-enumeration-style", "flat",
                      "-test-enumeration-format", "json", "-test-enumeration-output-path", str(enumeration_path)],
                     "enumerate", timeout=args.timeout)
        selection = selected_tests(json.loads(enumeration_path.read_text()), targets)
        receipt["selection"] = selection
        result_path = directory / "results.xcresult"
        execution = commands.run([*common, "-resultBundlePath", str(result_path), "-enableCodeCoverage", "YES",
                                  "-parallel-testing-enabled", "NO"], "test", timeout=args.timeout, check=False)
        report = commands.json(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path",
                                str(result_path)], "test-results")
        summary = commands.json(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path",
                                 str(result_path)], "summary")
        receipt["validation"] = observe_results(selection, targets, report, summary, device_id)
        if execution.returncode != 0:
            raise ValueError(f"xcodebuild test exited {execution.returncode}")
        receipt["sourcesAfter"] = source_digests(root)
        if receipt["sourcesBefore"] != receipt["sourcesAfter"]:
            raise ValueError("Package sources changed between discovery and execution")
        receipt["status"] = "passed"
    except (Exception, KeyboardInterrupt) as failure:
        error = str(failure) or type(failure).__name__
        receipt["error"] = error
    finally:
        if creation_attempted and device_id is None:
            try:
                devices = commands.json(["xcrun", "simctl", "list", "devices", "-j"], "recover-created-device")["devices"]
                matches = [device["udid"] for group in devices.values() for device in group
                           if device.get("name") == device_name and device["udid"] not in existing_devices]
                if len(matches) == 1:
                    device_id = matches[0]
                elif matches:
                    raise ValueError("Could not uniquely recover owned simulator")
            except Exception as failure:
                receipt["cleanupRecoveryError"] = str(failure)
        receipt["cleanup"] = cleanup_owned_device(device_id, commands.run)
        if receipt.get("cleanupRecoveryError") or not receipt["cleanup"]["passed"]:
            receipt["status"] = "failed"
        receipt["commands"] = commands.records
        receipt["finishedUTC"] = datetime.now(timezone.utc).isoformat()
        (directory / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Simulator verification {receipt['status']}; receipt: {directory / 'receipt.json'}")
    if error:
        print(error, file=sys.stderr)
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
