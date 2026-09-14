"""Publish a commit-pinned incremental channel and a tiny Windows launcher ZIP.

Developer/CI tool only; players need only the built-in Windows PowerShell.
The release workflow uploads channel.json LAST, after verification and assets.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "blakelassman/brassline"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def included(path):
    return (path in {"project.godot", "main.tscn", "server.cfg", "GODOT_LICENSES.txt", "HOSTING.txt",
                     "launcher/Core.ps1", "launcher/Launcher.ps1"}
            or path.startswith(("scripts/", "assets/"))) and not path.endswith((".py", ".import"))


def build(destination, commit):
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("Use the full Git commit SHA")
    # Read committed blobs, never a partly edited working directory.
    names = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", commit], cwd=ROOT, text=True).splitlines()
    def blob(path):
        return subprocess.check_output(["git", "show", f"{commit}:{path}"], cwd=ROOT)
    files = []
    for name in sorted(filter(included, names)):
        parts = PurePosixPath(name).parts
        if any(p in (".", "..") for p in parts) or not re.fullmatch(r"[a-zA-Z0-9_./-]+", name):
            raise ValueError(f"Unsafe path: {name}")
        data = blob(name)
        files.append(dict(path=name, size=len(data), sha256=sha256(data),
                          url=f"https://raw.githubusercontent.com/{REPOSITORY}/{commit}/{name}"))
    readme = blob("README.md").decode()
    version = re.search(r"^# BRASSLINE ([0-9.]+)", readme).group(1)
    channel = dict(schema=1, commit=commit, version=f"{version}+{commit[:7]}",
                   engine=json.loads(blob("launcher/engine.json")), files=files)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "channel.json").write_text(json.dumps(channel, indent=2) + "\n", encoding="utf-8")
    launcher_files = ["BRASSLINE_LAUNCHER.bat", "launcher/Bootstrap.ps1", "launcher/Core.ps1",
                      "launcher/Launcher.ps1", "launcher/READ_ME_FIRST.txt", "GODOT_LICENSES.txt"]
    archive = destination / "Brassline_Launcher_Windows.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        for name in launcher_files:
            info = zipfile.ZipInfo(f"Brassline_Launcher/{name}", (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, blob(name))
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for name in launcher_files:
            assert z.read(f"Brassline_Launcher/{name}") == blob(name)
    (destination / "SHA256SUMS.txt").write_text(
        f"{sha256(archive.read_bytes())}  {archive.name}\n", encoding="ascii")
    print(f"Packaged {len(files)} runtime files; launcher ZIP {archive.stat().st_size:,} bytes")
    return channel


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    parser.add_argument("--commit", default="HEAD")
    args = parser.parse_args()
    commit = subprocess.check_output(["git", "rev-parse", args.commit], cwd=ROOT, text=True).strip()
    build(args.destination, commit)
