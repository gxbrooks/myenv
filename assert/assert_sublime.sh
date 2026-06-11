#!/bin/bash
#
# Assert Sublime Text packages and user config.
#
# Ensures Package Control is present, installs packages from dotfiles/sublime/packages.txt
# (Pretty JSON for formatting/minifying JSON), and symlinks user settings from the repo.
#
# Usage:
#   ./assert_sublime.sh [--Debug|-d] [--Check|-c]

DEBUG=false
CHECK=false

script_name="$(basename "${BASH_SOURCE[0]}")"
assert_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$assert_dir/.." && pwd)"
repo_sublime_dir="$repo_root/dotfiles/sublime"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d) DEBUG=true ;;
        --Check|-c) CHECK=true ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name."
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Debug   : Starting: $script_name"
$DEBUG && echo "Debug   : repo_sublime_dir = $repo_sublime_dir"

PACKAGE_CONTROL_URL="https://packagecontrol.io/Package%20Control.sublime-package"
PRETTY_JSON_REPO="https://github.com/dzhibas/SublimePrettyJson.git"

is_sublime_installed() {
    command -v subl >/dev/null 2>&1 || dpkg-query -W -f='${Status}' sublime-text 2>/dev/null | grep -q "install ok installed"
}

detect_sublime_config_dir() {
    local dir
    for dir in "$HOME/.config/sublime-text" "$HOME/.config/sublime-text-3"; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return 0
        fi
    done
    echo "$HOME/.config/sublime-text"
}

is_sublime_text_3() {
    if [[ -d "$HOME/.config/sublime-text-3" && ! -d "$HOME/.config/sublime-text" ]]; then
        return 0
    fi
    local version_output
    version_output="$(subl --version 2>/dev/null || true)"
    if [[ "$version_output" =~ [Bb]uild[[:space:]]+3[0-9]{3} ]]; then
        return 0
    fi
    return 1
}

mkdir_if_missing() {
    local path="$1"
    if [[ -d "$path" ]]; then
        $DEBUG && echo "Debug   : Directory exists: $path"
        return 0
    fi
    if $CHECK; then
        echo "Check   : Would create directory: $path"
        return 0
    fi
    mkdir -p "$path"
    echo "Info    : Created directory: $path"
}

install_package_control() {
    local installed_packages_dir="$1"
    local package_file="$installed_packages_dir/Package Control.sublime-package"

    if [[ -f "$package_file" ]]; then
        $DEBUG && echo "Debug   : Package Control already installed"
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would install Package Control to $package_file"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "Error   : curl is required to download Package Control"
        return 1
    fi

    echo "Info    : Installing Package Control"
    if curl -fsSL -o "$package_file" "$PACKAGE_CONTROL_URL"; then
        echo "Result  : Package Control installed"
        return 0
    fi
    echo "Error   : Failed to download Package Control"
    rm -f "$package_file"
    return 1
}

is_package_installed() {
    local packages_dir="$1"
    local installed_packages_dir="$2"
    local package_name="$3"
    local package_slug="${package_name// /}"

    if [[ -d "$packages_dir/$package_name" ]]; then
        return 0
    fi
    if [[ -f "$installed_packages_dir/$package_name.sublime-package" ]]; then
        return 0
    fi
    if [[ -f "$installed_packages_dir/${package_slug}.sublime-package" ]]; then
        return 0
    fi
    return 1
}

install_pretty_json() {
    local packages_dir="$1"
    local package_dir="$packages_dir/Pretty JSON"

    if is_package_installed "$packages_dir" "$2" "Pretty JSON"; then
        $DEBUG && echo "Debug   : Pretty JSON already installed"
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would install Pretty JSON to $package_dir"
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "Error   : git is required to install Pretty JSON"
        return 1
    fi

    echo "Info    : Installing Pretty JSON (git clone)"
    if git clone "$PRETTY_JSON_REPO" "$package_dir"; then
        if is_sublime_text_3; then
            echo "Info    : Checking out Pretty JSON st3 branch for Sublime Text 3"
            git -C "$package_dir" checkout st3 >/dev/null 2>&1 || true
        fi
        echo "Result  : Pretty JSON installed"
        return 0
    fi
    echo "Error   : Failed to clone Pretty JSON"
    return 1
}

