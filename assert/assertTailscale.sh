#!/bin/bash
#
# Assert Tailscale (mesh VPN) — install, join the tailnet non-interactively,
# and verify connectivity. Idempotent and safe to run multiple times.
#
# Installs via the official installer (https://tailscale.com/install.sh),
# which already detects the host distro (apt/dnf/yum/zypper/pacman/...) —
# this script does not assume one.
#
# Does NOT enable Tailscale SSH (`tailscale up --ssh`). Existing SSH keys and
# ssh/config host aliases keep working; this only joins the node to the tailnet.
#
# Auth key resolution (first match wins):
#   1. $TAILSCALE_AUTHKEY environment variable
#   2. ${XDG_CONFIG_HOME:-~/.config}/tailscale/env  (mode 0600; TAILSCALE_AUTHKEY=...)
# Generate a reusable key in the Tailscale admin console under Settings > Keys.
# See dotfiles/tailscale/env.example for the secrets-file template.
#
# Usage: assertTailscale.sh [--Debug|-d] [--Check|-c] [--tags|-t <tag:a,tag:b>]

DEBUG=false
CHECK=false
TAGS="tag:homelab"

script_name="$(basename "${BASH_SOURCE[0]}")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d) DEBUG=true ;;
        --Check|-c) CHECK=true ;;
        --tags|-t)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error   : Missing value for --tags|-t" >&2
                exit 1
            fi
            TAGS="$1"
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." >&2
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--tags|-t <tag:a,tag:b>]" >&2
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Debug   : Starting: $script_name"
$DEBUG && echo "Debug   : script_dir = $script_dir"
$DEBUG && echo "Debug   : TAGS = $TAGS"

is_tailscale_installed() {
    command -v tailscale >/dev/null 2>&1
}

install_tailscale() {
    if is_tailscale_installed; then
        $DEBUG && echo "Debug   : tailscale already installed ($(tailscale version 2>/dev/null | head -1))"
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would install Tailscale (official installer, auto-detects distro)"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "Info    : Installing curl (required for Tailscale download)"
        sudo apt install -y curl || {
            echo "Error   : Failed to install curl"
            return 1
        }
    fi

    echo "Info    : Installing Tailscale (official installer)"
    tmp_installer="$(mktemp /tmp/tailscale-install_XXXXXX.sh)"
    if ! curl -fsSL https://tailscale.com/install.sh -o "$tmp_installer"; then
        echo "Error   : Failed to download Tailscale installer"
        rm -f "$tmp_installer"
        return 1
    fi
    if ! sh "$tmp_installer"; then
        echo "Error   : Tailscale installer failed"
        rm -f "$tmp_installer"
        return 1
    fi
    rm -f "$tmp_installer"

    if ! is_tailscale_installed; then
        echo "Error   : Tailscale installer ran but the tailscale command was not found"
        return 1
    fi

    echo "Result  : Tailscale installed ($(tailscale version 2>/dev/null | head -1))"
    return 0
}

# BackendState: "Running" means authenticated and connected to the tailnet.
# `tailscale status` reads the local socket and needs no sudo.
backend_state() {
    tailscale status --json 2>/dev/null | grep -o '"BackendState":[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/'
}

is_joined() {
    [[ "$(backend_state)" == "Running" ]]
}

resolve_authkey() {
    if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
        $DEBUG && echo "Debug   : Using TAILSCALE_AUTHKEY from environment"
        return 0
    fi

    local secrets_file="${XDG_CONFIG_HOME:-$HOME/.config}/tailscale/env"
    if [[ -f "$secrets_file" ]]; then
        # shellcheck disable=SC1090
        set -a
        source "$secrets_file"
        set +a
        if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
            $DEBUG && echo "Debug   : Using TAILSCALE_AUTHKEY from $secrets_file"
            return 0
        fi
    fi

    echo "Error   : TAILSCALE_AUTHKEY is not set." >&2
    echo "Error   : Set it in the environment, or create $secrets_file (mode 0600) with TAILSCALE_AUTHKEY=... (see dotfiles/tailscale/env.example)." >&2
    echo "Error   : Generate a reusable key in the Tailscale admin console under Settings > Keys." >&2
    return 1
}

join_tailnet() {
    if is_joined; then
        $DEBUG && echo "Debug   : Already joined to tailnet (BackendState=Running); not re-joining"
        echo "Result  : Already joined to tailnet"
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would join tailnet (tailscale up --advertise-tags=$TAGS)"
        return 1
    fi

    resolve_authkey || return 1

    echo "Info    : Joining tailnet (non-interactive, tags=$TAGS)"
    if ! sudo tailscale up --authkey="$TAILSCALE_AUTHKEY" --advertise-tags="$TAGS"; then
        echo "Error   : tailscale up failed" >&2
        return 1
    fi

    echo "Result  : Joined tailnet"
    return 0
}

verify_connected() {
    if $CHECK; then
        echo "Check   : Would verify tailscale status and IP"
        return 0
    fi

    local state ip attempt
    # Backend state takes a moment to settle after `tailscale up` returns; poll
    # rather than failing on a transient post-up state. Observed up to ~8s in practice.
    for attempt in $(seq 1 15); do
        state="$(backend_state)"
        [[ "$state" == "Running" ]] && break
        sleep 1
    done
    if [[ "$state" != "Running" ]]; then
        echo "Error   : Tailscale is not connected (BackendState=${state:-unknown})" >&2
        echo "Error   : Run 'tailscale status' and 'journalctl -u tailscaled' to diagnose." >&2
        exit 1
    fi

    ip="$(tailscale ip -4 2>/dev/null)"
    if [[ -z "$ip" ]]; then
        echo "Error   : Tailscale reports BackendState=Running but no IPv4 address was returned" >&2
        exit 1
    fi

    echo "Result  : Tailscale connected — $(hostname) is reachable at $ip"
    return 0
}

install_tailscale
install_rc=$?
if [[ $install_rc -ne 0 ]] && ! $CHECK; then
    exit 1
fi

join_tailnet
join_rc=$?
if [[ $join_rc -ne 0 ]] && ! $CHECK; then
    exit 1
fi

verify_connected

if $CHECK; then
    echo "Result  : assertTailscale check complete"
else
    echo "Result  : assertTailscale finished successfully"
fi

exit 0
