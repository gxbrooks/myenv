#!/bin/bash
#
# Assert MyEnv — ensure ~/.bashrc sources this repo's .bashrc (keychain, etc.).
# Idempotent. Invoked by assert_myenv.sh or run standalone.
#
# Usage: assert_bashrc.sh [--Debug|-d] [--Check|-c]

DEBUG=false
CHECK=false

script_name="$(basename "${BASH_SOURCE[0]}")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d) DEBUG=true ;;
        --Check|-c) CHECK=true ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." >&2
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c]" >&2
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Debug   : Starting: $script_name"

ensure_home_bashrc_sources_myenv() {
    local myenv_bashrc="$script_dir/.bashrc"
    local home_rc="${HOME}/.bashrc"
    local marker="# myenv: sourced by assert_myenv.sh"

    if [[ ! -f "$myenv_bashrc" ]]; then
        echo "Warning : myenv .bashrc not found: $myenv_bashrc"
        return 1
    fi

    if [[ -f "$home_rc" ]] && grep -qF "$myenv_bashrc" "$home_rc" 2>/dev/null; then
        $DEBUG && echo "Debug   : $home_rc already references $myenv_bashrc"
        return 0
    fi
    if [[ -f "$home_rc" ]] && grep -qF "$marker" "$home_rc" 2>/dev/null; then
        $DEBUG && echo "Debug   : $home_rc already contains myenv marker"
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would append source of $myenv_bashrc to $home_rc"
        return 0
    fi

    if [[ ! -f "$home_rc" ]]; then
        touch "$home_rc" || {
            echo "Error   : Could not create $home_rc"
            return 1
        }
    fi

    {
        echo ""
        echo "$marker"
        echo "if [ -f \"$myenv_bashrc\" ]; then"
        echo "  . \"$myenv_bashrc\""
        echo "fi"
    } >>"$home_rc" || {
        echo "Error   : Could not append to $home_rc"
        return 1
    }
    echo "Info    : Appended source of $myenv_bashrc to $home_rc"
    return 0
}

if ! ensure_home_bashrc_sources_myenv; then
    if ! $CHECK; then
        echo "Warning : Could not ensure ~/.bashrc sources myenv/.bashrc"
        exit 1
    fi
fi

echo "Result  : assert_bashrc finished successfully"
exit 0
