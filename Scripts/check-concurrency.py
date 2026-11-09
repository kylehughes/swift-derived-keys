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


def compile_fixture(compiler, settings, fixture, directory, shared=""):
    source = fixture.read_text()
    expected = [line.strip().removeprefix("// expected-error: ") for line in source.splitlines()
                if line.strip().startswith("// expected-error: ")]
    combined = directory / fixture.name
    combined.write_text(shared + "\n" + source)
    command = [compiler, *settings, str(combined), "-o", str(directory / (fixture.stem + ".o"))]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
    diagnostics = result.stdout + result.stderr
    (directory / (fixture.stem + ".log")).write_text(diagnostics)
    passed = (result.returncode == 0 if not expected else
              result.returncode == 1 and all(message in diagnostics for message in expected))
    print(("PASS " if passed else "FAIL ") + str(fixture.relative_to(ROOT)), flush=True)
    if not passed:
        print(diagnostics)
    return {"fixture": str(fixture.relative_to(ROOT)), "command": command,
            "expected_errors": expected, "exit_code": result.returncode, "passed": passed}


def check_ios(compiler, architecture, directory):
    directory = directory / "ios16"
    directory.mkdir()
    sdk = output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"])
    settings = ["-c", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-target", architecture + "-apple-ios16.0-simulator",
                "-sdk", sdk, "-I", str(directory)]
    modules = []
    for name in ("DerivedKeys", "DerivedKeysUI", "DerivedKeysUIExample"):
        sources = sorted((ROOT / "Sources" / name).glob("*.swift"))
        if not sources:
            raise SystemExit("No iOS sources found for " + name)
        objects = directory / name
        objects.mkdir()
        file_map = {str(source): {"object": str(objects / (source.stem + ".o"))} for source in sources}
        output_map = objects / "outputs.json"
        output_map.write_text(json.dumps(file_map, indent=2) + "\n")
        command = [compiler, *settings, "-emit-module", "-module-name", name,
                   "-emit-module-path", str(directory / (name + ".swiftmodule")),
                   "-output-file-map", str(output_map), *map(str, sources)]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
        diagnostics = result.stdout + result.stderr
        (directory / (name + ".log")).write_text(diagnostics)
        passed = (result.returncode == 0 and (directory / (name + ".swiftmodule")).is_file()
                  and all(Path(value["object"]).is_file() for value in file_map.values()))
        modules.append({"module": name, "command": command, "exit_code": result.returncode, "passed": passed})
        print(("PASS " if passed else "FAIL ") + name + " iOS 16 full compilation", flush=True)
        if not passed:
            print(diagnostics)
            break
    results = []
    if len(modules) == 3 and all(module["passed"] for module in modules):
        results = [compile_fixture(compiler, settings, fixture, directory)
                   for fixture in sorted((ROOT / "Fixtures/iOS").glob("*.swift"))]
    passed = (len(modules) == 3 and all(module["passed"] for module in modules)
              and bool(results) and all(result["passed"] for result in results))
    return {"settings": settings, "modules": modules, "results": results, "passed": passed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--warnings-policy", action="store_true", help="Also compile debug/release warning-policy probes")
    parser.add_argument("--scratch-path", help="Isolated SwiftPM build directory")
    args = parser.parse_args()
    build_settings = ["--scratch-path", args.scratch_path] if args.scratch_path else []
    subprocess.run(["swift", "build", *build_settings, "--target", "DerivedKeysUI"],
                   cwd=ROOT, check=True, timeout=600)
    binaries = Path(output(["swift", "build", *build_settings, "--show-bin-path"]))
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
    (ROOT / ".build").mkdir(exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix="compiler-fixtures-", dir=ROOT / ".build"))
    shared = (FIXTURES / "Shared.swift").read_text()
    results = [compile_fixture(compiler, settings, fixture, directory, shared)
               for fixture in sorted(FIXTURES.glob("*.swift")) if fixture.name != "Shared.swift"]
    ios = check_ios(compiler, architecture, directory)
    receipt = {"compiler": output([compiler, "--version"]), "settings": settings, "results": results, "ios16": ios}
    (directory / "results.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Compiler observations: " + str(directory))
    if args.warnings_policy:
        check_warning_policy(directory)
    if not results or not all(result["passed"] for result in results) or not ios["passed"]:
        raise SystemExit("A compiler fixture failed its expected outcome")
    print(f"Passed {len(results) + len(ios['results'])} public-import compiler fixtures and iOS 16 modules")


if __name__ == "__main__":
    main()
