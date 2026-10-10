#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import subprocess
from pathlib import Path


def safe_name(value: str) -> str:
    return re.sub(r"[^0-9A-Za-z._-]+", "-", value).strip("-")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--target")
    args = parser.parse_args()
    manifest = args.manifest.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    target = args.target or os.environ.get("CARGO_BUILD_TARGET")
    if not target:
        rustc = subprocess.run(
            ["rustc", "-vV"], check=True, stdout=subprocess.PIPE, text=True, encoding="utf-8"
        ).stdout
        target = next(line.split(":", 1)[1].strip() for line in rustc.splitlines() if line.startswith("host:"))
    command = [
        "cargo", "metadata", "--locked", "--offline", "--filter-platform", target,
        "--format-version", "1", "--manifest-path", str(manifest),
    ]
    result = subprocess.run(
        command,
        cwd=manifest.parent,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    metadata = json.loads(result.stdout)
    packages = sorted(
        (package for package in metadata["packages"] if package.get("source")),
        key=lambda package: (package["name"].lower(), package["version"]),
    )

    rows = []
    for package in packages:
        package_name = f'{package["name"]}-{package["version"]}'
        package_dir = Path(package["manifest_path"]).parent
        destination = output / safe_name(package_name)
        copied = []
        candidates = []
        license_file = package.get("license_file")
        if license_file:
            candidate = Path(license_file)
            candidates.append(candidate if candidate.is_absolute() else package_dir / candidate)
        if package_dir.is_dir():
            for candidate in package_dir.iterdir():
                upper = candidate.name.upper()
                if candidate.is_file() and upper.startswith(("LICENSE", "COPYING", "NOTICE", "UNLICENSE")):
                    candidates.append(candidate)
                elif candidate.is_dir() and upper == "LICENSES":
                    destination.mkdir(parents=True, exist_ok=True)
                    shutil.copytree(candidate, destination / candidate.name, dirs_exist_ok=True)
                    copied.append(candidate.name + "/")
        seen = set()
        for candidate in candidates:
            if not candidate.is_file():
                continue
            resolved = candidate.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            destination.mkdir(parents=True, exist_ok=True)
            shutil.copy2(resolved, destination / candidate.name)
            copied.append(candidate.name)

        declared = package.get("license") or "not declared"
        repository = package.get("repository") or ""
        repository = repository.replace("|", "\\|")
        files = ", ".join(sorted(copied)) if copied else "—"
        rows.append(
            f'| {package["name"]} | {package["version"]} | {declared} | {files} | {repository} |'
        )

    report = [
        "# Rust dependency licenses",
        "",
        "Generated from Cargo metadata for the locked dependency graph. License expressions are declarations from each package; copied files remain authoritative.",
        "",
        "| Package | Version | Declared license | Copied files | Repository |",
        "| --- | --- | --- | --- | --- |",
        *rows,
        "",
    ]
    (output / "RUST-DEPENDENCIES.md").write_text("\n".join(report), encoding="utf-8")
    print(f"Recorded {len(packages)} Rust packages in {output}")


if __name__ == "__main__":
    main()
