# Godot installer

One Bash script for Linux. Requires `curl`, `jq`, `unzip`, and GNU coreutils.
Global installs use `sudo` when needed.

Interactive setup uses arrow keys (or j/k) and Enter to choose a release and
install location. Press q or Escape to cancel. It shows a summary before
confirmation, colored status messages, and download progress. Set `NO_COLOR=1`
to disable colors; redirected output stays plain. Use CLI flags with `--yes`
for noninteractive or `TERM=dumb` sessions.

```sh
./install.sh                            # interactive setup
./install.sh --list                     # installed version + stable/unstable releases
./install.sh --check                    # installed + latest stable version
./install.sh --local --yes              # ~/.local/bin/godot
./install.sh --global --yes             # /usr/local/bin/godot
./install.sh --dir "$HOME/tools/bin" --yes
./install.sh --version 4.8-beta1 --yes   # explicit preview release
```

Defaults to the latest stable standard editor; no .NET builds. `--list` shows
recent releases for your architecture. Bare versions such as `4.7.2` select the
stable release. Re-run to update or replace the selected installation.

Installs the official icon and application launcher under `${XDG_DATA_HOME:-~/.local/share}`
locally, or `/usr/local/share` globally. `--dir` changes only the executable
directory; combine with `--global` for a global launcher. Downloads are checked
against the official release checksum before installation. Add your executable
directory to `PATH` if necessary.

Builds come from [official Godot releases](https://github.com/godotengine/godot-builds/releases).
Selection menus take inspiration from [Gum](https://github.com/charmbracelet/gum),
without requiring it. The local default and directory override follow the approach of
[uv's installer](https://docs.astral.sh/uv/reference/installer/).
