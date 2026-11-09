"""Observe public cache preconditions in isolated debug child processes."""
import json
from pathlib import Path
import resource
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "Fixtures/Preconditions"


def disable_core_dumps():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def main():
    (ROOT / ".build").mkdir(exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix="precondition-fixtures-", dir=ROOT / ".build"))
    package = directory / "Package"
    shutil.copytree(FIXTURE / "Sources", package / "Sources")
    manifest = (FIXTURE / "Package.swift.template").read_text().replace("__ROOT__", json.dumps(str(ROOT)))
    (package / "Package.swift").write_text(manifest)
    build_command = ["swift", "build", "--configuration", "debug", "--product", "PreconditionProbe"]
    build = subprocess.run(build_command, cwd=package, capture_output=True, text=True, timeout=600)
    (directory / "build.log").write_text(build.stdout + build.stderr)
    receipt = {"configuration": "debug", "build_command": build_command, "build_exit_code": build.returncode,
               "results": [], "passed": False}
    try:
        if build.returncode != 0:
            raise RuntimeError("Fixture build failed; see build.log")
        binary_directory = subprocess.check_output(
            ["swift", "build", "--configuration", "debug", "--show-bin-path"],
            cwd=package, text=True, timeout=120).strip()
        binary = str(Path(binary_directory) / "PreconditionProbe")
        cases = {name: None for name in ["valid-dimensions", "depth-64", "leaf-depth-64", "distinct-cache-nesting"]}
        cases.update({"negative-capacity": "SizeCache capacity must be nonnegative.",
                      "depth-65": "SizeCache dependency depth exceeds maximumDepth.",
                      "leaf-depth-65": "SizeCache dependency depth exceeds maximumDepth."})
        cases.update({name: "SizeCache cannot be reentered while its measurement recipe is running."
                      for name in ["reentry", "warm-hit-reentry", "count-reentry", "remove-reentry", "remove-all-reentry", "bound-reentry"]})
        cases.update({"result-valid": None, "result-distinct-cache-nesting": None,
                      "result-negative-capacity": "MainActorResultCache capacity must be nonnegative.",
                      "result-core-negative-capacity": "Cache capacity must be nonnegative."})
        cases.update({f"result-{phase}-{operation}":
                      "MainActorResultCache cannot be reentered while an operation is in progress."
                      for phase in ("capture", "compute", "removal")
                      for operation in ("lookup", "count", "remove", "clear")})
        cases.update({f"layout-reentry-{operation}": "LayoutCache cannot be reentered while a calculation is in progress."
                      for operation in ("lookup", "count", "remove", "clear")})
        cases.update({"declared-child": None, "undeclared-child-opt-out": None,
                      "undeclared-child": "SizeCache measured through a child that its parent did not declare in children:."})
        cases["undeclared-binding-path"] = cases["undeclared-child"]
        for operation in ("size", "remove", "bound"):
            for axis in ("width", "height"):
                cases[f"{operation}-{axis}-infinity"] = None
                for invalid in ("nan", "negativeInfinity", "negative"):
                    cases[f"{operation}-{axis}-{invalid}"] = f"SizeCache proposal {axis} must be nonnegative and not NaN."
        for name, expected in cases.items():
            command = [binary, name]
            record = {"case": name, "command": command, "expected_diagnostic": expected, "passed": False}
            receipt["results"].append(record)
            try:
                result = subprocess.run(command, cwd=package, capture_output=True, text=True, timeout=30,
                                        preexec_fn=disable_core_dumps)
                diagnostics = result.stdout + result.stderr
                (directory / (name + ".log")).write_text(diagnostics)
                record["exit_code"] = result.returncode
                record["passed"] = ((result.returncode == 0 and "Completed " + name in result.stdout)
                                    if expected is None else result.returncode < 0 and expected in diagnostics)
            except subprocess.TimeoutExpired as error:
                record["timed_out"] = True
                for stream in ("stdout", "stderr"):
                    content = getattr(error, stream) or b""
                    (directory / (name + "." + stream + ".log")).write_bytes(
                        content.encode() if isinstance(content, str) else content)
            print(("PASS " if record["passed"] else "FAIL ") + name, flush=True)
        receipt["passed"] = bool(receipt["results"]) and all(item["passed"] for item in receipt["results"])
    finally:
        (directory / "results.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print("Precondition observations: " + str(directory))
    if not receipt["passed"]:
        raise SystemExit("A precondition fixture failed its expected outcome")


if __name__ == "__main__":
    main()
