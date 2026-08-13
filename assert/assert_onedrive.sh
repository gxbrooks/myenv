#!/bin/bash
#
# Assert OneDrive (and future SharePoint) folders under $HOME via rclone.
#
# Each account is an rclone remote (onedrive-<id>) mounted at ~/<folder> by a
# systemd --user unit. Idempotent. Invoked by assert_myenv.sh or run standalone.
#
# Usage: assert_onedrive.sh [--Debug|-d] [--Check|-c]
#
# Microsoft login cannot be fully automated. On an interactive TTY the script
# runs rclone's browser OAuth. Otherwise it prints:
#   rclone config create onedrive-<id> onedrive config_type=onedrive
#
# Add further tenants or a personal OneDrive by appending to ONEDRIVE_ACCOUNTS.
# Do not reuse a remote name or mount folder across accounts.
#
# Optional: RCLONE_ONEDRIVE_CLIENT_ID / RCLONE_ONEDRIVE_CLIENT_SECRET for a
# tenant-approved Azure app if rclone's default client is blocked.

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
$DEBUG && echo "Debug   : script_dir = $script_dir"
$DEBUG && echo "Debug   : CHECK = $CHECK"
$DEBUG && echo "Debug   : HOME = $HOME"

# -----------------------------------------------------------------------------
# Accounts to assert. Pipe-separated fields:
#   id        — rclone remote onedrive-<id> and unit rclone-onedrive-<id>.service
#   label     — human-readable name (company or Personal)
#   kind      — business | personal | sharepoint
#               business/personal → rclone config_type=onedrive (My Files)
#               sharepoint        → config_type=sharepoint (needs site URL / drive_id)
#   portal    — OneDrive / SharePoint landing URL
#   folder    — directory name under $HOME (unique per account)
#   drive_id  — optional Graph/SharePoint drive id
#
# Examples for later accounts (do not duplicate id/folder):
#   "personal|Personal|personal|https://onedrive.live.com|OneDrive|"
#   "acme|Acme|business|https://acme-my.sharepoint.com/my|OneDrive-Acme|"
# -----------------------------------------------------------------------------
ONEDRIVE_ACCOUNTS=(
    "optimiz|Optimiz|business|https://optimiz-my.sharepoint.com/my|OneDrive-Optimiz|"
)

RCLONE_MIN_VERSION="1.64.0"
RCLONE_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/rclone/rclone.conf"
USER_SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
OBS_KEYRING="/usr/share/keyrings/obs-onedrive.gpg"
OBS_LIST="/etc/apt/sources.list.d/onedrive.list"

INSTALLED_COUNT=0
ALREADY_INSTALLED_COUNT=0
FAILED_COUNT=0
FAILED_STEPS=()

fail_step() {
    local step=$1
    local message=$2
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_STEPS+=("$step")
    echo "Warning : $message"
}

has_interactive_tty() {
    [[ -z "${NONINTERACTIVE:-}" && -z "${CURSOR_AGENT:-}" && -t 0 && -t 1 ]]
}

is_package_installed() {
    local pkg=$1
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

install_apt_package() {
    local pkg=$1
    if is_package_installed "$pkg"; then
        $DEBUG && echo "Debug   : Package '$pkg' is already installed"
        return 0
    fi
    if $CHECK; then
        echo "Check   : Would install package: $pkg"
        return 0
    fi
    echo "Info    : Installing package: $pkg"
    sudo apt update -qq
    if sudo apt install -y "$pkg"; then
        echo "Result  : Successfully installed $pkg"
        return 0
    fi
    fail_step "apt:$pkg" "Failed to install $pkg"
    return 1
}

rclone_version() {
    rclone version 2>/dev/null | awk 'NR==1 {print $2}' | sed 's/^v//'
}

rclone_is_current() {
    command -v rclone >/dev/null 2>&1 || return 1
    local ver
    ver="$(rclone_version)"
    [[ -n "$ver" ]] || return 1
    dpkg --compare-versions "$ver" ge "$RCLONE_MIN_VERSION" 2>/dev/null
}

remote_name() {
    local id=$1
    echo "onedrive-${id}"
}

account_sync_dir() {
    local folder=$1
    echo "$HOME/$folder"
}

account_unit_name() {
    local id=$1
    echo "rclone-onedrive-${id}.service"
}

rclone_config_type() {
    local kind=$1
    case "$kind" in
        sharepoint) echo "sharepoint" ;;
        *) echo "onedrive" ;;
    esac
}

