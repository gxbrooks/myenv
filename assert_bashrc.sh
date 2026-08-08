#!/bin/bash
#
# Assert MyEnv — ensure ~/.bashrc sources this repo's .bashrc (keychain, etc.)
# and seed local csdm-injector env (XDG; secrets never stored in the repo).
# Idempotent. Invoked by assert_myenv.sh or run standalone.
#
# Usage: assert_bashrc.sh [--Debug|-d] [--Check|-c]
#
# csdm-injector credentials live only at:
#   ${XDG_CONFIG_HOME:-~/.config}/csdm-injector/env  (mode 0600)
# Seeded once from dotfiles/csdm-injector/env.example or /opt/csdm-injector/.env.example.

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

# XDG dotenv for csdm-injector: directory 0700, env file 0600, never overwrite secrets.
ensure_csdm_injector_env() {
    local cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/csdm-injector"
    local env_file="${cfg_dir}/env"
    local example_dst="${cfg_dir}/env.example"
    local example_src=""
    local candidate

    for candidate in \
        "${script_dir}/dotfiles/csdm-injector/env.example" \
        "/opt/csdm-injector/.env.example" \
        "${HOME}/repos/csdm-injector/.env.example"
    do
        if [[ -f "$candidate" ]]; then
            example_src="$candidate"
            break
        fi
    done

    if [[ -z "$example_src" ]]; then
        echo "Warning : No csdm-injector env.example found; skip seeding ${cfg_dir}"
        return 0
    fi

    if $CHECK; then
        if [[ -d "$cfg_dir" && -f "$env_file" ]]; then
            echo "Check   : csdm-injector env already present at $env_file"
        else
            echo "Check   : Would create $cfg_dir and seed $env_file from $example_src"
        fi
        return 0
    fi

    mkdir -p "$cfg_dir" || {
        echo "Error   : Could not create $cfg_dir"
        return 1
    }
    chmod 700 "$cfg_dir" || true

    # Always refresh the non-secret example next to the real env file.
    cp -f "$example_src" "$example_dst"
    chmod 644 "$example_dst" || true

    if [[ -f "$env_file" ]]; then
        chmod 600 "$env_file" || true
        $DEBUG && echo "Debug   : Leaving existing $env_file unchanged"
        echo "✓ csdm-injector env present ($env_file)"
        return 0
    fi

    cp -f "$example_src" "$env_file" || {
        echo "Error   : Could not seed $env_file"
        return 1
    }
    chmod 600 "$env_file" || true
    echo "Info    : Seeded $env_file from $(basename "$example_src")"
    echo "Info    : Edit that file with SN_* values (never commit it); open a new shell to load"
    return 0
}

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

if ! ensure_csdm_injector_env; then
    if ! $CHECK; then
        echo "Warning : Could not ensure csdm-injector local env under ~/.config"
        exit 1
    fi
fi

echo "Result  : assert_bashrc finished successfully"
exit 0
