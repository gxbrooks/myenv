#!/bin/bash
#
# Assert Cursor extensions from repository list.
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

if ! command -v cursor >/dev/null 2>&1; then
    if $CHECK; then
        echo "Check   : Would require Cursor CLI in PATH to assert extensions"
        echo "Result  : assert_extensions check complete"
        exit 0
    fi
    echo "Warning : Cursor CLI ('cursor') not found; skipping extension assertion"
    exit 0
fi

if $MERGE_MODE; then
    echo "Info    : Merge mode: combining installed extensions with repository list"
    tmp_file="/tmp/cursor_extensions_merge_$$.tmp"
    installed_extensions="$(cursor --list-extensions 2>/dev/null || true)"

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
            echo "$installed_extensions" | sed '/^[[:space:]]*$/d' | sort -u > "$tmp_file"
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
while IFS= read -r extension_id || [[ -n "$extension_id" ]]; do
    extension_id="$(echo "$extension_id" | xargs)"
    [[ -z "$extension_id" ]] && continue

    if $CHECK; then
        echo "Check   : Would install Cursor extension: $extension_id"
    else
        if cursor --list-extensions 2>/dev/null | rg -x "$extension_id" >/dev/null 2>&1; then
            $DEBUG && echo "Debug   : Extension already installed: $extension_id"
            continue
        fi
        echo "Info    : Installing Cursor extension: $extension_id"
        cursor --install-extension "$extension_id" >/dev/null
    fi
done < "$extensions_path"

if $CHECK; then
    echo "Result  : assert_extensions check complete"
else
    echo "Result  : assert_extensions finished successfully"
fi

exit 0
