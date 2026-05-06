#!/bin/bash
#
# Assert dotfiles for Cursor config.
# Ensures ~/.config/Cursor/User/{settings.json,keybindings.json} are symlinked to
# this repository under dotfiles/cursor/.
#
# Usage:
#   ./assert_dotfiles.sh              # Standard mode (repo version takes precedence)
#   ./assert_dotfiles.sh --merge|-m   # Merge mode (combine local + repo JSON)
#   ./assert_dotfiles.sh --Debug|-d
#   ./assert_dotfiles.sh --Check|-c

DEBUG=false
CHECK=false
MERGE_MODE=false

script_name="$(basename "${BASH_SOURCE[0]}")"
assert_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$assert_dir/.." && pwd)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d) DEBUG=true ;;
        --Check|-c) CHECK=true ;;
        --merge|-m) MERGE_MODE=true ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name."
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--merge|-m]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Debug   : Starting: $script_name"
$DEBUG && echo "Debug   : repo_root = $repo_root"

CURSOR_CONFIG_DIR="$HOME/.config/Cursor/User"
REPO_CURSOR_DIR="$repo_root/dotfiles/cursor"
SETTINGS_FILE="settings.json"
KEYBINDINGS_FILE="keybindings.json"

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

merge_json_files() {
    local local_file="$1"
    local repo_file="$2"
    local merged_file="$3"

    if ! command -v jq >/dev/null 2>&1; then
        echo "Warning : jq is required for merge mode. Install with: sudo apt install jq"
        return 1
    fi
    if ! jq empty "$local_file" >/dev/null 2>&1; then
        echo "Warning : $local_file is not valid JSON, skipping merge"
        return 1
    fi
    if ! jq empty "$repo_file" >/dev/null 2>&1; then
        echo "Warning : $repo_file is not valid JSON, skipping merge"
        return 1
    fi

    jq -s '.[0] * .[1]' "$repo_file" "$local_file" > "$merged_file.tmp" || return 1
    mv "$merged_file.tmp" "$merged_file"
    return 0
}

sync_cursor_file() {
    local filename="$1"
    local local_path="$CURSOR_CONFIG_DIR/$filename"
    local repo_path="$REPO_CURSOR_DIR/$filename"

    echo "Info    : Processing $filename"

    if [[ -f "$repo_path" ]]; then
        if [[ -f "$local_path" && ! -L "$local_path" ]]; then
            if $MERGE_MODE; then
                echo "Info    : Merge mode enabled for $filename"
                if $CHECK; then
                    echo "Check   : Would merge $local_path into $repo_path and re-link"
                else
                    if merge_json_files "$local_path" "$repo_path" "$repo_path"; then
                        rm -f "$local_path"
                        ln -s "$repo_path" "$local_path"
                        echo "Result  : Merged and linked $filename"
                    else
                        rm -f "$local_path"
                        ln -s "$repo_path" "$local_path"
                        echo "Warning : Merge failed; linked repository version for $filename"
                    fi
                fi
            else
                if $CHECK; then
                    echo "Check   : Would replace local $filename with symlink to repo"
                else
                    rm -f "$local_path"
                    ln -s "$repo_path" "$local_path"
                    echo "Result  : Linked $filename to repository version"
                fi
            fi
        elif [[ ! -e "$local_path" ]]; then
            if $CHECK; then
                echo "Check   : Would create symlink $local_path -> $repo_path"
            else
                ln -s "$repo_path" "$local_path"
                echo "Result  : Created symlink for $filename"
            fi
        else
            $DEBUG && echo "Debug   : No action needed for $filename"
        fi
    elif [[ -f "$local_path" && ! -L "$local_path" ]]; then
        if $CHECK; then
            echo "Check   : Would copy $local_path to $repo_path and symlink back"
        else
            cp "$local_path" "$repo_path"
            rm -f "$local_path"
            ln -s "$repo_path" "$local_path"
            echo "Result  : Imported and linked $filename"
        fi
    else
        echo "Warning : No usable $filename found in local Cursor config or repository"
    fi
}

mkdir_if_missing "$CURSOR_CONFIG_DIR" || exit 1
mkdir_if_missing "$REPO_CURSOR_DIR" || exit 1

sync_cursor_file "$SETTINGS_FILE"
sync_cursor_file "$KEYBINDINGS_FILE"

if $CHECK; then
    echo "Result  : assert_dotfiles check complete"
else
    echo "Result  : assert_dotfiles finished successfully"
fi

exit 0
