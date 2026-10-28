"""Compile public-import controls and rejected uses with Swift 6 concurrency checks."""
import argparse
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Fixtures/Concurrency"


def output(command):
    return subprocess.check_output(command, cwd=ROOT, text=True, timeout=120).strip()


def check_warning_policy(directory):
    manifest = json.loads(output(["swift", "package", "dump-package"]))
    for target in manifest["targets"]:
        if target["type"] not in ("regular", "executable", "test", "macro"):
            continue
        settings = target.get("settings", [])
        if not any(setting.get("tool") == "swift" and not setting.get("condition")
                   and setting.get("kind", {}).get("treatAllWarnings", {}).get("_0") == "error"
                   for setting in settings):
            raise SystemExit("Missing unconditional warning policy: " + target["name"])
    fixture = directory / "warning-policy"
    shutil.copytree(ROOT / "Fixtures/Warnings", fixture)
    files = ["Sources/WarningLibrary/Value.swift", "Sources/WarningExecutable/main.swift",
             "Tests/WarningTests/ValueTests.swift"]
    results = []
    for configuration in ("debug", "release"):
        command = ["swift", "build", "--build-tests", "--configuration", configuration]
        for selected in [None, *files]:
            path = fixture / selected if selected else None
            original = path.read_text() if path else None
            if path:
                path.write_text(original + '\n#warning("warning-policy-probe")\n')
            try:
                result = subprocess.run(command, cwd=fixture, text=True, capture_output=True, timeout=600)
            finally:
                if path:
                    path.write_text(original)
            diagnostics = result.stdout + result.stderr
            passed = (result.returncode == 0 if path is None else
                      result.returncode == 1 and any("error:" in line and "warning-policy-probe" in line
                                                    for line in diagnostics.splitlines()))
            label = configuration + "-" + (Path(selected).parent.name if selected else "valid")
            (directory / (label + ".log")).write_text(diagnostics)
            results.append({"configuration": configuration, "warning_file": selected,
                            "command": command, "exit_code": result.returncode, "passed": passed})
            print(("PASS " if passed else "FAIL ") + label, flush=True)
            if not passed:
                print(diagnostics)
    (directory / "warning-policy.json").write_text(json.dumps(results, indent=2) + "\n")
    if not all(result["passed"] for result in results):
        raise SystemExit("Warning policy fixture failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--warnings-policy", action="store_true", help="Also compile debug/release warning-policy probes")
    args = parser.parse_args()
    subprocess.run(["swift", "build", "--target", "DerivedKeys"], cwd=ROOT, check=True, timeout=600)
    binaries = Path(output(["swift", "build", "--show-bin-path"]))
    modules = binaries / "Modules" if (binaries / "Modules").is_dir() else binaries
    if not (modules / "DerivedKeys.swiftmodule").exists():
        raise SystemExit("Built DerivedKeys module is missing from " + str(modules))
    compiler = output(["xcrun", "--find", "swiftc"])
    sdk = output(["xcrun", "--sdk", "macosx", "--show-sdk-path"])
    architecture = platform.machine()
    if architecture not in ("arm64", "x86_64"):
        raise SystemExit("Unsupported macOS host architecture: " + architecture)
    target = architecture + "-apple-macosx13.0"
    settings = ["-c", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-target", target, "-sdk", sdk, "-I", str(modules)]
    directory = Path(tempfile.mkdtemp(prefix="compiler-fixtures-", dir=ROOT / ".build"))
    shared = (FIXTURES / "Shared.swift").read_text()
    results = []
    for fixture in sorted(FIXTURES.glob("*.swift")):
        if fixture.name == "Shared.swift":
            continue
        source = fixture.read_text()
        expected = [line.removeprefix("// expected-error: ") for line in source.splitlines()
                    if line.startswith("// expected-error: ")]
        combined = directory / fixture.name
        combined.write_text(shared + "\n" + source)
        command = [compiler, *settings, str(combined), "-o", str(directory / (fixture.stem + ".o"))]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
        diagnostics = result.stdout + result.stderr
        (directory / (fixture.stem + ".log")).write_text(diagnostics)
        passed = (result.returncode == 0 if not expected else
                  result.returncode == 1 and all(message in diagnostics for message in expected))
        results.append({"fixture": str(fixture.relative_to(ROOT)), "command": command,
                        "expected_errors": expected, "exit_code": result.returncode, "passed": passed})
        print(("PASS " if passed else "FAIL ") + fixture.name, flush=True)
        if not passed:
            print(diagnostics)
    receipt = {"compiler": output([compiler, "--version"]), "settings": settings, "results": results}
    (directory / "results.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Compiler observations: " + str(directory))
    if args.warnings_policy:
        check_warning_policy(directory)
    if not results or not all(result["passed"] for result in results):
        raise SystemExit("A compiler fixture failed its expected outcome")
    print(f"Passed {len(results)} public-import compiler fixtures")


if __name__ == "__main__":
    main()
