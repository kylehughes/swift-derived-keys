"""Build static DocC using the installed Swift/DocC tools; no package plugins."""
import argparse
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

MODULES = ['DerivedKeys', 'DerivedKeysUI', 'DerivedKeysUIKit']
BASE_PATH = 'swift-derived-keys'


def extract_graphs(arguments):
    # SwiftPM extracts symbol graphs with the package's real graph and settings.
    extraction = subprocess.check_output(["swift", "package"] + arguments + ["dump-symbol-graph"],
                                         text=True, timeout=600)
    print(extraction, end="")
    locations = [line.removeprefix("Files written to ") for line in extraction.splitlines() if line.startswith("Files written to ")]
    if len(locations) != 1:
        raise ValueError("SwiftPM did not identify one symbol graph output directory")
    return Path(locations[0])


def validate_site(output: Path):
    pages = [(module, module, "module") for module in MODULES]
    pages += [("DerivedKeysUI", "DerivedKeysUI/SizeCache/" + title, "init") for title in [
        "init(dependingOn:capacity:)", "init(dependingOn:children:capacity:measure:)"]]
    for module, symbol, kind in pages:
        relative = "documentation/" + symbol.lower()
        data = output / "data" / (relative + ".json")
        html = output / relative / "index.html"
        try:
            page = json.loads(data.read_text())
            metadata = page["metadata"]
            if (page["kind"] != "symbol" or metadata["title"] != symbol.split("/")[-1]
                    or metadata["symbolKind"] != kind
                    or {"name": module} not in metadata["modules"]
                    or page["identifier"]["url"] != "doc://" + module + "/documentation/" + symbol
                    or page["identifier"]["interfaceLanguage"] != "swift"):
                raise ValueError("Unexpected symbol metadata")
            if symbol == "DerivedKeysUI/SizeCache/init(dependingOn:capacity:)":
                constraints = metadata["conformance"]["constraints"]
                expected = [{"type": "codeVoice", "code": "Root"},
                            {"type": "text", "text": " inherits "},
                            {"type": "codeVoice", "code": "UIView"},
                            {"type": "text", "text": "."}]
                if not isinstance(constraints, list) or not any(
                        constraints[index:index + len(expected)] == expected for index in range(len(constraints))):
                    raise ValueError("Missing rendered Root inherits UIView condition")
            if "<html" not in html.read_text().lower():
                raise ValueError("Missing static HTML document")
        except (OSError, ValueError, KeyError, TypeError) as error:
            raise ValueError("Invalid documentation page for " + symbol + ": " + str(error)) from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Documentation output already exists; choose a fresh output")
    architecture = platform.machine()
    if architecture not in ("arm64", "x86_64"):
        raise ValueError("Unsupported iOS Simulator host architecture: " + architecture)
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"],
                                  text=True, timeout=60).strip()
    if not sdk or not Path(sdk).is_dir():
        raise ValueError("xcrun did not identify an iOS Simulator SDK directory")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix="docc-", dir=args.output.parent))
    try:
        subprocess.run(["swift", "build"], check=True, timeout=600)
        graphs = {"macos": extract_graphs([]),
                  "ios": extract_graphs(["--triple", architecture + "-apple-ios16.0-simulator", "--sdk", sdk,
                                         "--scratch-path", str(scratch / "ios-build")])}
        archives = []
        for module in MODULES:
            selected = scratch / module
            for target, directory in graphs.items():
                platform_graphs = selected / target
                platform_graphs.mkdir(parents=True)
                matches = list(directory.glob(module + ".symbols.json")) + list(directory.glob(module + "@*.symbols.json"))
                if not matches:
                    raise ValueError("No public " + target + " symbol graph for " + module)
                for path in matches:
                    shutil.copyfile(path, platform_graphs / path.name)
            catalog = Path("Documentation/" + module + ".docc")
            if not catalog.is_dir():
                raise ValueError("Expected documentation catalog: " + str(catalog))
            archive = scratch / (module + ".doccarchive")
            subprocess.run(["xcrun", "docc", "convert", str(catalog), "--additional-symbol-graph-dir", str(selected),
                            "--output-path", str(archive), "--hosting-base-path", BASE_PATH,
                            "--transform-for-static-hosting", "--warnings-as-errors"], check=True, timeout=600)
            archives.append(archive)
        site = scratch / "site"
        if len(archives) == 1:
            shutil.copytree(archives[0], site)
        else:
            subprocess.run(["xcrun", "docc", "merge"] + [str(path) for path in archives]
                           + ["--output-path", str(site)], check=True, timeout=600)
        validate_site(site)
        destination = "/" + BASE_PATH.strip("/") + "/documentation/" + (MODULES[0].lower() + "/" if len(MODULES) == 1 else "")
        (site / "index.html").write_text('<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=' + destination + '"><a href="' + destination + '">Documentation</a>\n')
        (site / ".nojekyll").touch()
        args.output.mkdir()
        try:
            shutil.copytree(site, args.output, dirs_exist_ok=True)
        except BaseException:
            shutil.rmtree(args.output)
            raise
        print(json.dumps({"base_path": BASE_PATH, "modules": MODULES, "output": str(args.output)}))
    finally:
        shutil.rmtree(scratch)


if __name__ == "__main__":
    main()
