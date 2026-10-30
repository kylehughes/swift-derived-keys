#!/usr/bin/env python3
"""Run opt-in UIKit sizing or String timings in Release and retain a local evidence bundle.

With no destination, the runner creates and removes its own disposable iOS Simulator.
An explicit destination must be platform=iOS,id=UDID or platform=iOS Simulator,id=UUID;
no lifecycle commands are issued for explicit devices. Xcode installs and runs the test bundle.
"""
import argparse
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import plistlib
import re
import signal
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
TARGET = "DerivedKeysUIExampleTests"
TEST = TARGET + "/UIKitSizingBenchmarkTests/testSizingBenchmarks"
ATTACHMENT = "DerivedKeysUIKitBenchmarks.json"
SUITES = {
    "sizing": (TEST, ATTACHMENT),
    "strings": (TARGET + "/UIKitStringBenchmarkTests/testStringRepresentationBenchmarks",
                "DerivedKeysUIKitStringBenchmarks.json"),
}
COST_INTERPRETATION = (
    "Separate stable-input phases include their observation overhead; "
    "subtracting phases does not isolate LRU bookkeeping"
)
COST_BOUNDARIES = {
    "direct-warm-fit": "Warmed UIKit sizeThatFits plus preallocated size-buffer writes",
    "snapshot-capture-64-slots":
        "Actual configured key-path capture plus 64-slot snapshot-buffer writes; hashing after timing",
    "hash-preconstructed-snapshot":
        "Public hashValue of 64 preconstructed equivalent snapshots plus UInt64 accumulation",
    "warm-size-lookup": "Full warmed SizeCache.size lookup plus preallocated size-buffer writes",
    "text-getter-64-slots":
        "UITextView.text getter plus 64-slot String-buffer writes; validation and UTF-8 counts after timing",
}


def simulator_tools():
    spec = importlib.util.spec_from_file_location("check_simulator", ROOT / "Scripts/check-simulator.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def destination(value):
    pairs = [part.split("=", 1) for part in value.split(",")]
    if len(pairs) != 2 or any(len(pair) != 2 for pair in pairs):
        raise ValueError("Destination requires exactly platform and id")
    fields = dict(pairs)
    if set(fields) != {"platform", "id"} or fields["platform"] not in {"iOS", "iOS Simulator"} or not fields["id"]:
        raise ValueError("Destination must be platform=iOS,id=UDID or platform=iOS Simulator,id=UUID")
    return fields


def source_digests():
    paths = {ROOT / "Package.swift", Path(__file__).resolve(), ROOT / "Scripts/check-simulator.py"}
    paths.update(path for path in (ROOT / "Benchmarks").iterdir() if path.suffix in {".py", ".sh"})
    for folder in ("Sources", "Tests", "Examples"):
        paths.update(path for path in (ROOT / folder).rglob("*") if path.is_file())
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(paths)}


def inject_environment(document, environment):
    """Handle both modern TestConfigurations and legacy target-keyed xctestrun files."""
    targets = []
    if "TestConfigurations" in document:
        for configuration in document["TestConfigurations"]:
            for target in configuration.get("TestTargets", []):
                if target.get("BlueprintName") == TARGET:
                    targets.append(target)
    else:
        for name, target in document.items():
            if isinstance(target, dict) and (name == TARGET or target.get("BlueprintName") == TARGET):
                targets.append(target)
    if len(targets) != 1:
        raise ValueError(f"Expected one {TARGET} target in xctestrun; found {len(targets)}")
    targets[0].setdefault("EnvironmentVariables", {}).update(environment)
    return document


def strict_json(text):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON object key: " + key)
            result[key] = value
        return result

    def reject_constant(value):
        raise ValueError("Nonfinite JSON constant: " + value)

    return json.loads(text, object_pairs_hook=unique_object, parse_constant=reject_constant)


