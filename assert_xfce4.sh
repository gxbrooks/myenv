#!/bin/bash
#
# assert_xfce4.sh — Assert XFCE4 desktop environment with myenv configuration
#
# Installs XFCE4/LightDM and related packages, links dotfiles from this repo,
# installs KVM helpers. Idempotent. Invoked by assert_myenv.sh or run standalone.
#
# Usage: assert_xfce4.sh [--Debug|-d] [--Check|-c] [--restart-lightdm|-r] [--no-restart-lightdm]
#
#   --Check  Dry-run: report packages and changes that would be made (no apt, no sudo writes).
#
#   After a successful live run, should-dos 1–3 (packages + LightDM/XFCE session defaults,
#   repo symlinks and helpers, apply session) finish with a LightDM restart when appropriate.
#   On an interactive TTY you are prompted: [R]estart LightDM or [S]kip (default R on Enter).
#   Use --no-restart-lightdm to skip without prompting; use --restart-lightdm to restart
#   without prompting when non-interactive (e.g. SSH/cron). Restart is never performed in --Check mode.
#
# Requires: sudo privileges for live (non-check) runs

DEBUG=false
CHECK=false
RESTART_LIGHTDM_EXPLICIT=false
RESTART_LIGHTDM=false
script_name="$(basename "${BASH_SOURCE[0]}")"

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
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." >&2
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--restart-lightdm|-r] [--no-restart-lightdm]" >&2
            exit 1
            ;;
    esac
    shift
done

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

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

REFRESH_SCRIPT_SOURCE="$PROJECT_DIR/refresh_display_kvm.sh"
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
# 8. Run wake_on_kvm.sh for KVM switch support
#############################################
echo "🔧 Setting up KVM switch persistence..."
echo ""

WAKE_SCRIPT="$PROJECT_DIR/wake_on_kvm.sh"

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
    echo "Summary (dry-run): would ensure XFCE4/LightDM packages, session defaults, repo symlinks, KVM helpers."
    if [[ "$NEEDS_REBOOT" == "true" ]]; then
        echo "Check   : After a live run, LightDM restart would apply the new display manager and session."
    fi
    echo "Check   : Live run would offer [R]estart / [S]kip LightDM on a TTY (unless --no-restart-lightdm)."
    echo "Result  : assert_xfce4 check complete"
    exit 0
fi

echo "✅ assert_xfce4.sh complete!"
echo ""
echo "Should-dos 1–3 (this run):"
echo "  1. Packages, LightDM default, XFCE session defaults"
echo "  2. Repo symlinks (~/.xprofile, autostart, .xscreensaver) and /usr/local/bin helpers"
echo "  3. KVM persistence (wake_on_kvm.sh when sudo granted)"
echo ""
echo "Summary of changes:"
echo "  • XFCE4, LightDM, xdotool, and xscreensaver packages installed"
echo "  • LightDM set as default display manager"
echo "  • XFCE4 set as default session (system-wide and user-specific)"
echo "  • ~/.xprofile → $PROJECT_DIR/.xprofile"
echo "  • ~/.config/autostart → $PROJECT_DIR/autostart"
echo "  • xfconf displays/Notify → 0 (no Display dialog on monitor reconnect)"
echo "  • ~/.xscreensaver → $PROJECT_DIR/.xscreensaver"
echo "  • refresh_display_kvm.sh installed to /usr/local/bin"
echo "  • KVM switch persistence configured (wake_on_kvm.sh)"
echo ""

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
