#!/usr/bin/env bash
set -euo pipefail

bold= cyan= green= yellow= red= reset=
if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR+x} ]]; then
    bold=$'\e[1m'; cyan=$'\e[36m'; green=$'\e[32m'
    yellow=$'\e[33m'; red=$'\e[31m'; reset=$'\e[0m'
fi
fail() { printf '%sError:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }
step() { printf '\n%s›%s %s\n' "$cyan" "$reset" "$*"; }

# Small arrow-key menu: no extra dependency or persistent terminal-mode changes.
choose() {
    local title=$1 key tail i
    shift
    local options=("$@")
    selected=0
    printf '\n%s%s%s\n  %s\n' "$bold" "$title" "$reset" '(↑/↓ or j/k · Enter · q cancel)'
    while :; do
        for i in "${!options[@]}"; do
            printf '\r\033[2K'
            if ((i == selected)); then
                printf '%s  › %s%s\n' "$cyan$bold" "${options[i]}" "$reset"
            else
                printf '    %s\n' "${options[i]}"
            fi
        done
        IFS= read -rsn1 key || exit 1
        if [[ $key == $'\e' ]]; then
            tail=
            IFS= read -rsn2 -t 0.2 tail || true
            key+=$tail
        fi
        case $key in
            $'\e[A'|$'\eOA'|k) selected=$(((selected + ${#options[@]} - 1) % ${#options[@]})) ;;
            $'\e[B'|$'\eOB'|j) selected=$(((selected + 1) % ${#options[@]})) ;;
            '')
                printf '\033[%dA\033[J  %s✓ %s%s\n' "${#options[@]}" "$green" "${options[selected]}" "$reset"
                return ;;
            q|$'\e') printf '\nCancelled.\n'; exit 0 ;;
        esac
        printf '\033[%dA' "${#options[@]}"
    done
}
fetch() { curl --proto '=https' --proto-redir '=https' -fLsS --connect-timeout 15 --max-time 300 "$@"; }

scope= dir= version= mode=install yes=false
while (($#)); do
    case "$1" in
        --local|--global)
            [[ -z $scope || $scope == "$1" ]] || fail 'Choose --local or --global.'
            scope=$1 ;;
        --dir|--version)
            (($# >= 2)) && [[ -n $2 && $2 != --* ]] || fail "$1 needs a value."
            if [[ $1 == --dir ]]; then dir=$2; else version=$2; fi
            shift ;;
        --list) mode=list ;;
        --check) mode=check ;;
        -y|--yes) yes=true ;;
        -h|--help)
            cat <<'EOF'
Usage: ./install.sh [options]
  --list           Show installed version and recent stable/unstable releases
  --check          Show installed and latest stable versions without installing
  --local          Install for this user (default: ~/.local/bin)
  --global         Install for all users (/usr/local/bin; uses sudo)
  --dir PATH       Custom executable directory
  --version TAG    Specific stable or preview release (default: latest stable)
  -y, --yes        Skip prompts
  -h, --help       Show help
Requires Bash, curl, jq, unzip, and GNU coreutils. Standard editor only, no .NET.
EOF
            exit ;;
        *) fail "Unknown option: $1" ;;
    esac
    shift
done
interactive=false
if ! $yes && [[ -t 0 && -t 1 && ${TERM:-dumb} != dumb ]]; then interactive=true; fi
printf '\n%sGodot installer%s\n' "$bold$cyan" "$reset"
[[ $(uname -s) == Linux ]] || fail 'Linux only.'
for tool in curl jq unzip install realpath sha256sum sha512sum timeout; do
    command -v "$tool" >/dev/null || fail "Missing dependency: $tool"
done
case $(uname -m) in
    x86_64|amd64) arch=x86_64 ;; aarch64|arm64) arch=arm64 ;;
    armv7l) arch=arm32 ;; i386|i686) arch=x86_32 ;;
    *) fail 'Unsupported architecture.' ;;