remote_listed() {
    local name=$1
    command -v rclone >/dev/null 2>&1 || return 1
    rclone listremotes 2>/dev/null | grep -qx "${name}:"
}

remote_reachable() {
    local name=$1
    command -v rclone >/dev/null 2>&1 || return 1
    rclone lsf "${name}:" --max-depth 1 >/dev/null 2>&1
}

path_is_rclone_mount() {
    local path=$1
    findmnt -n -o FSTYPE --target "$path" 2>/dev/null | grep -q 'fuse.rclone'
}

install_rclone() {
    if rclone_is_current; then
        ALREADY_INSTALLED_COUNT=$((ALREADY_INSTALLED_COUNT + 1))
        echo "✓ rclone is already installed ($(rclone version 2>/dev/null | head -1))"
        return 0
    fi

    if $CHECK; then
        if command -v rclone >/dev/null 2>&1; then
            echo "Check   : Would upgrade rclone $(rclone_version) → ${RCLONE_MIN_VERSION}+ (rclone.org)"
        else
            echo "Check   : Would install rclone ${RCLONE_MIN_VERSION}+ from rclone.org"
        fi
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        install_apt_package curl || {
            fail_step "apt:curl" "curl is required to install rclone"
            return 1
        }
    fi
    install_apt_package unzip || true
    install_apt_package fuse3 || true

    echo "Info    : Installing rclone from rclone.org (Ubuntu universe is ${RCLONE_MIN_VERSION}-incompatible)"
    if ! curl -fsSL https://rclone.org/install.sh | sudo bash; then
        fail_step "rclone:install" "Official rclone installer failed"
        return 1
    fi
    if ! rclone_is_current; then
        fail_step "rclone:version" "rclone installed but version is still below ${RCLONE_MIN_VERSION}"
        return 1
    fi
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
    echo "Result  : Successfully installed $(rclone version 2>/dev/null | head -1)"
    return 0
}

cleanup_abraunegg_leftovers() {
    local unit confdir
    for unit in onedrive.service; do
        if systemctl --user is-enabled "$unit" >/dev/null 2>&1 \
            || systemctl --user is-active "$unit" >/dev/null 2>&1; then
            if $CHECK; then
                echo "Check   : Would disable leftover $unit"
            else
                echo "Info    : Disabling leftover $unit"
                systemctl --user disable --now "$unit" 2>/dev/null || true
            fi
        fi
    done

    local entry id
    for entry in "${ONEDRIVE_ACCOUNTS[@]}"; do
        IFS='|' read -r id _ <<< "$entry"
        unit="onedrive-${id}.service"
        if systemctl --user is-enabled "$unit" >/dev/null 2>&1 \
            || systemctl --user is-active "$unit" >/dev/null 2>&1 \
            || [[ -f "$USER_SYSTEMD_DIR/$unit" ]]; then
            if $CHECK; then
                echo "Check   : Would remove leftover abraunegg unit $unit"
            else
                echo "Info    : Removing leftover abraunegg unit $unit"
                systemctl --user disable --now "$unit" 2>/dev/null || true
                rm -f "$USER_SYSTEMD_DIR/$unit"
            fi
        fi
        confdir="${XDG_CONFIG_HOME:-$HOME/.config}/onedrive-${id}"
        if [[ -d "$confdir" ]]; then
            if $CHECK; then
                echo "Check   : Would remove leftover $confdir"
            else
                echo "Info    : Removing leftover abraunegg confdir $confdir"
                rm -rf "$confdir"
            fi
        fi
    done

    if [[ -f "$OBS_LIST" ]] || is_package_installed onedrive; then
        if $CHECK; then
            echo "Check   : Would remove leftover OBS onedrive package/repo"
            return 0
        fi
        echo "Info    : Removing leftover OBS onedrive client (replaced by rclone)"
        sudo apt remove -y onedrive 2>/dev/null || true
        sudo rm -f "$OBS_LIST" "$OBS_KEYRING"
        sudo rm -f /etc/systemd/user/default.target.wants/onedrive.service
    fi
}

