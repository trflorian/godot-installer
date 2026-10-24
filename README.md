# Godot installer

Installs Godot on Linux with interactive version and location selection,
checksum verification, and an application launcher.

Requires Bash, `curl`, `jq`, `unzip`, and GNU coreutils.

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/trflorian/godot-installer/main/install.sh)"
```

```text
Godot installer
Installed: 4.7.2.stable.official

Choose a release
  (↑/↓ or j/k · Enter · q cancel)
  › 4.7.2-stable · recommended
    4.8-beta1 · unstable
    4.8-dev7 · unstable

Install location
  (↑/↓ or j/k · Enter · q cancel)
  › Only me · ~/.local/bin
    All users · /usr/local/bin (sudo)
    Custom directory · only me
```
