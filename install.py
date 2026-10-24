#!/usr/bin/env python3
"""Install the official Godot editor for Linux; Python standard library only."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zipfile import BadZipFile, ZipFile

RELEASES = "https://api.github.com/repos/godotengine/godot-builds/releases"


def download(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "godot-installer"})
    with urlopen(request, timeout=120) as response:
        return response.read()


def directory(value: str) -> Path:
    path = Path(value).expanduser().absolute()
    if any(char in str(path) for char in "\n\r\t"):
        raise ValueError("Installation paths must not contain tabs or newlines.")
    return path


def exec_quote(path: Path) -> str:
    # Desktop Exec has its own quoting rules, independent of shell quoting.
    value = str(path).replace("%", "%%")
    for char in ("\\", '"', "`", "$"):
        value = value.replace(char, "\\" + char)
    return '"' + value.replace("\\", "\\\\") + '"'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument("--local", action="store_true", help="install for this user (default)")
    scope.add_argument("--global", dest="system", action="store_true", help="install for all users")
    parser.add_argument("--dir", help="executable directory (default: ~/.local/bin or /usr/local/bin)")
    parser.add_argument("--version", help="release to install, e.g. 4.7.2 or 4.8-dev5 (default: latest stable)")
    parser.add_argument("--list", action="store_true", help="list recent stable and unstable releases; no installation")
    parser.add_argument("--check", action="store_true", help="show available version without installing")
    parser.add_argument("-y", "--yes", action="store_true", help="use defaults and skip prompts")
    args = parser.parse_args()
    if platform.system() != "Linux":
        parser.error("This installer supports Linux only.")
    architectures = {"x86_64": "x86_64", "amd64": "x86_64", "aarch64": "arm64", "arm64": "arm64", "armv7l": "arm32", "i686": "x86_32"}
    arch = architectures.get(platform.machine().lower())
    if not arch:
        parser.error(f"Unsupported architecture: {platform.machine()}")
    target_dir = args.dir or ("/usr/local/bin" if args.system else "~/.local/bin")
    candidates = [directory(target_dir) / "godot"]
    if not (args.dir or args.local or args.system):
        candidates = [Path(found)] + candidates if (found := shutil.which("godot")) else candidates
    installed = next((path for path in candidates if path.is_file()), None)
    if installed:
        result = subprocess.run([str(installed), "--version"], capture_output=True, text=True, timeout=15, check=True)
        print(f"Installed: {result.stdout.strip()} ({installed})")
    else:
        print("Installed: not found")
    if args.list:
        releases = json.loads(download(f"{RELEASES}?per_page=30"))
        latest = json.loads(download(f"{RELEASES}/latest"))["tag_name"]
        for item in releases:
            if any(asset["name"] == f"Godot_v{item['tag_name']}_linux.{arch}.zip" for asset in item["assets"]):
                label = "latest stable" if item["tag_name"] == latest else "unstable" if item["prerelease"] else "stable"
                print(f"{item['tag_name']:<24} {label}")
        return
    tag = args.version
    if tag and re.fullmatch(r"\d+\.\d+(?:\.\d+)?", tag):
        tag += "-stable"
    if tag and not re.fullmatch(r"\d+\.\d+(?:\.\d+)?-(?:stable|dev\d+|beta\d+|rc\d+)", tag):
        parser.error("Use a release such as 4.7.2, 4.7.2-stable, or 4.8-dev5.")
    release = json.loads(download(f"{RELEASES}/tags/{tag}" if tag else f"{RELEASES}/latest"))
    tag = release["tag_name"]
    name = f"Godot_v{tag}_linux.{arch}"
    assets = {asset["name"]: asset for asset in release["assets"]}
    asset = assets.get(name + ".zip")
    if asset is None:
        raise ValueError(f"Release {tag} has no Linux build for {arch}.")
    print(f"Godot {tag} · Linux {arch}")
    print(release["html_url"])
    if args.check:
        return

    interactive = sys.stdin.isatty() and not args.yes
    if interactive and not (args.local or args.system or args.dir):
        choice = input("Install for [1] this user or [2] all users? [1]: ").strip()
        if choice not in ("", "1", "2"):
            parser.error("Choose 1 or 2.")
        args.system = choice == "2"
    default = "/usr/local/bin" if args.system else "~/.local/bin"
    target = args.dir or default
    if interactive and not args.dir:
        target = input(f"Executable directory [{default}]: ").strip() or default
    binary = directory(target) / "godot"
    data = directory("/usr/local/share" if args.system else os.environ.get("XDG_DATA_HOME") or "~/.local/share")
    icon = data / "icons/hicolor/scalable/apps/godot.svg"
    launcher = data / "applications/godot.desktop"
    print(f"Executable: {binary}\nLauncher:   {launcher}\nIcon:       {icon}")
    if not args.yes:
        if not interactive:
            parser.error("Use --yes for noninteractive installation.")
        if input("Install / replace these files? [y/N]: ").strip().lower() not in ("y", "yes"):
            return
    prefix = ["sudo"] if args.system and os.geteuid() != 0 else []
    if prefix and not shutil.which("sudo"):
        raise ValueError("Global installation requires sudo or running as root.")

    with TemporaryDirectory(prefix="godot-install-") as temp:
        stage = Path(temp)
        print("Downloading editor…", flush=True)
        archive = download(asset["browser_download_url"])
        digest = asset.get("digest") or ""
        if digest.startswith("sha256:"):
            actual = "sha256:" + hashlib.sha256(archive).hexdigest()
            if actual != digest:
                raise ValueError("Download checksum mismatch; nothing installed.")
        else:
            sums = assets.get("SHA512-SUMS.txt")
            if sums is None:
                raise ValueError("Release has no supported checksum; nothing installed.")
            lines = download(sums["browser_download_url"]).decode().splitlines()
            expected = next((line.split()[0] for line in lines if len(line.split()) == 2 and line.split()[1].lstrip("*") == name + ".zip"), None)
            if hashlib.sha512(archive).hexdigest() != expected:
                raise ValueError("Download checksum mismatch; nothing installed.")
        print("Checksum verified.")
        zip_path = stage / "godot.zip"
        zip_path.write_bytes(archive)
        with ZipFile(zip_path) as zipped:
            # Read only the expected binary; never extract arbitrary archive paths.
            (stage / "godot").write_bytes(zipped.read(name))
        base = f"https://raw.githubusercontent.com/godotengine/godot/{tag}"
        try:
            svg = download(f"{base}/misc/logo/icon.svg")
        except HTTPError as error:
            if error.code != 404:
                raise
            svg = download(f"{base}/icon.svg")
        (stage / "godot.svg").write_bytes(svg)
        (stage / "godot.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=Godot\n"
            "Comment=Create and edit games with Godot Engine\n"
            f"Exec={exec_quote(binary)} --project-manager\n"
            f"Icon={icon}\nTerminal=false\nCategories=Development;IDE;\n"
            "StartupWMClass=Godot\n"
        )
        for source, destination, mode in (("godot", binary, "755"), ("godot.svg", icon, "644"), ("godot.desktop", launcher, "644")):
            subprocess.run(prefix + ["install", "-D", "-m", mode, "--", str(stage / source), str(destination)], check=True)
    if shutil.which("update-desktop-database"):
        subprocess.run(prefix + ["update-desktop-database", str(launcher.parent)], check=True)
    print("Installed. Open Godot from your application menu.")
    if str(binary.parent) not in os.environ.get("PATH", "").split(os.pathsep):
        print(f"To use 'godot' in a terminal, add {binary.parent} to PATH.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, URLError, ValueError, KeyError, BadZipFile, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        sys.exit(f"Error: {error}")
    except (KeyboardInterrupt, EOFError):
        sys.exit("Cancelled.")