write_user_unit() {
    local id=$1
    local label=$2
    local remote=$3
    local sync_dir=$4
    local unit_path="$USER_SYSTEMD_DIR/$(account_unit_name "$id")"
    local rclone_bin fusermount_bin desired tmp
    rclone_bin="$(command -v rclone)"
    fusermount_bin="$(command -v fusermount3 || command -v fusermount)"

    desired="$(cat <<EOF
[Unit]
Description=rclone mount OneDrive (${label})
Documentation=https://rclone.org/onedrive/
After=network-online.target
Wants=network-online.target
AssertPathIsDirectory=${sync_dir}

[Service]
Type=notify
TimeoutStartSec=60
ExecStart=${rclone_bin} mount ${remote}: ${sync_dir} --config=${RCLONE_CONFIG} --vfs-cache-mode writes --vfs-cache-max-age 24h --dir-cache-time 5m --umask 007 --log-level INFO
ExecStop=${fusermount_bin} -u ${sync_dir}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF
)"

    if [[ -f "$unit_path" ]] && [[ "$(cat "$unit_path")" == "$desired" ]]; then
        $DEBUG && echo "Debug   : systemd unit already matches: $unit_path"
        return 1
    fi
    tmp="$(mktemp)"
    printf '%s\n' "$desired" > "$tmp"
    mv "$tmp" "$unit_path"
    echo "Result  : Wrote systemd user unit $(account_unit_name "$id")"
    return 0
}

ensure_remote() {
    local id=$1
    local label=$2
    local kind=$3
    local portal=$4
    local drive_id=$5
    local remote config_type
    remote="$(remote_name "$id")"
    config_type="$(rclone_config_type "$kind")"

    if remote_listed "$remote" && remote_reachable "$remote"; then
        echo "✓ ${label} rclone remote '${remote}' is authenticated"
        return 0
    fi

    if $CHECK; then
        if remote_listed "$remote"; then
            echo "Check   : Remote ${remote} exists but is not reachable; would reconnect"
        else
            echo "Check   : Would create rclone remote ${remote} (${config_type}, portal ${portal})"
        fi
        return 1
    fi

    if ! has_interactive_tty; then
        fail_step "auth:${id}" "${label} rclone remote '${remote}' is not authenticated (no TTY / NONINTERACTIVE / CURSOR_AGENT)"
        echo "Info    : Authenticate later with:"
        echo "Info    :   rclone config create ${remote} onedrive config_type=${config_type}"
        echo "Info    : Portal for this account: $portal"
        echo "Info    : Then re-run: bash ${script_dir}/${script_name}"
        return 1
    fi

    local create_args=("$remote" onedrive config_type "$config_type")
    if [[ "$kind" == "business" || "$kind" == "sharepoint" ]]; then
        create_args+=(drive_type business)
    fi
    if [[ -n "$drive_id" ]]; then
        create_args+=(drive_id "$drive_id")
    fi
    if [[ -n "${RCLONE_ONEDRIVE_CLIENT_ID:-}" ]]; then
        create_args+=(client_id "$RCLONE_ONEDRIVE_CLIENT_ID")
    fi
    if [[ -n "${RCLONE_ONEDRIVE_CLIENT_SECRET:-}" ]]; then
        create_args+=(client_secret "$RCLONE_ONEDRIVE_CLIENT_SECRET")
    fi

    echo "Info    : Authenticating ${label} via rclone (browser window / localhost:53682)"
    echo "Info    : Portal for this account: $portal"
    if remote_listed "$remote"; then
        if rclone config reconnect "${remote}:"; then
            echo "Result  : Reconnected rclone remote ${remote}"
        else
            fail_step "auth:${id}" "rclone config reconnect failed for ${remote}"
            return 1
        fi
    else
        if rclone config create "${create_args[@]}"; then
            echo "Result  : Created rclone remote ${remote}"
        else
            fail_step "auth:${id}" "rclone config create failed for ${remote}"
            return 1
        fi
    fi

    if remote_reachable "$remote"; then
        echo "Result  : ${label} rclone remote '${remote}' is reachable"
        return 0
    fi
    fail_step "auth:${id}" "${label} remote '${remote}' was configured but listing files failed"
    return 1
}

