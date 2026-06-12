#!/bin/bash
#
# assert_xfce4.sh — Assert XFCE4 desktop environment with myenv configuration
#
# WHAT IT DOES / WHEN TO RUN
#   Installs XFCE4/LightDM and related packages, sets them as the defaults, links the
#   repo dotfiles (~/.xprofile, autostart, kitty.conf, .xscreensaver), places the Kitty
#   panel launcher, installs the KVM helpers, and delegates all AMD iGPU freeze mitigation
#   to assert/assert_amdgpu.sh. Idempotent. Lives in assert/; invoked by assert_myenv.sh
#   (or install_myenv.sh) or run standalone. The repo root is the parent of assert/.
#
# USAGE
#   assert_xfce4.sh [--Debug|-d] [--Check|-c] [--restart-lightdm|-r] [--no-restart-lightdm]
#                   [--skip-firmware-update] [--amdgpu-dc-off | --amdgpu-dc-on]
#                   [--suppress-volman-noise] [--help|-h]
#
# FLAGS
#   --Check, -c            Dry-run: report packages and changes that would be made
#                          (no apt, no sudo writes). Forwarded to assert/assert_amdgpu.sh.
#   --Debug, -d            Verbose logging (forwarded to child scripts).
#   --restart-lightdm, -r  Restart LightDM after a live run without prompting (SSH/cron).
#   --no-restart-lightdm   Skip the LightDM restart without prompting.
#                          (Default: prompt [R]estart/[S]kip on a TTY; skip when non-interactive.
#                           Never restarts in --Check mode or when a full reboot is pending.)
#   --skip-firmware-update Forwarded to assert_amdgpu.sh: do not upgrade linux-firmware.
#   --amdgpu-dc-off        Forwarded to assert_amdgpu.sh: opt-in last-resort kernel
#                          workaround (amdgpu.dc=0). See that script's --help for the warning.
#   --amdgpu-dc-on         Forwarded to assert_amdgpu.sh: revert --amdgpu-dc-off.
#   --suppress-volman-noise  Disable thunar-volman automount so the KVM switch stops spamming
#                          "Unsupported USB device type" into ~/.xsession-errors. (Benign
#                          noise; disables USB-drive auto-mounting for this user.)
#   --help, -h             Show this help and exit.
#
#   AMD iGPU freeze (Lab3 Raphael iGPU "dm_irq_work_func hogged CPU" bug that stalls the
#   xfwm4 compositor; mouse/keyboard appear dead but SSH stays alive) is handled by
#   assert/assert_amdgpu.sh, which this script runs once the XFCE session is configured.
#
# Requires: sudo privileges for live (non-check) runs

DEBUG=false
CHECK=false
RESTART_LIGHTDM_EXPLICIT=false
RESTART_LIGHTDM=false
SKIP_FIRMWARE_UPDATE=false
AMDGPU_DC_OFF=false
AMDGPU_DC_ON=false
SUPPRESS_VOLMAN_NOISE=false
script_name="$(basename "${BASH_SOURCE[0]}")"

show_help() {
    sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^#\s\{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d) DEBUG=true ;;
        --Check|-c) CHECK=true ;;
        --restart-lightdm|-r)
            RESTART_LIGHTDM=true
            RESTART_LIGHTDM_EXPLICIT=true
            ;;
        --no-restart-lightdm)
            RESTART_LIGHTDM=false
            RESTART_LIGHTDM_EXPLICIT=true
            ;;
        --skip-firmware-update) SKIP_FIRMWARE_UPDATE=true ;;
        --amdgpu-dc-off) AMDGPU_DC_OFF=true ;;
        --amdgpu-dc-on) AMDGPU_DC_ON=true ;;
        --suppress-volman-noise) SUPPRESS_VOLMAN_NOISE=true ;;
        --help|-h) show_help; exit 0 ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." >&2
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--restart-lightdm|-r] [--no-restart-lightdm] [--skip-firmware-update] [--amdgpu-dc-off|--amdgpu-dc-on] [--suppress-volman-noise] [--help|-h]" >&2
            exit 1
            ;;
    esac
    shift
done

if $AMDGPU_DC_OFF && $AMDGPU_DC_ON; then
    echo "Error   : --amdgpu-dc-off and --amdgpu-dc-on are mutually exclusive." >&2
    exit 1
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# assert_xfce4.sh lives in <repo>/assert/, so the project root is the parent directory.
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AMDGPU_SCRIPT="$PROJECT_DIR/assert/assert_amdgpu.sh"

MYENV_KITTY_DESKTOP_NAME="myenv-kitty.desktop"
MYENV_KITTY_DESKTOP_SOURCE="$PROJECT_DIR/xfce/$MYENV_KITTY_DESKTOP_NAME"