install_packages_from_list() {
    local packages_dir="$1"
    local installed_packages_dir="$2"
    local packages_file="$repo_sublime_dir/packages.txt"
    local failed=0

    if [[ ! -f "$packages_file" ]]; then
        echo "Warning : Packages file not found at $packages_file"
        return 0
    fi

    while IFS= read -r package_name || [[ -n "$package_name" ]]; do
        package_name="$(echo "$package_name" | sed 's/#.*//' | xargs)"
        [[ -z "$package_name" ]] && continue

        if is_package_installed "$packages_dir" "$installed_packages_dir" "$package_name"; then
            $DEBUG && echo "Debug   : Package already installed: $package_name"
            continue
        fi

        case "$package_name" in
            "Pretty JSON")
                if ! install_pretty_json "$packages_dir" "$installed_packages_dir"; then
                    failed=1
                fi
                ;;
            *)
                if $CHECK; then
                    echo "Check   : Would install Sublime package: $package_name (via Package Control on next launch)"
                else
                    echo "Info    : Package '$package_name' will be installed by Package Control on next Sublime launch"
                fi
                ;;
        esac
    done < "$packages_file"

    return $failed
}

sync_sublime_user_file() {
    local filename="$1"
    local user_dir="$2"
    local local_path="$user_dir/$filename"
    local repo_path="$repo_sublime_dir/$filename"

    if [[ ! -f "$repo_path" ]]; then
        $DEBUG && echo "Debug   : No repo file for $filename; skipping"
        return 0
    fi

    echo "Info    : Processing $filename"

    if [[ -L "$local_path" ]]; then
        local current_target
        current_target="$(readlink -f "$local_path" 2>/dev/null || true)"
        if [[ "$current_target" == "$repo_path" ]]; then
            $DEBUG && echo "Debug   : Symlink already correct for $filename"
            return 0
        fi
    fi

    if [[ -f "$local_path" && ! -L "$local_path" ]]; then
        if $CHECK; then
            echo "Check   : Would replace local $filename with symlink to repo"
        else
            rm -f "$local_path"
            ln -s "$repo_path" "$local_path"
            echo "Result  : Linked $filename to repository version"
        fi
        return 0
    fi

    if [[ ! -e "$local_path" ]]; then
        if $CHECK; then
            echo "Check   : Would create symlink $local_path -> $repo_path"
        else
            ln -s "$repo_path" "$local_path"
            echo "Result  : Created symlink for $filename"
        fi
        return 0
    fi

    $DEBUG && echo "Debug   : No action needed for $filename"
}

trigger_package_control_bootstrap() {
    if $CHECK; then
        echo "Check   : Would run Sublime in background to bootstrap Package Control"
        return 0
    fi

    if ! command -v subl >/dev/null 2>&1; then
        $DEBUG && echo "Debug   : subl not in PATH; skipping Package Control bootstrap"
        return 0
    fi

    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        echo "Info    : Starting Sublime briefly to bootstrap Package Control"
        subl -b >/dev/null 2>&1 || true
        sleep 2
        pkill -x sublime_text >/dev/null 2>&1 || true
    else
        $DEBUG && echo "Debug   : No display available; skipping Sublime bootstrap (packages installed via git clone)"
    fi
}

if ! is_sublime_installed; then
    if $CHECK; then
        echo "Check   : Would require sublime-text to assert Sublime packages"
        echo "Result  : assert_sublime check complete"
        exit 0
    fi
    echo "Warning : Sublime Text not installed; skipping Sublime package assertion"
    exit 0
fi

SUBLIME_CONFIG_DIR="$(detect_sublime_config_dir)"
INSTALLED_PACKAGES_DIR="$SUBLIME_CONFIG_DIR/Installed Packages"
PACKAGES_DIR="$SUBLIME_CONFIG_DIR/Packages"
USER_DIR="$PACKAGES_DIR/User"

$DEBUG && echo "Debug   : SUBLIME_CONFIG_DIR = $SUBLIME_CONFIG_DIR"

FAILED=0

mkdir_if_missing "$SUBLIME_CONFIG_DIR" || exit 1
mkdir_if_missing "$INSTALLED_PACKAGES_DIR" || exit 1
mkdir_if_missing "$PACKAGES_DIR" || exit 1
mkdir_if_missing "$USER_DIR" || exit 1
mkdir_if_missing "$repo_sublime_dir" || exit 1

if ! install_package_control "$INSTALLED_PACKAGES_DIR"; then
    FAILED=1
fi

sync_sublime_user_file "Package Control.sublime-settings" "$USER_DIR"
sync_sublime_user_file "Default (Linux).sublime-keymap" "$USER_DIR"

if ! install_packages_from_list "$PACKAGES_DIR" "$INSTALLED_PACKAGES_DIR"; then
    FAILED=1
fi

trigger_package_control_bootstrap

if $CHECK; then
    echo "Result  : assert_sublime check complete"
elif [[ $FAILED -ne 0 ]]; then
    echo "Error   : assert_sublime finished with failures"
    exit 1
else
    echo "Result  : assert_sublime finished successfully"
fi

exit 0