ensure_account() {
    local entry=$1
    local id label kind portal folder drive_id
    IFS='|' read -r id label kind portal folder drive_id <<< "$entry"

    if [[ -z "$id" || -z "$label" || -z "$kind" || -z "$folder" ]]; then
        fail_step "account:parse" "Invalid ONEDRIVE_ACCOUNTS entry: $entry"
        return 1
    fi

    local remote sync_dir unit_name unit_path
    remote="$(remote_name "$id")"
    sync_dir="$(account_sync_dir "$folder")"
    unit_name="$(account_unit_name "$id")"
    unit_path="$USER_SYSTEMD_DIR/$unit_name"

    echo ""
    echo "Info    : Asserting OneDrive account '${label}' (${kind}) → ${sync_dir}"
    $DEBUG && echo "Debug   : portal = $portal"
    $DEBUG && echo "Debug   : remote = ${remote}:"
    $DEBUG && echo "Debug   : rclone.conf = $RCLONE_CONFIG"

    if $CHECK; then
        [[ -d "$sync_dir" ]] || echo "Check   : Would create directory: $sync_dir"
        ensure_remote "$id" "$label" "$kind" "$portal" "$drive_id" || true
        if [[ -f "$unit_path" ]]; then
            echo "Check   : systemd user unit already present: $unit_path"
        else
            echo "Check   : Would install systemd user unit: $unit_path"
        fi
        if path_is_rclone_mount "$sync_dir"; then
            echo "Check   : ${sync_dir} is already an rclone mount"
        fi
        return 0
    fi

    mkdir -p "$(dirname "$RCLONE_CONFIG")" "$sync_dir" "$USER_SYSTEMD_DIR"
    chmod 700 "$(dirname "$RCLONE_CONFIG")" "$sync_dir"
    [[ -f "$RCLONE_CONFIG" ]] && chmod 600 "$RCLONE_CONFIG"

    if ! ensure_remote "$id" "$label" "$kind" "$portal" "$drive_id"; then
        return 1
    fi

    local unit_changed=false
    if write_user_unit "$id" "$label" "$remote" "$sync_dir"; then
        unit_changed=true
    fi

    if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
        echo "Warning : XDG_RUNTIME_DIR is unset; cannot enable systemd --user unit now"
        echo "Info    : After login run: systemctl --user enable --now ${unit_name}"
        return 0
    fi

    systemctl --user daemon-reload
    if systemctl --user is-enabled "$unit_name" >/dev/null 2>&1 \
        && systemctl --user is-active "$unit_name" >/dev/null 2>&1 \
        && path_is_rclone_mount "$sync_dir" \
        && ! $unit_changed; then
        echo "✓ systemd user unit ${unit_name} is already enabled and mounted"
        return 0
    fi

    if $unit_changed && systemctl --user is-active "$unit_name" >/dev/null 2>&1; then
        echo "Info    : Restarting ${unit_name} after unit file change"
        systemctl --user restart "$unit_name" || {
            fail_step "systemd:${id}" "Failed to restart ${unit_name}"
            return 1
        }
    elif ! systemctl --user enable --now "$unit_name"; then
        fail_step "systemd:${id}" "Failed to enable/start ${unit_name}"
        return 1
    fi
    echo "Result  : Enabled ${unit_name} (rclone mount ${remote}: → ${sync_dir})"
    return 0
}

echo ""
echo "Info    : Asserting rclone OneDrive mounts under $HOME..."

cleanup_abraunegg_leftovers
install_apt_package fuse3 || true
install_rclone || true

if command -v rclone >/dev/null 2>&1 || $CHECK; then
    for account_entry in "${ONEDRIVE_ACCOUNTS[@]}"; do
        ensure_account "$account_entry" || true
    done
else
    fail_step "rclone:missing" "rclone command not found; cannot configure accounts"
fi

if $CHECK; then
    echo "Result  : assert_onedrive check complete"
else
    if [[ $FAILED_COUNT -eq 0 ]]; then
        echo "Result  : assert_onedrive: OneDrive accounts asserted via rclone"
    else
        echo "Error   : assert_onedrive: failed steps count: $FAILED_COUNT"
        [[ ${#FAILED_STEPS[@]} -gt 0 ]] && echo "Error   : assert_onedrive: failed steps: ${FAILED_STEPS[*]}"
        exit 1
    fi
fi

echo "Result  : assert_onedrive finished successfully"
exit 0