# Pick the main horizontal bar: bottom-ish position (various Xfce p= values) with full width,
# else the widest panel by /length (typically 100 for the primary bar).
myenv_xfce_pick_target_panel() {
    local prop pnum pos p len
    local candidate_bottom="" candidate_wide="" wide_max=-1
    while IFS= read -r prop; do
        [[ "$prop" =~ /panels/panel-([0-9]+)/position ]] || continue
        pnum="${BASH_REMATCH[1]}"
        pos=$(xfconf-query -c xfce4-panel -p "$prop" -v 2>/dev/null || true)
        [[ "$pos" =~ ^p=([0-9]+) ]] || continue
        p="${BASH_REMATCH[1]}"
        len=$(xfconf-query -c xfce4-panel -p "/panels/panel-$pnum/length" -v 2>/dev/null || echo 0)
        case "$p" in
            8|10|11|12)
                if [[ "$len" -eq 100 ]]; then
                    candidate_bottom="$pnum"
                fi
                ;;
        esac
        if [[ "$len" -gt "$wide_max" ]]; then
            wide_max=$len
            candidate_wide="$pnum"
        fi
    done < <(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -E '^/panels/panel-[0-9]+/position$' || true)

    if [[ -n "$candidate_bottom" ]]; then
        echo "$candidate_bottom"
    elif [[ -n "$candidate_wide" ]]; then
        echo "$candidate_wide"
    else
        echo "1"
    fi
}

myenv_xfce_max_plugin_id() {
    xfconf-query -c xfce4-panel -l 2>/dev/null \
        | grep -oE '/plugins/plugin-[0-9]+/' \
        | sed 's|/plugins/plugin-||;s|/||' \
        | sort -n \
        | uniq \
        | tail -1
}

myenv_xfce_read_panel_plugin_ids() {
    local panel_id=$1
    xfconf-query -c xfce4-panel -p "/panels/panel-$panel_id/plugin-ids" -v 2>/dev/null | grep -E '^[0-9]+$' || true
}

