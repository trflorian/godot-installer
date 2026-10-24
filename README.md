# Godot installer

A small Linux installer for the official standard Godot editor (GDScript, not .NET).
One Python script, no third-party Python dependencies. Requires Python 3.10+ and
GNU `install`; global installs also need `sudo` or root.

## Install

```sh
uv sync
uv run install.py
```

Or run `python3 install.py` directly. Interactive setup offers local/global scope,
a custom executable directory, and confirmation before replacing files.

```sh
uv run install.py --list                          # recent stable + unstable releases
uv run install.py --check                         # installed + latest stable version
uv run install.py --local --yes                   # ~/.local/bin/godot
uv run install.py --global --yes                  # /usr/local/bin/godot; prompts for sudo
uv run install.py --dir ~/tools/bin --yes         # custom executable directory
uv run install.py --version 4.7.2 --local --yes    # a specific stable release
uv run install.py --version 4.8-beta1 --local --yes # an explicit preview release
```

`--list` shows recent releases for your Linux architecture, labels the latest
stable and unstable builds, and detects the installed `godot` version. Preview
builds require an explicit `--version`; the default is always latest stable.
.NET builds are never selected.

The launcher and official icon go in `$XDG_DATA_HOME` (default `~/.local/share`)
for local installs, or `/usr/local/share` for global installs. `--dir` changes
only the executable directory; combine it with `--global` for a global launcher.
The script prints the paths before installing. Add the executable directory to
`PATH` if needed; shell configuration is never edited.

Re-run to update. This replaces `godot`, `godot.desktop`, and `godot.svg` in the
selected locations. Existing projects and editor settings are preserved.
Downloads are verified against the release's SHA-256 digest or SHA-512 manifest
before installation. Downloads require access to GitHub's API and release hosts.

## Sources

- [Official Godot builds](https://github.com/godotengine/godot-builds/releases)
- [uv installer options](https://docs.astral.sh/uv/reference/installer/) inspired
  the simple per-user default and custom install directory.
