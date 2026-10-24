# Godot installer

A Linux installer for the Godot editor with interactive release and installation
options. Downloads official builds, verifies checksums, and installs the executable,
icon, and application launcher. Supports stable and preview releases, excluding .NET.

Requires Bash, `curl`, `jq`, `unzip`, and GNU coreutils.

```sh
./install.sh                          # interactive setup
./install.sh --list                   # available releases and installed version
./install.sh --check                  # installed and latest stable versions
./install.sh --local --yes            # install in ~/.local/bin
./install.sh --global --yes           # install in /usr/local/bin using sudo
./install.sh --dir "$HOME/tools/bin" --yes
./install.sh --version 4.7.2 --yes     # install a specific release
./install.sh --help
```

The default is the latest stable release. Use arrow keys and Enter to select
options, or q to cancel. Set `NO_COLOR=1` to disable colors.

Local launchers and icons go under `~/.local/share` (or `$XDG_DATA_HOME`);
global ones go under `/usr/local/share`. `--dir` sets the executable directory.