# Insert after the first expanding separator (Xfce’s usual flex spacer), else at the middle index.
myenv_xfce_kitty_insert_index() {
    local ids=("$@")
    local i pid ptype expand
    for i in "${!ids[@]}"; do
        pid="${ids[$i]}"
        ptype=$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$pid" -v 2>/dev/null || true)
        if [[ "$ptype" == "separator" ]]; then
            expand=$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$pid/expand" -v 2>/dev/null || true)
            if [[ "$expand" == "true" ]]; then
                echo $((i + 1))
                return 0
            fi
        fi
    done
    echo $((${#ids[@]} / 2))
}

myenv_xfce_find_myenv_kitty_plugin() {
    local pid ptype line item
    while IFS= read -r line; do
        [[ "$line" =~ ^/plugins/plugin-([0-9]+)/items$ ]] || continue
        pid="${BASH_REMATCH[1]}"
        ptype=$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$pid" -v 2>/dev/null || true)
        [[ "$ptype" == "launcher" ]] || continue
        while IFS= read -r item; do
            if [[ "$item" == "$MYENV_KITTY_DESKTOP_NAME" ]]; then
                echo "$pid"
                return 0
            fi
        done < <(xfconf-query -c xfce4-panel -p "/plugins/plugin-$pid/items" -v 2>/dev/null | grep -E '^[[:alnum:]_-]+\.desktop$' || true)
    done < <(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -E '^/plugins/plugin-[0-9]+/items$' || true)
    return 1
}

myenv_xfce_plugin_on_panel() {
    local panel_id=$1
    local want=$2
    local pid
    while IFS= read -r pid; do
        [[ "$pid" == "$want" ]] && return 0
    done < <(myenv_xfce_read_panel_plugin_ids "$panel_id")
    return 1
}

myenv_xfce_sync_kitty_launcher_file() {
    local plugin_id=$1
    local dir="$HOME/.config/xfce4/panel/launcher-$plugin_id"
    mkdir -p "$dir"
    if [[ -f "$dir/$MYENV_KITTY_DESKTOP_NAME" ]] && cmp -s "$MYENV_KITTY_DESKTOP_SOURCE" "$dir/$MYENV_KITTY_DESKTOP_NAME"; then
        return 0
    fi
    cp -f "$MYENV_KITTY_DESKTOP_SOURCE" "$dir/$MYENV_KITTY_DESKTOP_NAME"
}

if $CHECK; then
    INTERACTIVE=false
elif [ -t 0 ] && [ "${NONINTERACTIVE:-}" != "1" ]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# Default: restart LightDM after live run when interactive; skip when non-interactive unless --restart-lightdm.
if $CHECK; then
    RESTART_LIGHTDM=false
elif ! $RESTART_LIGHTDM_EXPLICIT; then
    RESTART_LIGHTDM=$INTERACTIVE
fi

NEEDS_REBOOT=false
NEEDS_FULL_REBOOT=false

$DEBUG && echo "Debug   : Starting: $script_name (CHECK=$CHECK)"

echo "========== $(date): Running assert_xfce4.sh =========="
echo "Project directory: $PROJECT_DIR"
if $CHECK; then
    echo "Running in check mode (dry-run, no system changes)"
elif [ "$INTERACTIVE" = "false" ]; then
    echo "Running in non-interactive mode (no TTY or NONINTERACTIVE=1)"
fi

#############################################
# 1. Install packages if not already installed
#############################################
echo "🔍 Checking for required packages..."

packages=("xfce4" "lightdm" "xdotool" "xscreensaver" "xscreensaver-data" "xscreensaver-gl")
packages_to_install=()

for package in "${packages[@]}"; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
        echo "✓ $package is already installed"
        $DEBUG && echo "Debug   : package ok: $package"
    else
        echo "→ $package needs to be installed"
        packages_to_install+=("$package")
    fi
done
if [ ${#packages_to_install[@]} -gt 0 ]; then
    if $CHECK; then
        echo "Check   : Would run: sudo apt update && sudo apt install -y ${packages_to_install[*]}"
    else
        echo "→ Installing packages: ${packages_to_install[*]}"
        sudo apt update
        sudo apt install -y "${packages_to_install[@]}"
        echo "✓ Package installation complete"
    fi
else
    echo "✓ All required packages are already installed"
fi

# AMD iGPU freeze mitigations (linux-firmware, xfwm4 compositor, amdgpu.dc kernel
# parameter) are handled by assert/assert_amdgpu.sh, invoked near the end of this script
# once the XFCE session is configured.

#############################################
# 2. Set LightDM as default display manager
#############################################
echo "🔧 Configuring LightDM as default display manager..."

CURRENT_DM=$(cat /etc/X11/default-display-manager 2>/dev/null || echo "none")

if [[ "$CURRENT_DM" == *"lightdm"* ]]; then
    echo "✓ LightDM is already the default display manager"
else
    echo "→ Current display manager: $CURRENT_DM"
    if $CHECK; then
        echo "Check   : Would switch default display manager to LightDM (dpkg-reconfigure or tee + systemctl)"
        NEEDS_REBOOT=true
    else
        echo "→ Switching to LightDM (requires sudo)"

        if sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure lightdm 2>/dev/null; then
            echo "✓ LightDM set as default display manager"
        else
            echo "→ Using alternative method to set LightDM"
            echo "/usr/sbin/lightdm" | sudo tee /etc/X11/default-display-manager > /dev/null
            sudo systemctl disable gdm3 2>/dev/null || true
            sudo systemctl disable gdm 2>/dev/null || true
            sudo systemctl enable lightdm
            echo "✓ LightDM configured as default"
        fi
        echo ""
        echo "⚠️  Default display manager changed to LightDM; a LightDM restart at the end of this script applies it (or use --no-restart-lightdm)."
        NEEDS_REBOOT=true
    fi
fi

#############################################
# 3. Set XFCE4 as default session
#############################################
echo "🔧 Configuring XFCE4 as default session..."

LIGHTDM_CONF="/etc/lightdm/lightdm.conf.d/50-myenv-default-session.conf"

if [ -f "$LIGHTDM_CONF" ] && grep -q "user-session=xfce" "$LIGHTDM_CONF" 2>/dev/null; then
    echo "✓ XFCE4 is already the system-wide default session"
else
    if $CHECK; then
        echo "Check   : Would write $LIGHTDM_CONF with user-session=xfce"
    else
        echo "→ Setting XFCE4 as system-wide default session (requires sudo)"
        sudo mkdir -p /etc/lightdm/lightdm.conf.d
        sudo tee "$LIGHTDM_CONF" > /dev/null <<EOF
[Seat:*]
# Set XFCE4 as the default session
user-session=xfce
EOF
        echo "✓ XFCE4 set as system-wide default session"
    fi
fi

DMRC_FILE="$HOME/.dmrc"
if [ -f "$DMRC_FILE" ] && grep -q "Session=xfce" "$DMRC_FILE" 2>/dev/null; then
    echo "✓ XFCE4 is already your default session"
else
    if $CHECK; then
        echo "Check   : Would write $DMRC_FILE with Session=xfce"
    else
        echo "→ Setting XFCE4 as your default session"
        cat > "$DMRC_FILE" <<EOF
[Desktop]
Session=xfce
EOF
        chmod 644 "$DMRC_FILE"
        echo "✓ XFCE4 set as your default session"
    fi
fi

#############################################
# 4. Link ~/.xprofile to repository .xprofile
#############################################
echo "🔗 Setting up ~/.xprofile link..."

XPROFILE_SOURCE="$PROJECT_DIR/.xprofile"
XPROFILE_TARGET="$HOME/.xprofile"

if [ -L "$XPROFILE_TARGET" ] && [ "$(readlink "$XPROFILE_TARGET")" = "$XPROFILE_SOURCE" ]; then
    echo "✓ ~/.xprofile already linked to repository .xprofile"
elif [ -e "$XPROFILE_TARGET" ]; then
    if $CHECK; then
        echo "Check   : Would remove $XPROFILE_TARGET and: ln -s $XPROFILE_SOURCE $XPROFILE_TARGET"
    else
        echo "→ Removing existing ~/.xprofile and creating link"
        rm -rf "$XPROFILE_TARGET"
        ln -s "$XPROFILE_SOURCE" "$XPROFILE_TARGET"
        echo "✓ ~/.xprofile linked to repository .xprofile"
    fi
else
    if $CHECK; then
        echo "Check   : Would create: ln -s $XPROFILE_SOURCE $XPROFILE_TARGET"
    else
        echo "→ Creating ~/.xprofile link"
        ln -s "$XPROFILE_SOURCE" "$XPROFILE_TARGET"
        echo "✓ ~/.xprofile linked to repository .xprofile"
    fi
fi

#############################################
# 5. Link ~/.config/autostart to repository autostart directory
#############################################
echo "🔗 Setting up ~/.config/autostart link..."

AUTOSTART_SOURCE="$PROJECT_DIR/autostart"
AUTOSTART_TARGET="$HOME/.config/autostart"

mkdir -p "$HOME/.config"

if [ -L "$AUTOSTART_TARGET" ] && [ "$(readlink "$AUTOSTART_TARGET")" = "$AUTOSTART_SOURCE" ]; then
    echo "✓ ~/.config/autostart already linked to repository autostart directory"
elif [ -e "$AUTOSTART_TARGET" ]; then
    if $CHECK; then
        echo "Check   : Would remove $AUTOSTART_TARGET and: ln -s $AUTOSTART_SOURCE $AUTOSTART_TARGET"
    else
        echo "→ Removing existing ~/.config/autostart and creating link"
        rm -rf "$AUTOSTART_TARGET"
        ln -s "$AUTOSTART_SOURCE" "$AUTOSTART_TARGET"
        echo "✓ ~/.config/autostart linked to repository autostart directory"
    fi
else
    if $CHECK; then
        echo "Check   : Would create: ln -s $AUTOSTART_SOURCE $AUTOSTART_TARGET"
    else
        echo "→ Creating ~/.config/autostart link"
        ln -s "$AUTOSTART_SOURCE" "$AUTOSTART_TARGET"
        echo "✓ ~/.config/autostart linked to repository autostart directory"
    fi
fi

#############################################
# 5a. Link ~/.config/kitty/kitty.conf to repository kitty/kitty.conf
#############################################
echo "🔗 Setting up Kitty config link..."

KITTY_CONF_SOURCE="$PROJECT_DIR/kitty/kitty.conf"
KITTY_CONF_DIR="$HOME/.config/kitty"
KITTY_CONF_TARGET="$KITTY_CONF_DIR/kitty.conf"

if [ ! -f "$KITTY_CONF_SOURCE" ]; then
    echo "⚠️  $KITTY_CONF_SOURCE not found; skipping Kitty config link"
elif [ -d "$KITTY_CONF_TARGET" ]; then
    echo "⚠️  $KITTY_CONF_TARGET is a directory; not replacing; fix manually"
elif [ -L "$KITTY_CONF_TARGET" ] && [ "$(readlink "$KITTY_CONF_TARGET")" = "$KITTY_CONF_SOURCE" ]; then
    echo "✓ ~/.config/kitty/kitty.conf already linked to repository kitty/kitty.conf"
elif [ -e "$KITTY_CONF_TARGET" ]; then
    if $CHECK; then
        echo "Check   : Would mv $KITTY_CONF_TARGET to ${KITTY_CONF_TARGET}.bak and: ln -s $KITTY_CONF_SOURCE $KITTY_CONF_TARGET"
    else
        echo "→ Backing up existing kitty.conf to kitty.conf.bak"
        mv "$KITTY_CONF_TARGET" "${KITTY_CONF_TARGET}.bak"
        mkdir -p "$KITTY_CONF_DIR"
        ln -s "$KITTY_CONF_SOURCE" "$KITTY_CONF_TARGET"
        echo "✓ ~/.config/kitty/kitty.conf linked to repository kitty/kitty.conf"
    fi
else
    if $CHECK; then
        echo "Check   : Would mkdir -p $KITTY_CONF_DIR && ln -s $KITTY_CONF_SOURCE $KITTY_CONF_TARGET"
    else
        echo "→ Creating ~/.config/kitty and kitty.conf link"
        mkdir -p "$KITTY_CONF_DIR"
        ln -s "$KITTY_CONF_SOURCE" "$KITTY_CONF_TARGET"
        echo "✓ ~/.config/kitty/kitty.conf linked to repository kitty/kitty.conf"
    fi
fi

#############################################
# 5b. Xfce: do not open Display settings on monitor hotplug / resume
#############################################
# Xfce stores "Configure new displays when connected" as channel displays, key /Notify (1=on).
# After DPMS-off or KVM reconnect, Notify=1 can raise xfce4-display-settings unprompted.
echo "🔧 Xfce display notifications (suppress hotplug Display dialog)..."
if command -v xfconf-query >/dev/null 2>&1; then
    if $CHECK; then
        if cur=$(xfconf-query -c displays -p /Notify -v 2>/dev/null); then
            if [[ "$cur" == "0" ]]; then
                echo "✓ displays/Notify is already 0"
            else
                echo "Check   : Would set displays/Notify to 0 (currently $cur)"
            fi
        else
            echo "Check   : Would set displays/Notify to 0 when the displays channel exists"
        fi
    else
        if xfconf-query -c displays -p /Notify -v >/dev/null 2>&1; then
            cur=$(xfconf-query -c displays -p /Notify -v)
            if [[ "$cur" != "0" ]]; then
                xfconf-query -c displays -p /Notify -s 0 -t int
                echo "✓ Set displays/Notify to 0 (no automatic Display dialog on reconnect)"
            else
                echo "✓ displays/Notify already 0"
            fi
        elif xfconf-query -c displays -lv >/dev/null 2>&1; then
            if xfconf-query -c displays -p /Notify -n -t int -s 0 --create -f 2>/dev/null; then
                echo "✓ Created displays/Notify=0"
            else
                echo "⚠️  Could not set displays/Notify (unexpected xfconf state)"
            fi
        else
            echo "⚠️  xfconf channel displays not found; skipped (log in to Xfce once, then re-run assert_xfce4)"
        fi
    fi
else
    echo "⚠️  xfconf-query not in PATH; skipped displays/Notify"
fi

#############################################
# 5c. Suppress thunar-volman KVM device noise (opt-in)
#############################################
# KVM switches present HID/audio/video composite devices that thunar-volman cannot
# handle, flooding ~/.xsession-errors with "Unsupported USB device type". Benign, but
# noisy on every KVM input switch. --suppress-volman-noise disables volman automount.
if $SUPPRESS_VOLMAN_NOISE; then
    echo "🔧 Suppressing thunar-volman KVM device noise..."
    if ! command -v xfconf-query >/dev/null 2>&1; then
        echo "⚠️  xfconf-query not in PATH; skipped thunar-volman noise suppression"
    elif $CHECK; then
        echo "Check   : Would set thunar-volman /automount-media/enabled and /automount-drives/enabled to false"
    else
        vm_changed=false
        for vm_key in /automount-media/enabled /automount-drives/enabled; do
            cur=$(xfconf-query -c thunar-volman -p "$vm_key" -v 2>/dev/null || echo "")
            if [[ "$cur" != "false" ]]; then
                xfconf-query -c thunar-volman -p "$vm_key" -s false -t bool --create 2>/dev/null \
                    && vm_changed=true
            fi
        done
        if $vm_changed; then
            echo "✓ thunar-volman automount disabled (KVM USB-device log spam suppressed)"
        else
            echo "✓ thunar-volman automount already disabled"
        fi
    fi
fi

#############################################
# 5d. Xfce panel: Kitty launcher on primary bar (after first expanding separator)
#############################################
echo "🔧 Xfce panel: Kitty launcher (bottom primary bar, centered via expand spacer)..."
if [[ ! -f "$MYENV_KITTY_DESKTOP_SOURCE" ]]; then
    echo "⚠️  $MYENV_KITTY_DESKTOP_SOURCE not found; skipping Kitty panel launcher"
elif ! command -v xfconf-query >/dev/null 2>&1; then
    echo "⚠️  xfconf-query not in PATH; skipped Kitty panel launcher"
elif ! xfconf-query -c xfce4-panel -l >/dev/null 2>&1; then
    echo "⚠️  No xfce4-panel xfconf channel (log in to Xfce once, then re-run assert_xfce4)"
else
    target_panel=$(myenv_xfce_pick_target_panel)
    existing_pid=$(myenv_xfce_find_myenv_kitty_plugin || true)

    if [[ -n "$existing_pid" ]] && myenv_xfce_plugin_on_panel "$target_panel" "$existing_pid"; then
        if $CHECK; then
            echo "✓ Kitty panel launcher already on primary panel $target_panel (plugin $existing_pid)"
        else
            myenv_xfce_sync_kitty_launcher_file "$existing_pid"
            echo "✓ Kitty panel launcher present on panel $target_panel (plugin $existing_pid); desktop file synced"
        fi
    elif [[ -n "$existing_pid" ]]; then
        if $CHECK; then
            echo "Check   : Kitty launcher exists on plugin $existing_pid (not on computed primary panel $target_panel); leaving layout unchanged"
        else
            myenv_xfce_sync_kitty_launcher_file "$existing_pid"
            echo "⚠️  Kitty launcher is on plugin $existing_pid (not primary panel $target_panel); not duplicating; desktop file synced"
        fi
    else
        mapfile -t panel_ids < <(myenv_xfce_read_panel_plugin_ids "$target_panel")
        if [[ ${#panel_ids[@]} -eq 0 ]]; then
            echo "⚠️  No plugins on panel-$target_panel; skipping Kitty launcher"
        else
            insert_idx=$(myenv_xfce_kitty_insert_index "${panel_ids[@]}")
            max_pid=$(myenv_xfce_max_plugin_id)
            [[ "$max_pid" =~ ^[0-9]+$ ]] || max_pid=0
            new_pid=$((max_pid + 1))
            if $CHECK; then
                echo "Check   : Would add launcher plugin $new_pid to panel-$target_panel at index $insert_idx (after first expand separator or mid-bar)"
                echo "Check   : Would create ~/.config/xfce4/panel/launcher-$new_pid/$MYENV_KITTY_DESKTOP_NAME and xfconf-query plugin + plugin-ids"
                if [[ -n "${DISPLAY:-}" ]]; then
                    echo "Check   : Would run: xfce4-panel -r (reload panel)"
                fi
            else
                mkdir -p "$HOME/.config/xfce4/panel/launcher-$new_pid"
                cp -f "$MYENV_KITTY_DESKTOP_SOURCE" "$HOME/.config/xfce4/panel/launcher-$new_pid/$MYENV_KITTY_DESKTOP_NAME"
                xfconf-query -c xfce4-panel -p "/plugins/plugin-$new_pid" -t string -s launcher --create
                xfconf-query -c xfce4-panel -p "/plugins/plugin-$new_pid/items" -t string -s "$MYENV_KITTY_DESKTOP_NAME" -a --create

                new_order=("${panel_ids[@]:0:insert_idx}" "$new_pid" "${panel_ids[@]:insert_idx}")
                xfconf-query -c xfce4-panel -p "/panels/panel-$target_panel/plugin-ids" -r 2>/dev/null || true
                qargs=()
                for id in "${new_order[@]}"; do
                    qargs+=(-t int -s "$id")
                done
                xfconf-query -c xfce4-panel -p "/panels/panel-$target_panel/plugin-ids" -n "${qargs[@]}" -a --create

                if [[ -n "${DISPLAY:-}" ]] && command -v xfce4-panel >/dev/null 2>&1; then
                    xfce4-panel -r 2>/dev/null || true
                fi
                echo "✓ Added Kitty launcher to panel $target_panel (plugin $new_pid, insert index $insert_idx)"
            fi
        fi
    fi
fi

#############################################
# 6. Link ~/.xscreensaver to repository .xscreensaver
#############################################
echo "🔗 Setting up ~/.xscreensaver link..."

XSCREENSAVER_SOURCE="$PROJECT_DIR/.xscreensaver"
XSCREENSAVER_TARGET="$HOME/.xscreensaver"

if [ -L "$XSCREENSAVER_TARGET" ] && [ "$(readlink "$XSCREENSAVER_TARGET")" = "$XSCREENSAVER_SOURCE" ]; then
    echo "✓ ~/.xscreensaver already linked to repository .xscreensaver"
elif [ -e "$XSCREENSAVER_TARGET" ]; then
    if $CHECK; then
        echo "Check   : Would mv $XSCREENSAVER_TARGET to ${XSCREENSAVER_TARGET}.bak and ln -s $XSCREENSAVER_SOURCE $XSCREENSAVER_TARGET"
    else
        echo "→ Backing up existing ~/.xscreensaver to ~/.xscreensaver.bak"
        mv "$XSCREENSAVER_TARGET" "${XSCREENSAVER_TARGET}.bak"
        ln -s "$XSCREENSAVER_SOURCE" "$XSCREENSAVER_TARGET"
        echo "✓ ~/.xscreensaver linked to repository .xscreensaver"
    fi
else
    if $CHECK; then
        echo "Check   : Would create: ln -s $XSCREENSAVER_SOURCE $XSCREENSAVER_TARGET"
    else
        echo "→ Creating ~/.xscreensaver link"
        ln -s "$XSCREENSAVER_SOURCE" "$XSCREENSAVER_TARGET"
        echo "✓ ~/.xscreensaver linked to repository .xscreensaver"
    fi
fi

#############################################
# 7. Install refresh_display_kvm.sh to /usr/local/bin
#############################################
echo "🔧 Installing refresh_display_kvm.sh to /usr/local/bin..."

REFRESH_SCRIPT_SOURCE="$PROJECT_DIR/diagnose/refresh_display_kvm.sh"
REFRESH_SCRIPT_TARGET="/usr/local/bin/refresh_display_kvm.sh"

if [ -f "$REFRESH_SCRIPT_SOURCE" ]; then
    if [ -f "$REFRESH_SCRIPT_TARGET" ]; then
        if ! cmp -s "$REFRESH_SCRIPT_SOURCE" "$REFRESH_SCRIPT_TARGET"; then
            if $CHECK; then
                echo "Check   : Would sudo cp $REFRESH_SCRIPT_SOURCE $REFRESH_SCRIPT_TARGET && chmod +x"
            else
                echo "→ Updating $REFRESH_SCRIPT_TARGET"
                sudo cp "$REFRESH_SCRIPT_SOURCE" "$REFRESH_SCRIPT_TARGET"
                sudo chmod +x "$REFRESH_SCRIPT_TARGET"
                echo "✓ refresh_display_kvm.sh updated in /usr/local/bin"
            fi
        else
            echo "✓ refresh_display_kvm.sh already installed and up-to-date"
        fi
    else
        if $CHECK; then
            echo "Check   : Would sudo install $REFRESH_SCRIPT_SOURCE to $REFRESH_SCRIPT_TARGET"
        else
            echo "→ Installing refresh_display_kvm.sh to /usr/local/bin"
            sudo cp "$REFRESH_SCRIPT_SOURCE" "$REFRESH_SCRIPT_TARGET"
            sudo chmod +x "$REFRESH_SCRIPT_TARGET"
            echo "✓ refresh_display_kvm.sh installed to /usr/local/bin"
        fi
    fi
else
    echo "⚠️  refresh_display_kvm.sh not found at $REFRESH_SCRIPT_SOURCE, skipping"
fi

echo ""

#############################################
# 7b. Install diagnose/ + assert/ helpers to /usr/local/bin
#############################################
echo "🔧 Installing diagnose/ and assert/ helpers to /usr/local/bin..."
declare -A HELPER_SRC=(
    [recover_xfce_freeze.sh]="$PROJECT_DIR/diagnose/recover_xfce_freeze.sh"
    [escalate_xfce_freeze.sh]="$PROJECT_DIR/diagnose/escalate_xfce_freeze.sh"
    [assert_amdgpu.sh]="$PROJECT_DIR/assert/assert_amdgpu.sh"
)
for helper in recover_xfce_freeze.sh escalate_xfce_freeze.sh assert_amdgpu.sh; do
    helper_src="${HELPER_SRC[$helper]}"
    helper_dst="/usr/local/bin/$helper"
    if [ ! -f "$helper_src" ]; then
        echo "⚠️  $helper not found at $helper_src, skipping"
        continue
    fi
    if [ -f "$helper_dst" ] && cmp -s "$helper_src" "$helper_dst"; then
        echo "✓ $helper already installed and up-to-date"
    elif $CHECK; then
        echo "Check   : Would sudo install $helper_src to $helper_dst (chmod +x)"
    else
        echo "→ Installing $helper to /usr/local/bin"
        sudo cp "$helper_src" "$helper_dst"
        sudo chmod +x "$helper_dst"
        echo "✓ $helper installed to /usr/local/bin"
    fi
done

echo ""

#############################################
# 7c. AMD iGPU freeze mitigation (delegated to assert/assert_amdgpu.sh)
#############################################
echo "🔧 AMD iGPU freeze mitigation (assert/assert_amdgpu.sh)..."
if [ ! -f "$AMDGPU_SCRIPT" ]; then
    echo "⚠️  $AMDGPU_SCRIPT not found; skipping AMD GPU mitigation"
else
    amdgpu_args=()
    $DEBUG && amdgpu_args+=(--Debug)
    $CHECK && amdgpu_args+=(--Check)
    $SKIP_FIRMWARE_UPDATE && amdgpu_args+=(--skip-firmware-update)
    $AMDGPU_DC_OFF && amdgpu_args+=(--amdgpu-dc-off)
    $AMDGPU_DC_ON && amdgpu_args+=(--amdgpu-dc-on)
    amdgpu_rc=0
    bash "$AMDGPU_SCRIPT" "${amdgpu_args[@]}" || amdgpu_rc=$?
    if [[ $amdgpu_rc -eq 10 ]]; then
        NEEDS_FULL_REBOOT=true
    elif [[ $amdgpu_rc -ne 0 ]]; then
        echo "⚠️  assert_amdgpu.sh exited $amdgpu_rc (see output above)"
    fi
fi

echo ""

#############################################
# 8. Run wake_on_kvm.sh for KVM switch support
#############################################
echo "🔧 Setting up KVM switch persistence..."
echo ""

WAKE_SCRIPT="$PROJECT_DIR/diagnose/wake_on_kvm.sh"

if [ -f "$WAKE_SCRIPT" ]; then
    if $CHECK; then
        echo "Check   : Would run: sudo bash $WAKE_SCRIPT"
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  🔐 Sudo access required for system configuration"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "The following operations require sudo privileges:"
        echo "  • Write to /var/log/wake_on_kvm.log"
        echo "  • Configure Xorg display settings"
        echo "  • Enable USB device wake support"
        echo "  • Mask systemd sleep targets"
        echo ""
        echo -n "Requesting sudo access... "

        if sudo -v; then
            echo "✓ Granted"
            echo ""
            sudo bash "$WAKE_SCRIPT"
            echo ""
            echo "✓ KVM switch persistence configured"
        else
            echo "✗ Denied"
            echo ""
            echo "⚠️  Sudo access denied. KVM switch configuration skipped."
            echo "    You can run this manually later with: sudo bash $WAKE_SCRIPT"
        fi
    fi
else
    echo "⚠️  wake_on_kvm.sh not found at $WAKE_SCRIPT, skipping"
fi

echo ""

#############################################
# 9. Completion
#############################################
echo ""
if $CHECK; then
    echo "✅ assert_xfce4 check complete (no changes applied)"
    echo ""
    echo "Summary (dry-run): would ensure XFCE4/LightDM packages, session defaults, repo symlinks, Kitty config, Kitty panel launcher, AMD GPU freeze mitigations (via assert/assert_amdgpu.sh), diagnose/ helpers, KVM persistence."
    if [[ "$NEEDS_REBOOT" == "true" ]]; then
        echo "Check   : After a live run, LightDM restart would apply the new display manager and session."
    fi
    if [[ "$NEEDS_FULL_REBOOT" == "true" ]]; then
        echo "Check   : ⚠️  A live run would change firmware and/or kernel parameters — a full REBOOT (not just LightDM) would be required."
    fi
    echo "Check   : Live run would offer [R]estart / [S]kip LightDM on a TTY (unless --no-restart-lightdm)."
    echo "Result  : assert_xfce4 check complete"
    exit 0
fi

echo "✅ assert_xfce4.sh complete!"
echo ""
echo "Should-dos 1–3 (this run):"
echo "  1. Packages, LightDM default, XFCE session defaults"
echo "  2. Repo symlinks (~/.xprofile, autostart, kitty.conf, .xscreensaver), Xfce Kitty panel launcher, /usr/local/bin helpers"
echo "  3. KVM persistence (wake_on_kvm.sh when sudo granted)"
echo ""
echo "Summary of changes:"
echo "  • XFCE4, LightDM, xdotool, and xscreensaver packages installed"
echo "  • LightDM set as default display manager"
echo "  • XFCE4 set as default session (system-wide and user-specific)"
echo "  • ~/.xprofile → $PROJECT_DIR/.xprofile"
echo "  • ~/.config/autostart → $PROJECT_DIR/autostart"
echo "  • ~/.config/kitty/kitty.conf → $PROJECT_DIR/kitty/kitty.conf (scrollback 50k lines)"
echo "  • Xfce: Kitty launcher on primary panel (myenv-kitty.desktop, after expand separator)"
echo "  • xfconf displays/Notify → 0 (no Display dialog on monitor reconnect)"
echo "  • AMD iGPU freeze mitigations applied via assert/assert_amdgpu.sh (firmware, xfwm4 xpresent, optional amdgpu.dc)"
$SUPPRESS_VOLMAN_NOISE && echo "  • thunar-volman automount disabled (KVM USB log-spam suppressed)"
echo "  • recover_xfce_freeze.sh + escalate_xfce_freeze.sh + assert_amdgpu.sh installed to /usr/local/bin"
echo "  • ~/.xscreensaver → $PROJECT_DIR/.xscreensaver"
echo "  • refresh_display_kvm.sh installed to /usr/local/bin"
echo "  • KVM switch persistence configured (wake_on_kvm.sh)"
echo ""

if [[ "$NEEDS_FULL_REBOOT" == "true" ]]; then
    # A full reboot supersedes (and applies) any pending LightDM/session change.
    RESTART_LIGHTDM=false
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ⚠️  FULL REBOOT REQUIRED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  GPU firmware and/or kernel parameters changed. A LightDM restart is NOT"
    echo "  enough — reboot to load the new firmware/kernel command line:"
    echo "      sudo reboot"
    echo "  After reboot, verify the freeze bug is gone (single command):"
    echo "      assert_amdgpu.sh --Check     # or: /usr/local/bin/assert_amdgpu.sh --Check"
    echo ""
    echo "Result  : assert_xfce4 finished (reboot required)"
    exit 0
fi

if $RESTART_LIGHTDM && [ "$INTERACTIVE" = "true" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Apply X session: LightDM"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    if [[ "$NEEDS_REBOOT" == "true" ]]; then
        echo "  Display manager and/or session defaults changed; restarting LightDM applies them."
    else
        echo "  Restarting LightDM reloads ~/.xprofile, xscreensaver, and session dotfiles."
    fi
    echo ""
    echo "  ⚠️  Restart ends this graphical session immediately (black screen). Save work first."
    echo ""
    echo "  [R] Restart LightDM now"
    echo "  [S] Skip — keep this session; apply later with: sudo systemctl restart lightdm"
    echo ""
    while true; do
        echo -n "  Your choice [R/s]: "
        read -r lightdm_choice
        lightdm_choice=$(echo "$lightdm_choice" | tr '[:upper:]' '[:lower:]')
        case "$lightdm_choice" in
            ""|r|restart|y|yes)
                break
                ;;
            s|skip|n|no)
                RESTART_LIGHTDM=false
                echo "  ✓ Skipping LightDM restart (your choice)."
                break
                ;;
            *)
                echo "  ✗ Enter R to restart, S to skip, or press Enter for restart."
                ;;
        esac
    done
    echo ""
fi

if $RESTART_LIGHTDM; then
    echo "  → sudo systemctl restart lightdm"
    sudo systemctl restart lightdm
    echo "Result  : assert_xfce4 finished (LightDM restart requested)"
    exit 0
fi

echo "Skipped LightDM restart (your choice, --no-restart-lightdm, or non-interactive default)."
echo "  To apply ~/.xprofile and session config: sudo systemctl restart lightdm"
echo "  Or re-run: $PROJECT_DIR/assert_xfce4.sh"
echo ""
echo "Result  : assert_xfce4 finished successfully"
exit 0
