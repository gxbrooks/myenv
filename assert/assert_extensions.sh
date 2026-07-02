#!/bin/bash
#
# Assert Cursor extensions from repository list.
#
# Uses the headless Cursor CLI (bin/cursor → cli.js), not the Electron binary.
# One --list-extensions call, then a single batched --install-extension invocation.
#
# Usage:
#   ./assert_extensions.sh [extensions_file]
#   ./assert_extensions.sh --merge|-m [extensions_file]
#   ./assert_extensions.sh --Debug|-d [--Check|-c]

DEBUG=false
CHECK=false
MERGE_MODE=false

script_name="$(basename "${BASH_SOURCE[0]}")"
assert_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$assert_dir/.." && pwd)"
repo_cursor_dir="$repo_root/dotfiles/cursor"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d) DEBUG=true; shift ;;
        --Check|-c) CHECK=true; shift ;;
        --merge|-m) MERGE_MODE=true; shift ;;
        *) break ;;
    esac
done

extensions_file="${1:-extensions.txt}"
extensions_path="$repo_cursor_dir/$extensions_file"

$DEBUG && echo "Debug   : Starting: $script_name"
$DEBUG && echo "Debug   : extensions_path = $extensions_path"

resolve_cursor_cli() {
    local candidate

    # Prefer the headless CLI script shipped with Cursor (cli.js via ELECTRON_RUN_AS_NODE).
    for candidate in /opt/cursor/usr/share/cursor/bin/cursor /opt/cursor/bin/cursor; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    if command -v cursor >/dev/null 2>&1; then
        candidate="$(command -v cursor)"
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    fi

    return 1
}

CURSOR_CLI=""
if CURSOR_CLI="$(resolve_cursor_cli)"; then
    $DEBUG && echo "Debug   : Cursor CLI = $CURSOR_CLI"
else
    if $CHECK; then
        echo "Check   : Would require Cursor CLI in PATH to assert extensions"
        echo "Result  : assert_extensions check complete"
        exit 0
    fi
    echo "Warning : Cursor CLI not found; skipping extension assertion"
    exit 0
fi

cursor_cli() {
    "$CURSOR_CLI" "$@"
}

list_installed_extensions() {
    cursor_cli --list-extensions 2>/dev/null | sed '/^[[:space:]]*$/d'
}

if $MERGE_MODE; then
    echo "Info    : Merge mode: combining installed extensions with repository list"
    tmp_file="/tmp/cursor_extensions_merge_$$.tmp"
    installed_extensions="$(list_installed_extensions)"

    if [[ -f "$extensions_path" ]]; then
        if $CHECK; then
            echo "Check   : Would merge installed extensions into $extensions_path"
        else
            (echo "$installed_extensions"; <"$extensions_path" sort -u) | sed '/^[[:space:]]*$/d' | sort -u > "$tmp_file"
            mv "$tmp_file" "$extensions_path"
            echo "Result  : Merged extensions list updated at $extensions_path"
        fi
    else
        if $CHECK; then
            echo "Check   : Would create $extensions_path from installed extensions"
        else
            mkdir -p "$repo_cursor_dir"
            echo "$installed_extensions" | sort -u > "$tmp_file"
            mv "$tmp_file" "$extensions_path"
            echo "Result  : Created extensions list at $extensions_path"
        fi
    fi
fi

if [[ ! -f "$extensions_path" ]]; then
    echo "Warning : Extensions file not found at $extensions_path; nothing to install"
    if $CHECK; then
        echo "Result  : assert_extensions check complete"
    else
        echo "Result  : assert_extensions finished successfully"
    fi
    exit 0
fi

echo "Info    : Asserting extensions from $extensions_path"

installed_file="$(mktemp /tmp/cursor_extensions_installed_XXXXXX.txt)"
trap 'rm -f "$installed_file"' EXIT
list_installed_extensions | sort -u > "$installed_file"

declare -a required_extensions=()
declare -a missing_extensions=()

while IFS= read -r extension_id || [[ -n "$extension_id" ]]; do
    extension_id="$(echo "$extension_id" | xargs)"
    [[ -z "$extension_id" ]] && continue
    required_extensions+=("$extension_id")

    if grep -Fxq "$extension_id" "$installed_file"; then
        $DEBUG && echo "Debug   : Extension already installed: $extension_id"
    else
        missing_extensions+=("$extension_id")
        if $CHECK; then
            echo "Check   : Would install Cursor extension: $extension_id"
        fi
    fi
done < "$extensions_path"

already_installed_count=$((${#required_extensions[@]} - ${#missing_extensions[@]}))
$DEBUG && echo "Debug   : Required=${#required_extensions[@]} missing=${#missing_extensions[@]} already=$already_installed_count"

if $CHECK; then
    if [[ ${#missing_extensions[@]} -eq 0 ]]; then
        echo "Check   : All ${#required_extensions[@]} required extension(s) already installed"
    else
        echo "Check   : Would install ${#missing_extensions[@]} missing extension(s) in one Cursor CLI call"
    fi
    echo "Result  : assert_extensions check complete"
    exit 0
fi

if [[ ${#missing_extensions[@]} -eq 0 ]]; then
    echo "Result  : assert_extensions: all ${#required_extensions[@]} extension(s) already installed"
    exit 0
fi

echo "Info    : Installing ${#missing_extensions[@]} missing extension(s) via headless Cursor CLI"

install_args=()
for extension_id in "${missing_extensions[@]}"; do
    install_args+=(--install-extension "$extension_id")
done

if ! cursor_cli "${install_args[@]}"; then
    echo "Error   : Cursor extension install failed"
    exit 1
fi

# Verify installs
list_installed_extensions | sort -u > "$installed_file"
still_missing=()
for extension_id in "${missing_extensions[@]}"; do
    if ! grep -Fxq "$extension_id" "$installed_file"; then
        still_missing+=("$extension_id")
    fi
done

if [[ ${#still_missing[@]} -gt 0 ]]; then
    echo "Error   : Extension install verification failed for: ${still_missing[*]}"
    exit 1
fi

echo "Result  : assert_extensions: installed ${#missing_extensions[@]} extension(s), $already_installed_count already present"
exit 0