def read_attachment(directory, device_id, suite="sizing"):
    selected_test, attachment_name = SUITES[suite]
    manifest = strict_json((directory / "manifest.json").read_text())
    matches = []
    support = simulator_tools()
    for test in manifest:
        identity = test.get("testIdentifier", "").removesuffix("()")
        if identity not in {selected_test, selected_test.split("/", 1)[1]}:
            continue
        if not support.test_identity_matches_url(selected_test, test.get("testIdentifierURL", "")):
            raise ValueError("Benchmark attachment test URL does not match its identity")
        for attachment in test.get("attachments", []):
            name = attachment.get("suggestedHumanReadableName", "")
            if name == attachment_name or re.fullmatch(
                    re.escape(Path(attachment_name).stem) + r"_[0-9]+_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-"
                    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.json", name):
                if attachment.get("deviceId") != device_id or attachment.get("isAssociatedWithFailure") is not False:
                    raise ValueError("Benchmark attachment has an unexpected device or failure association")
                path = directory / attachment["exportedFileName"]
                if path.resolve().parent != directory.resolve():
                    raise ValueError("Attachment export path escapes its directory")
                matches.append(path)
    if len(matches) != 1 or not matches[0].is_file() or matches[0].stat().st_size == 0:
        raise ValueError("Expected one nonempty benchmark JSON attachment")
    return strict_json(matches[0].read_text()), matches[0]


def validate_payload(payload, iterations, trials, suite="sizing"):
    if suite == "strings":
        return validate_string_payload(payload, iterations, trials)
    # The benchmark's versioned contract is validated below; malformed or missing data fails closed.
    if payload.get("schemaVersion") != 1:
        raise ValueError("Unsupported benchmark attachment schema")
    if payload.get("iterations") != iterations or payload.get("trials") != trials or payload.get("capacity") != 16:
        raise ValueError("Benchmark parameters differ from the requested bounded workload")
    validation = validate_rows(payload, iterations, trials)
    validation["costDiagnostics"] = validate_cost_diagnostics(payload)
    return validation


def validate_rows(payload, iterations, trials):
    workloads = {"UILabel-single-line", "UILabel-multiline", "UILabel-attributed", "UITextView",
                 "DocumentContentView-text", "DocumentContentView-button"}
    scenarios = {"warm-one-view", "equivalent-pool-views", "width-changes", "content-font-changes", "mixed-bounded"}
    expected = {(workload, scenario) for workload in workloads for scenario in scenarios}
    expected.update(("DocumentContentView-parent", scenario) for scenario in
                    {"warm-parent", "equivalent-pool-views", "parent-only-spacing-miss",
                     "width-changes", "content-font-changes", "mixed-bounded"})
    if payload.get("benchmarkEnabled") is not True or payload.get("warmupIterationsPerView") != 4:
        raise ValueError("Timings were not enabled or warmup contract differs")
    runtime = payload.get("runtime", {})
    if any(not isinstance(runtime.get(key), str) or not runtime[key]
           for key in ("deviceName", "model", "systemName", "systemVersion")) or type(runtime.get("isSimulator")) is not bool:
        raise ValueError("Missing actual device runtime metadata")
    rows = payload.get("rows", [])
    identities = [(row.get("workload"), row.get("scenario")) for row in rows]
    if len(identities) != len(expected) or set(identities) != expected:
        raise ValueError("Benchmark rows are missing, duplicated, or unexpected")

    def positive_number(value):
        return type(value) in (int, float) and math.isfinite(value) and value > 0

    for row in rows:
        if (row.get("iterations") != iterations or row.get("capacity") != 16
                or row.get("resultsValidated") is not True or not row.get("timingBoundary")):
            raise ValueError("Invalid row parameters, result validation, or timing boundary")
        samples = row.get("trials", [])
        if len(samples) != trials or [sample.get("index") for sample in samples] != list(range(trials)):
            raise ValueError("Missing, duplicated, or out-of-order trial indices")
        for sample in samples:
            if sample.get("resultsValidated") is not True or type(sample.get("directFirst")) is not bool:
                raise ValueError("Trial has no successful result comparison or execution order")
            for key in ("directNanoseconds", "cachedNanoseconds", "directNanosecondsPerOperation",
                        "cachedNanosecondsPerOperation", "checksum", "expectedChecksum"):
                if not positive_number(sample.get(key)):
                    raise ValueError("Trial timing or checksum is nonpositive or nonfinite")
            if sample["checksum"] != sample["expectedChecksum"]:
                raise ValueError("Direct and cached result checksums disagree")
            for mode in ("direct", "cached"):
                if not math.isclose(sample[mode + "NanosecondsPerOperation"],
                                    sample[mode + "Nanoseconds"] / iterations, rel_tol=1e-12):
                    raise ValueError("Per-operation timing disagrees with total timing")
        diagnostics = row.get("diagnostics", {})
        if (diagnostics.get("resultsValidated") is not True
                or diagnostics.get("measurementCountsInferredFromMisses") is not row["workload"].startswith("DocumentContentView-")
                or not diagnostics.get("ownership") or type(diagnostics.get("evictionObserved")) is not bool):
            raise ValueError("Invalid diagnostics contract")
        counts = {}
        for kind in ("observedMembershipHits", "observedMembershipMisses", "entryCounts"):
            values = diagnostics.get(kind, {})
            if set(values) != {"parent", "text", "button", "leaf"} or any(
                    type(value) is not int or value < 0 or (kind == "entryCounts" and value > 16)
                    for value in values.values()):
                raise ValueError("Invalid bounded cache diagnostics")
            counts[kind] = values
        hits, misses = counts["observedMembershipHits"], counts["observedMembershipMisses"]
        scenario, workload = row["scenario"], row["workload"]
        if workload == "DocumentContentView-parent":
            if (hits["parent"] + misses["parent"] != iterations
                    or any(hits[child] + misses[child] != misses["parent"] for child in ("text", "button"))
                    or hits["leaf"] or misses["leaf"]):
                raise ValueError("Parent and child membership counts do not conserve requests")
        else:
            active = {"DocumentContentView-text": "text", "DocumentContentView-button": "button"}.get(workload, "leaf")
            if (hits[active] + misses[active] != iterations
                    or any(hits[cache] or misses[cache] for cache in hits if cache != active)):
                raise ValueError("Leaf membership counts do not conserve requests")
        if workload == "DocumentContentView-button":
            expected_entries = {"content-font-changes": 3, "mixed-bounded": 6}.get(scenario)
            if expected_entries is not None and counts["entryCounts"]["button"] != expected_entries:
                raise ValueError("Button entry count differs from its bounded semantic keys")
        if scenario == "mixed-bounded" and iterations >= 48:
            if not sum(hits.values()) or not sum(misses.values()):
                raise ValueError("Mixed workload did not demonstrate both reuse and misses")
            if workload != "DocumentContentView-button" and diagnostics["evictionObserved"] is not True:
                raise ValueError("Mixed workload did not demonstrate eviction")
        if workload == "DocumentContentView-parent":
            if scenario in {"warm-parent", "equivalent-pool-views"}:
                if hits != {"parent": iterations, "text": 0, "button": 0, "leaf": 0} or any(misses.values()):
                    raise ValueError("Warm parent unexpectedly accessed child caches or missed")
            elif scenario == "parent-only-spacing-miss":
                if misses["parent"] != iterations or hits["text"] != iterations or hits["button"] != iterations:
                    raise ValueError("Parent-only misses did not preserve child hits")
        elif scenario in {"warm-one-view", "equivalent-pool-views"}:
            cache = {"DocumentContentView-text": "text", "DocumentContentView-button": "button"}.get(workload, "leaf")
            if hits[cache] != iterations or any(misses.values()):
                raise ValueError("Warm leaf did not hit on every operation")
    return {"rowCount": len(rows), "trialsPerRow": trials, "checksumsValidated": True,
            "diagnosticsValidated": True}


def validate_cost_diagnostics(payload):
    workloads = {"UILabel-single-line", "UILabel-multiline", "UILabel-attributed", "UITextView"}
    phases = set(COST_BOUNDARIES) - {"text-getter-64-slots"}
    expected = {(workload, phase) for workload in workloads for phase in phases}
    expected.add(("UITextView", "text-getter-64-slots"))
    if payload.get("costDiagnosticsInterpretation") != COST_INTERPRETATION:
        raise ValueError("Unsupported cost diagnostic interpretation")
    rows = payload.get("costDiagnostics", [])
    identities = [(row.get("workload"), row.get("phase")) for row in rows]
    if len(identities) != 17 or set(identities) != expected:
        raise ValueError("Cost diagnostic rows are missing, duplicated, or unexpected")
    for row in rows:
        if (type(row.get("iterations")) is not int or row["iterations"] != 512
                or row.get("resultsValidated") is not True
                or row.get("timingBoundary") != COST_BOUNDARIES[row["phase"]]):
            raise ValueError("Unsupported cost diagnostic parameters or timing boundary")
        samples = row.get("trials", [])
        if (len(samples) != 5 or any(type(sample.get("index")) is not int for sample in samples)
                or [sample["index"] for sample in samples] != list(range(5))):
            raise ValueError("Cost diagnostics require five distinct ordered trials")
        for sample in samples:
            elapsed, per_operation = sample.get("elapsedNanoseconds"), sample.get("nanosecondsPerOperation")
            if (sample.get("resultsValidated") is not True or type(elapsed) is not int
                    or not 0 < elapsed < 2 ** 64 or type(per_operation) not in (int, float)
                    or not math.isfinite(per_operation) or per_operation <= 0
                    or not math.isclose(per_operation, elapsed / 512, rel_tol=1e-12)):
                raise ValueError("Invalid cost diagnostic timing or result validation")
            checksum, expected_checksum = sample.get("checksum"), sample.get("expectedChecksum")
            if (not isinstance(checksum, str) or checksum != expected_checksum
                    or re.fullmatch(r"(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?", checksum) is None
                    or not Decimal(checksum).is_finite() or Decimal(checksum) < 0):
                raise ValueError("Invalid or mismatched cost diagnostic checksums")
    return {"rowCount": 17, "iterationsPerTrial": 512, "trialsPerRow": 5,
            "checksumsValidated": True, "interpretation": COST_INTERPRETATION}


STRING_CONTENTS = ("short-ascii", "long-ascii", "long-non-ascii")
STRING_SCENARIOS = ("repeated-warm", "mutation-return", "mixed-bounded")
STRING_STRATEGIES = ("direct", "uikit-text", "model-text", "contiguous-uikit-text")
STRING_PHASES = ("dependency-read-64-slots", "snapshot-capture-64-slots",
                 "string-hash-pre-read", "snapshot-hash-preconstructed")


STRING_TIMING_SUFFIX = (
    "complete direct fit or SizeCache.size including dependency reads, per-request normalization where selected, "
    "snapshot, hashing, equality, lookup/miss fit, and preallocated CGSize-buffer write"
)
STRING_TIMING_BOUNDARIES = {
    scenario: ("No configuration in loop; " if scenario == "repeated-warm" else
               "Identical model.text and UITextView.text setters before every request; ") + STRING_TIMING_SUFFIX
    for scenario in STRING_SCENARIOS
}
STRING_PHASE_INTERPRETATION = (
    "Fixed phase order; separate observations include buffer/call overhead and are not additive or suitable for exact subtraction. "
    "String hashing uses pre-read values; complete lookup includes all capture and normalization."
)
STRING_PHASE_BOUNDARIES = {
    "dependency-read-64-slots": "Selected dependency read including makeContiguousUTF8 only for contiguous-uikit-text, plus preallocated 64-slot String writes",
    "snapshot-capture-64-slots": "SizeCache.snapshot capture of actual selected text/font key paths, including selected normalization, plus preallocated 64-slot snapshot writes",
    "string-hash-pre-read": "Public hashValue of 64 pre-read Strings, no getter/normalization in timing, plus UInt64 accumulation and non-inlined call",
    "snapshot-hash-preconstructed": "Public hashValue of 64 preconstructed snapshots, no capture in timing, plus UInt64 accumulation and non-inlined call",
}
STRING_FIXTURE_OWNERSHIP = (
    "Fresh independent fixture per arm/trial; same native model and actual UITextView configuration; "
    "no timed counters; rotating four-arm order"
)
STRING_COUNTS = {
    "direct": (0, 0, 128, 0, False, False),
    "repeated-warm": (128, 0, 0, 1, False, False),
    "mutation-return": (124, 4, 4, 5, False, True),
    "mixed-bounded": (65, 63, 63, 16, True, False),
}


def validate_string_payload(payload, iterations, trials):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    def positive(value):
        return type(value) in (int, float) and math.isfinite(value) and value > 0

    def identities(rows, keys, expected):
        actual = [tuple(row.get(key) for key in keys) for row in rows]
        require(len(actual) == len(expected) and set(actual) == expected,
                "String benchmark rows are missing, duplicated, or unexpected")

    def samples(row, count, operations, checksum_string=False):
        values = row.get("trials", [])
        require(len(values) == count and all(type(value.get("index")) is int for value in values)
                and [value["index"] for value in values] == list(range(count)),
                "String benchmark trials must be distinct and ordered")
        for value in values:
            elapsed, per_operation = value.get("elapsedNanoseconds"), value.get("nanosecondsPerOperation")
            require(type(elapsed) is int and 0 < elapsed < 2 ** 64 and positive(per_operation)
                    and math.isclose(per_operation, elapsed / operations, rel_tol=1e-12)
                    and value.get("resultsValidated") is True, "Invalid string benchmark timing or equivalence")
            checksum, expected = value.get("checksum"), value.get("expectedChecksum")
            if checksum_string:
                require(isinstance(checksum, str) and checksum == expected
                        and re.fullmatch(r"(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?", checksum) is not None
                        and Decimal(checksum).is_finite() and Decimal(checksum) >= 0,
                        "Invalid string phase checksum")
            else:
                require(positive(checksum) and type(expected) in (int, float) and checksum == expected,
                        "Invalid string benchmark checksum")
        return values

    require(type(payload.get("schemaVersion")) is int and payload["schemaVersion"] == 1,
            "Unsupported string benchmark schema")
    require(iterations == 128 and trials == 9 and type(payload.get("iterations")) is int
            and payload["iterations"] == 128 and type(payload.get("trials")) is int
            and payload["trials"] == 9 and type(payload.get("capacity")) is int
            and payload["capacity"] == 16 and payload.get("benchmarkEnabled") is True,
            "String benchmark requires 128 operations, nine trials, and capacity 16")
    require(payload.get("fixtureOwnership") == STRING_FIXTURE_OWNERSHIP
            and type(payload.get("warmupIterationsPerView")) is int and payload["warmupIterationsPerView"] == 8
            and type(payload.get("width")) is int and payload["width"] == 180
            and type(payload.get("fontPointSize")) is int and payload["fontPointSize"] == 17,
            "String fixture configuration changed")
    runtime = payload.get("runtime", {})
    require(all(isinstance(runtime.get(key), str) and runtime[key]
                for key in ("deviceName", "model", "systemName", "systemVersion"))
            and type(runtime.get("isSimulator")) is bool, "Missing string benchmark runtime")
    rows = payload.get("rows", [])
    identities(rows, ("content", "scenario", "strategy"),
               {(content, scenario, strategy) for content in STRING_CONTENTS
                for scenario in STRING_SCENARIOS for strategy in STRING_STRATEGIES})
    checksums = {}
    for row in rows:
        require(type(row.get("iterations")) is int and row["iterations"] == 128
                and type(row.get("capacity")) is int and row["capacity"] == 16
                and row.get("resultsValidated") is True and row.get("timingBoundary") == STRING_TIMING_BOUNDARIES[row["scenario"]],
                "Invalid string row parameters or timing boundary")
        values = samples(row, 9, 128)
        for value in values:
            require(type(value.get("orderIndex")) is int
                    and value["orderIndex"] == (STRING_STRATEGIES.index(row["strategy"]) - value["index"]) % 4,
                    "String strategy order does not rotate by trial")
            identity = (row["content"], row["scenario"], value["index"])
            if identity in checksums:
                require(checksums[identity] == value["checksum"], "String strategy results disagree")
            checksums[identity] = value["checksum"]
        diagnostic = row.get("diagnostics", {})
        require(type(diagnostic.get("iterations")) is int and diagnostic["iterations"] == 128
                and diagnostic.get("resultsValidated") is True
                and type(diagnostic.get("distinctHeightsObserved")) is bool
                and diagnostic["distinctHeightsObserved"] is (row["scenario"] != "repeated-warm")
                and type(diagnostic.get("restoredResultValidated")) is bool
                and diagnostic["restoredResultValidated"] is (row["scenario"] == "mutation-return")
                and type(diagnostic.get("evictionObserved")) is bool
                and type(diagnostic.get("returnHitValidated")) is bool,
                "Invalid string diagnostic validation flags")
        for key in ("hits", "misses", "measurementCount", "entryCount"):
            require(type(diagnostic.get(key)) is int and diagnostic[key] >= 0,
                    "Invalid string diagnostic counts")
        expected = STRING_COUNTS["direct" if row["strategy"] == "direct" else row["scenario"]]
        require(tuple(diagnostic[key] for key in ("hits", "misses", "measurementCount", "entryCount",
                                                  "evictionObserved", "returnHitValidated")) == expected,
                "String counts, invalidation, reuse, or eviction differ from the bounded workload")
    require(type(payload.get("phaseIterations")) is int and payload["phaseIterations"] == 512
            and type(payload.get("phaseTrials")) is int and payload["phaseTrials"] == 5
            and payload.get("phaseOrder") == list(STRING_PHASES)
            and payload.get("phaseInterpretation") == STRING_PHASE_INTERPRETATION,
            "Invalid string cost phase contract")
    phases = payload.get("costDiagnostics", [])
    identities(phases, ("content", "strategy", "phase"),
               {(content, strategy, phase) for content in STRING_CONTENTS
                for strategy in STRING_STRATEGIES[1:] for phase in STRING_PHASES})
    for row in phases:
        require(type(row.get("iterations")) is int and row["iterations"] == 512
                and row.get("resultsValidated") is True
                and row.get("timingBoundary") == STRING_PHASE_BOUNDARIES[row["phase"]],
                "Invalid string cost phase parameters or boundary")
        samples(row, 5, 512, checksum_string=True)
    representations = payload.get("representations", [])
    identities(representations, ("content", "strategy"),
               {(content, strategy) for content in STRING_CONTENTS for strategy in STRING_STRATEGIES[1:]})
    lengths = {}
    for representation in representations:
        require(type(representation.get("utf8Length")) is int
                and representation["utf8Length"] > 0
                and all(type(representation.get(key)) is bool for key in
                        ("isContiguousUTF8", "rawUIKitIsContiguousUTF8", "sourceIsContiguousUTF8")),
                "Invalid string representation metadata")
        content = representation["content"]
        require(content not in lengths or lengths[content] == representation["utf8Length"],
                "String representation lengths disagree across strategies")
        lengths[content] = representation["utf8Length"]
    return {"rowCount": 36, "trialsPerRow": 9, "checksumsValidated": True,
            "diagnosticsValidated": True, "representationCount": 9,
            "costDiagnostics": {"rowCount": 36, "iterationsPerTrial": 512, "trialsPerRow": 5}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=SUITES, default="sizing", help="Benchmark suite (default sizing)")
    parser.add_argument("--destination", help="Explicit platform=iOS,id=UDID or platform=iOS Simulator,id=UUID")
    parser.add_argument("--development-team", help="Locally configured signing team for an explicit physical device")
    parser.add_argument("--runtime", help="Runtime for the automatically created Simulator; default latest available")
    parser.add_argument("--iterations", type=int, default=128, help="Operations per trial (48–512; default 128)")
    parser.add_argument("--trials", type=int, default=9, help="Measured trials (3–30; default 9)")
    parser.add_argument("--timeout", type=int, default=1200, help="Timeout seconds per xcodebuild phase")
    parser.add_argument("--output", type=Path, help="New output directory; default allocates under .build")
    args = parser.parse_args()
    if not 48 <= args.iterations <= 512 or not 3 <= args.trials <= 30 or args.timeout <= 0:
        parser.error("Require iterations 48–512, trials 3–30, and positive timeout")
    if args.suite == "strings" and (args.iterations != 128 or args.trials != 9):
        parser.error("The strings suite requires exactly 128 iterations and 9 trials")
    selected_test, _ = SUITES[args.suite]
    try:
        chosen = destination(args.destination) if args.destination else None
    except ValueError as error:
        parser.error(str(error))
    if args.runtime and chosen:
        parser.error("--runtime applies only to the automatically created Simulator")
    if args.development_team and (not chosen or chosen["platform"] != "iOS"):
        parser.error("--development-team requires an explicit physical iOS destination")
    if args.output:
        directory = args.output.expanduser().resolve()
        directory.mkdir(parents=True, exist_ok=False)
    else:
        (ROOT / ".build").mkdir(exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix="uikit-benchmark-", dir=ROOT / ".build"))
    print(f"UIKit benchmark artifacts: {directory}", flush=True)
    support = simulator_tools()
    commands = support.Commands(ROOT, directory)
    receipt = {"schemaVersion": 1, "startedUTC": datetime.now(timezone.utc).isoformat(),
               "evidenceDirectory": str(directory), "status": "failed", "configuration": "Release",
               "codeCoverage": False, "parallelTesting": False, "iterations": args.iterations,
               "trials": args.trials, "capacity": 16, "selectedTest": selected_test, "suite": args.suite}
    owned_id = None
    creation_attempted = False
    existing_devices = set()
    owned_name = "DerivedKeys-Benchmark-" + str(uuid.uuid4())

    def interrupted(_signal, _frame):
        raise InterruptedError("UIKit benchmark interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    try:
        receipt["sourcesBefore"] = source_digests()
        receipt["candidate"] = {
            "head": commands.run(["git", "-c", "core.fsmonitor=false", "rev-parse", "HEAD"], "git-head").stdout.strip(),
            "statusPorcelain": commands.run(["git", "-c", "core.fsmonitor=false", "status", "--porcelain=v1", "--untracked-files=all"], "git-status").stdout,
        }
        diff = commands.run(["git", "-c", "core.fsmonitor=false", "diff", "HEAD", "--binary"], "git-diff").stdout
        receipt["candidate"]["trackedDiffSHA256"] = hashlib.sha256(diff.encode()).hexdigest()
        receipt["candidate"]["dirty"] = bool(receipt["candidate"]["statusPorcelain"])
        for name, command in (
            ("xcode-version", ["xcodebuild", "-version"]),
            ("swift-version", ["xcrun", "swift", "--version"]),
            ("host-os", ["sw_vers"]),
            ("host-hardware", ["sysctl", "hw.model", "hw.machine", "hw.ncpu", "hw.memsize"]),
        ):
            receipt[name] = commands.run(command, name).stdout.strip()
        if not chosen:
            runtimes = commands.json(["xcrun", "simctl", "list", "runtimes", "-j"], "runtimes")["runtimes"]
            types = commands.json(["xcrun", "simctl", "list", "devicetypes", "-j"], "device-types")["devicetypes"]
            devices = commands.json(["xcrun", "simctl", "list", "devices", "-j"], "devices-before")["devices"]
            existing_devices = {device["udid"] for group in devices.values() for device in group}
            runtime, device_type = support.choose_device(runtimes, types, args.runtime)
            creation_attempted = True
            created = commands.run(["xcrun", "simctl", "create", owned_name, device_type["identifier"],
                                    runtime["identifier"]], "create")
            candidate = str(uuid.UUID(created.stdout.strip())).upper()
            if candidate in existing_devices:
                raise ValueError("Simulator creation returned an existing device")
            owned_id = candidate
            chosen = {"platform": "iOS Simulator", "id": owned_id}
            receipt["ownedSimulator"] = {"id": owned_id, "name": owned_name, "runtime": runtime,
                                         "deviceType": device_type}
        receipt["requestedDestination"] = chosen
        sdk = "iphoneos" if chosen["platform"] == "iOS" else "iphonesimulator"
        receipt["sdkVersion"] = commands.run(["xcrun", "--sdk", sdk, "--show-sdk-version"], "sdk-version").stdout.strip()
        receipt["sdkPath"] = commands.run(["xcrun", "--sdk", sdk, "--show-sdk-path"], "sdk-path").stdout.strip()
        destination_string = f"platform={chosen['platform']},id={chosen['id']}"
        build = ["xcodebuild", "build-for-testing", "-scheme", "DerivedKeys-Package", "-configuration", "Release",
                 "-destination", destination_string, "-derivedDataPath", str(directory / "DerivedData"),
                 "-enableCodeCoverage", "NO", "-parallel-testing-enabled", "NO"]
        if args.development_team:
            build.append("DEVELOPMENT_TEAM=" + args.development_team)
        commands.run(build, "build-for-testing", timeout=args.timeout)
        products = directory / "DerivedData/Build/Products"
        specifications = sorted(products.glob("*.xctestrun"))
        if len(specifications) != 1:
            raise ValueError(f"Expected one generated xctestrun file, found {len(specifications)}")
        environment = {"DERIVEDKEYS_UIKIT_BENCHMARK": "1", "DERIVEDKEYS_UIKIT_ITERATIONS": str(args.iterations),
                       "DERIVEDKEYS_UIKIT_TRIALS": str(args.trials)}
        document = inject_environment(plistlib.loads(specifications[0].read_bytes()), environment)
        # Keep this beside the original: __TESTROOT__ paths resolve relative to the xctestrun file.
        specification = products / "UIKitBenchmark.xctestrun"
        specification.write_bytes(plistlib.dumps(document))
        receipt["testEnvironment"] = environment
        result_path = directory / "results.xcresult"
        execution = commands.run(["xcodebuild", "test-without-building", "-xctestrun", str(specification),
                                  "-destination", destination_string, "-configuration", "Release",
                                  "-resultBundlePath", str(result_path), "-enableCodeCoverage", "NO",
                                  "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
                                  "-only-testing:" + selected_test],
                                 "test-without-building", timeout=args.timeout, check=False)
        report = commands.json(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(result_path)],
                               "test-results")
        summary = commands.json(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_path)],
                                "summary")
        # xcresult identifiers include parentheses even though -only-testing uses the method name.
        receipt["testValidation"] = support.observe_results([selected_test + "()"], [TARGET], report, summary, chosen["id"])
        receipt["actualDestination"] = {"platform": chosen["platform"], "devices": report.get("devices"),
                                         "configurations": summary.get("devicesAndConfigurations")}
        attachments = directory / "attachments"
        # Export all attachments after checking that this bundle contains exactly the requested test.
        # xcresulttool's test-id grammar differs from xcodebuild's -only-testing grammar.
        commands.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result_path),
                      "--output-path", str(attachments)], "export-attachments")
        payload, attachment = read_attachment(attachments, chosen["id"], args.suite)
        receipt["payloadValidation"] = validate_payload(payload, args.iterations, args.trials, args.suite)
        receipt["actualDestination"]["runtime"] = payload["runtime"]
        if payload["runtime"]["isSimulator"] != (chosen["platform"] == "iOS Simulator"):
            raise ValueError("Attachment runtime disagrees with destination platform")
        receipt["attachment"] = str(attachment.relative_to(directory))
        receipt["attachmentSHA256"] = hashlib.sha256(attachment.read_bytes()).hexdigest()
        if execution.returncode != 0:
            raise ValueError(f"test-without-building exited {execution.returncode}")
        receipt["sourcesAfter"] = source_digests()
        if receipt["sourcesBefore"] != receipt["sourcesAfter"]:
            raise ValueError("Sources changed during benchmark execution")
        receipt["status"] = "passed"
    except (Exception, KeyboardInterrupt) as error:
        receipt["error"] = str(error) or type(error).__name__
        print(receipt["error"], file=sys.stderr)
    finally:
        if creation_attempted and owned_id is None:
            try:
                devices = commands.json(["xcrun", "simctl", "list", "devices", "-j"], "recover-created-device")["devices"]
                matches = [device["udid"] for group in devices.values() for device in group
                           if device.get("name") == owned_name and device["udid"] not in existing_devices]
                if len(matches) == 1:
                    owned_id = matches[0]
                elif matches:
                    raise ValueError("Could not uniquely recover owned Simulator")
            except Exception as error:
                receipt["cleanupRecoveryError"] = str(error)
        receipt["cleanup"] = support.cleanup_owned_device(owned_id, commands.run)
        if receipt.get("cleanupRecoveryError") or not receipt["cleanup"]["passed"]:
            receipt["status"] = "failed"
        receipt["commands"] = commands.records
        receipt["finishedUTC"] = datetime.now(timezone.utc).isoformat()
        (directory / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        (directory / "receipt.txt").write_text(
            f"UIKit {args.suite} benchmark: {receipt['status']}\nConfiguration: Release; coverage: NO; parallel testing: NO\n"
            f"Iterations: {args.iterations}; trials: {args.trials}; capacity: 16\n"
            f"Candidate: {receipt.get('candidate', {}).get('head', 'unavailable')}; "
            f"dirty: {receipt.get('candidate', {}).get('dirty', 'unknown')}\n"
            f"Compiler: {receipt.get('swift-version', 'unavailable')}\n"
            f"Xcode: {receipt.get('xcode-version', 'unavailable')}\n"
            f"SDK: {receipt.get('sdkVersion', 'unavailable')} ({receipt.get('sdkPath', 'unavailable')})\n"
            f"Host OS: {receipt.get('host-os', 'unavailable')}\n"
            f"Host hardware: {receipt.get('host-hardware', 'unavailable')}\n"
            f"Destination: {json.dumps(receipt.get('actualDestination', receipt.get('requestedDestination')))}\n"
            f"Details and command logs: {directory / 'receipt.json'}\n"
            + (f"Error: {receipt['error']}\n" if "error" in receipt else ""))
    print(f"UIKit benchmark {receipt['status']}; receipt: {directory / 'receipt.json'}", flush=True)
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
