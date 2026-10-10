#!/usr/bin/env python3
"""Fetch the pinned official Element Call embedded bundle for the native UI."""
import argparse
import hashlib
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path, PurePosixPath

VERSION = "0.26.0"
URL = ("https://registry.npmjs.org/@element-hq/element-call-embedded/-/"
       f"element-call-embedded-{VERSION}.tgz")
SHA512 = "e9262723c164d1ec4792796627cd19c381010b7aa549103679d20e0f7136edd2aac82ad270e70327255f5b9d0b52d183aa485aacadba27549d501c68e14a9abf"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if (output / "dist" / "index.html").is_file():
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="element-call-", dir=output.parent) as temporary:
        temporary = Path(temporary)
        archive = temporary / "bundle.tgz"
        with urllib.request.urlopen(URL, timeout=90) as response, archive.open("wb") as target:
            shutil.copyfileobj(response, target)
        digest = hashlib.sha512(archive.read_bytes()).hexdigest()
        if digest != SHA512:
            raise SystemExit(f"Element Call {VERSION} checksum mismatch")
        staged = temporary / "element-call"
        (staged / "dist").mkdir(parents=True)
        with tarfile.open(archive, "r:gz") as bundle:
            for member in bundle.getmembers():
                path = PurePosixPath(member.name)
                if len(path.parts) < 3 or path.parts[:2] != ("package", "dist"):
                    continue
                relative = PurePosixPath(*path.parts[2:])
                if not relative.parts or ".." in relative.parts or member.issym() or member.islnk():
                    continue
                destination = staged / "dist" / Path(*relative.parts)
                if member.isdir():
                    destination.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    source = bundle.extractfile(member)
                    if source is not None:
                        with source, destination.open("wb") as target:
                            shutil.copyfileobj(source, target)
        if not (staged / "dist" / "index.html").is_file():
            raise SystemExit("The Element Call package does not contain dist/index.html")
        if output.exists():
            shutil.rmtree(output)
        staged.rename(output)
    print(f"Element Call embedded {VERSION} installed in {output}")


if __name__ == "__main__":
    main()