esac

current=${dir:-$HOME/.local/bin}/godot
if [[ $scope == --global && -z $dir ]]; then current=/usr/local/bin/godot; fi
if [[ -z $scope && -z $dir ]]; then current=$(command -v godot || printf '%s' "$current"); fi
if [[ -x $current ]]; then
    installed=$(timeout 15 "$current" --version) || installed='unable to run'
    printf '%sInstalled:%s %s (%s)\n' "$green" "$reset" "$installed" "$current"
else
    printf '%sInstalled:%s not found\n' "$yellow" "$reset"
fi
api=https://api.github.com/repos/godotengine/godot-builds/releases
if [[ $mode == list ]]; then
    latest=$(fetch "$api/latest" | jq -er .tag_name)
    fetch "$api?per_page=30" | jq -r --arg arch "$arch" --arg latest "$latest" '
        .[] | . as $release | select(any(.assets[]; .name == ("Godot_v" + $release.tag_name + "_linux." + $arch + ".zip")))
        | [.tag_name, (if .tag_name == $latest then "latest stable" elif .prerelease then "unstable" else "stable" end)] | @tsv'
    exit
fi
if [[ -z $version && $mode == install ]] && $interactive; then
    step 'Fetching available releases…'
    latest=$(fetch "$api/latest" | jq -er .tag_name)
    releases=$(fetch "$api?per_page=15")
    mapfile -t tags < <(jq -r --arg latest "$latest" --arg arch "$arch" '
        [$latest] + [.[] | . as $r
        | select(.tag_name != $latest)
        | select(any(.assets[]; .name == ("Godot_v" + $r.tag_name + "_linux." + $arch + ".zip")))
        | .tag_name][:7] | .[]' <<<"$releases")
    labels=()
    for tag in "${tags[@]}"; do
        if [[ $tag == "$latest" ]]; then labels+=("$tag · recommended")
        elif [[ $tag == *-stable ]]; then labels+=("$tag · stable")
        else labels+=("$tag · unstable"); fi
    done
    choose 'Choose a release' "${labels[@]}"
    version=${tags[selected]}
fi
if [[ -n $version ]]; then
    [[ $version != *-* ]] && version+=-stable
    [[ $version =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?-(stable|dev[0-9]+|beta[0-9]+|rc[0-9]+)$ ]] || fail 'Invalid release tag.'
    release=$(fetch "$api/tags/$version")
else
    release=$(fetch "$api/latest")
fi
tag=$(jq -er .tag_name <<<"$release")
name=Godot_v${tag}_linux.$arch
asset=$(jq -ce --arg name "$name.zip" '.assets[] | select(.name == $name)' <<<"$release") || fail "No Linux $arch build."
printf 'Godot %s · Linux %s\n' "$tag" "$arch"
[[ $mode != check ]] || exit 0

if $interactive; then
    custom=false
    if [[ -z $scope && -z $dir ]]; then
        choose 'Install location' 'Only me · ~/.local/bin' 'All users · /usr/local/bin (sudo)' 'Custom directory · only me'
        case $selected in 0) scope=--local ;; 1) scope=--global ;; 2) scope=--local; custom=true ;; esac
    elif [[ -z $dir ]]; then
        choose 'Executable directory' 'Use the default directory' 'Choose a custom directory'
        [[ $selected != 1 ]] || custom=true
    fi
    if $custom; then
        printf '\n%sDirectory:%s ' "$cyan" "$reset"
        IFS= read -r dir
        [[ -n $dir ]] || fail 'Directory cannot be empty.'
        case $dir in '~') dir=$HOME ;; '~/'*) dir=$HOME/${dir:2} ;; esac
    fi
fi
if [[ $scope == --global ]]; then
    dir=${dir:-/usr/local/bin}; data=/usr/local/share
else
    dir=${dir:-$HOME/.local/bin}; data=${XDG_DATA_HOME:-$HOME/.local/share}
