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

resolve_cursor_cli_script() {
    local candidate
    for candidate in \
        /opt/cursor/usr/share/cursor/bin/cursor \
        /opt/cursor/bin/cursor; do
        if [[ -x "$candidate" ]] && ! file "$candidate" 2>/dev/null | grep -q 'ELF'; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

resolve_cursor_cli() {
    local candidate

    if candidate="$(resolve_cursor_cli_script 2>/dev/null)"; then
        echo "$candidate"
        return 0
    fi

    # Only trust PATH cursor when it is the headless launcher, not the Electron binary.
    if command -v cursor >/dev/null 2>&1; then
        candidate="$(command -v cursor)"
        if [[ -x "$candidate" ]] && ! file "$candidate" 2>/dev/null | grep -q 'ELF'; then
            if grep -qF 'usr/share/cursor/cursor"' "$candidate" 2>/dev/null \
                && ! grep -qF 'usr/share/cursor/bin/cursor"' "$candidate" 2>/dev/null; then
                $DEBUG && echo "Debug   : Ignoring $candidate (wrapper execs Electron binary)"
            else
                echo "$candidate"
                return 0
            fi
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

# Install in dependency waves so dependents (e.g. debugpy) are not activated before
# their prerequisites (e.g. ms-python.python) finish installing.
declare -A extension_deps=(
    ["ms-python.debugpy"]="ms-python.python"
    ["vscjava.vscode-java-debug"]="redhat.java"
    ["vscjava.vscode-java-test"]="redhat.java"
    ["vscjava.vscode-java-dependency"]="redhat.java"
    ["vscjava.vscode-maven"]="redhat.java"
    ["vscjava.vscode-gradle"]="redhat.java"
)

install_batch() {
    local -a batch=("$@")
    [[ ${#batch[@]} -eq 0 ]] && return 0
    local -a install_args=()
    local extension_id
    for extension_id in "${batch[@]}"; do
        install_args+=(--install-extension "$extension_id")
    done
    cursor_cli "${install_args[@]}"
}

declare -a wave1=()
declare -a wave2=()

for extension_id in "${missing_extensions[@]}"; do
    dep="${extension_deps[$extension_id]:-}"
    if [[ -n "$dep" ]] && printf '%s\n' "${missing_extensions[@]}" | grep -Fxq "$dep"; then
        wave2+=("$extension_id")
    else
        wave1+=("$extension_id")
    fi
done

if ! install_batch "${wave1[@]}"; then
    echo "Error   : Cursor extension install failed (wave 1)"
    exit 1
fi

if [[ ${#wave2[@]} -gt 0 ]]; then
    if ! install_batch "${wave2[@]}"; then
        echo "Error   : Cursor extension install failed (wave 2)"
        exit 1
    fi
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