fi
for path in "$dir" "$data"; do
    [[ $path != *$'\n'* && $path != *$'\r'* && $path != *$'\t'* ]] || fail 'Paths cannot contain tabs or newlines.'
done
binary=$(realpath -m -- "$dir")/godot
data=$(realpath -m -- "$data")
icon=$data/icons/hicolor/scalable/apps/godot.svg
launcher=$data/applications/godot.desktop
step "Install Godot $tag"
printf '  Executable  %s\n  Launcher    %s\n  Icon        %s\n' "$binary" "$launcher" "$icon"
if ! $yes; then
    $interactive || fail 'Use --yes and install options for noninteractive or TERM=dumb sessions.'
    choose 'Ready? Existing installation files will be replaced.' 'Cancel' 'Install Godot'
    [[ $selected == 1 ]] || { echo 'Cancelled.'; exit 0; }
fi
sudo_cmd=()
if [[ $scope == --global && $EUID != 0 ]]; then
    command -v sudo >/dev/null || fail 'Global installation requires sudo or root.'
    sudo_cmd=(sudo)
fi
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
step 'Downloading editor…'
progress=()
[[ ! -t 1 ]] || progress=(--no-silent --progress-bar)
fetch "${progress[@]}" "$(jq -er .browser_download_url <<<"$asset")" -o "$temp/godot.zip"
digest=$(jq -r '.digest // ""' <<<"$asset")
if [[ $digest == sha256:* ]]; then
    printf '%s  %s\n' "${digest#sha256:}" "$temp/godot.zip" | sha256sum --status -c - || fail 'Checksum mismatch; nothing installed.'
else
    sums=$(jq -er '.assets[] | select(.name == "SHA512-SUMS.txt") | .browser_download_url' <<<"$release")
    expected=$(fetch "$sums" | awk -v name="$name.zip" '$2 == name || $2 == "*" name {print $1}')
    [[ $expected =~ ^[[:xdigit:]]{128}$ ]] || fail 'Missing SHA-512 checksum.'
    printf '%s  %s\n' "$expected" "$temp/godot.zip" | sha512sum --status -c - || fail 'Checksum mismatch; nothing installed.'
fi
printf '%s✓%s Checksum verified\n' "$green" "$reset"
step 'Installing editor, icon, and launcher…'
# Extract only the expected binary, never arbitrary archive paths.
unzip -p "$temp/godot.zip" "$name" > "$temp/godot"
base=https://raw.githubusercontent.com/godotengine/godot/$tag
fetch "$base/misc/logo/icon.svg" -o "$temp/godot.svg" || fetch "$base/icon.svg" -o "$temp/godot.svg"
# Desktop Exec quoting is independent of shell quoting.
exec_path=${binary//%/%%}
for char in '\' '"' '`' '$'; do exec_path=${exec_path//"$char"/"\\$char"}; done
exec_path=${exec_path//\\/\\\\}
cat > "$temp/godot.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Godot
Comment=Create and edit games with Godot Engine
Exec="$exec_path" --project-manager
Icon=$icon
Terminal=false
Categories=Development;IDE;
StartupWMClass=Godot
EOF
"${sudo_cmd[@]}" install -Dm755 -- "$temp/godot" "$binary"
"${sudo_cmd[@]}" install -Dm644 -- "$temp/godot.svg" "$icon"
"${sudo_cmd[@]}" install -Dm644 -- "$temp/godot.desktop" "$launcher"
if command -v update-desktop-database >/dev/null; then
    "${sudo_cmd[@]}" update-desktop-database "${launcher%/*}"
fi
printf '\n%s✓ Godot %s installed.%s Open it from your application menu.\n' "$green$bold" "$tag" "$reset"
case :$PATH: in *:"${binary%/*}":*) ;; *) printf 'Add %s to PATH to use godot in a terminal.\n' "${binary%/*}" ;; esac
