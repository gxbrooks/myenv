#!/bin/bash
#
# setup_xfce4.sh — Setup XFCE4 desktop environment with myenv configuration
#
# Features:
#   • Installs XFCE4, LightDM, and xdotool if not already installed
#   • Links ~/.xprofile to repository .xprofile
#   • Links ~/.config/autostart to repository autostart directory
#   • Links ~/.xscreensaver to repository .xscreensaver
#   • Adds sourcing of project .bashrc to user's .bashrc
#   • Idempotent: safe to run repeatedly
#
# Requires: sudo privileges for package installation

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Check if running interactively (has TTY)
# Allow override via NONINTERACTIVE=1 environment variable
if [ -t 0 ] && [ "${NONINTERACTIVE:-}" != "1" ]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# Initialize variables
NEEDS_REBOOT=false

echo "========== $(date): Running setup_xfce4.sh =========="
echo "Project directory: $PROJECT_DIR"
if [ "$INTERACTIVE" = "false" ]; then
    echo "Running in non-interactive mode (SSH detected)"
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
    else
        echo "→ $package needs to be installed"
        packages_to_install+=("$package")
    fi
done
if [ ${#packages_to_install[@]} -gt 0 ]; then
    echo "→ Installing packages: ${packages_to_install[*]}"
    sudo apt update
    sudo apt install -y "${packages_to_install[@]}"
    echo "✓ Package installation complete"
else
    echo "✓ All required packages are already installed"
fi

#############################################
# 2. Set LightDM as default display manager
#############################################
echo "🔧 Configuring LightDM as default display manager..."

# Check current display manager
CURRENT_DM=$(cat /etc/X11/default-display-manager 2>/dev/null || echo "none")

if [[ "$CURRENT_DM" == *"lightdm"* ]]; then
    echo "✓ LightDM is already the default display manager"
else
    echo "→ Current display manager: $CURRENT_DM"
    echo "→ Switching to LightDM (requires sudo)"
    
    # Use DEBIAN_FRONTEND to avoid interactive prompts
    if sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure lightdm 2>/dev/null; then
        echo "✓ LightDM set as default display manager"
    else
        # Fallback: manually set it
        echo "→ Using alternative method to set LightDM"
        echo "/usr/sbin/lightdm" | sudo tee /etc/X11/default-display-manager > /dev/null
        sudo systemctl disable gdm3 2>/dev/null || true
        sudo systemctl disable gdm 2>/dev/null || true
        sudo systemctl enable lightdm
        echo "✓ LightDM configured as default"
    fi
    echo ""
    echo "⚠️  Display manager changed! Choose one option:"
    echo ""
    echo "   Option 1: Reboot (Recommended)"
    echo "     sudo reboot"
    echo "     → Graceful shutdown (time to save work)"
    echo "     → Clean system restart"
    echo ""
    echo "   Option 2: Restart display manager (Faster)"
    echo "     sudo systemctl restart lightdm"
    echo "     → Session ends INSTANTLY (screen goes black immediately)"
    echo "     → Save your work NOW before running this!"
    echo ""
    NEEDS_REBOOT=true
fi

#############################################
# 3. Set XFCE4 as default session
#############################################
echo "🔧 Configuring XFCE4 as default session..."

# Set system-wide default session
LIGHTDM_CONF="/etc/lightdm/lightdm.conf.d/50-myenv-default-session.conf"

if [ -f "$LIGHTDM_CONF" ] && grep -q "user-session=xfce" "$LIGHTDM_CONF" 2>/dev/null; then
    echo "✓ XFCE4 is already the system-wide default session"
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

# Set user-specific default session
DMRC_FILE="$HOME/.dmrc"
if [ -f "$DMRC_FILE" ] && grep -q "Session=xfce" "$DMRC_FILE" 2>/dev/null; then
    echo "✓ XFCE4 is already your default session"
else
    echo "→ Setting XFCE4 as your default session"
    cat > "$DMRC_FILE" <<EOF
[Desktop]
Session=xfce
EOF
    chmod 644 "$DMRC_FILE"
    echo "✓ XFCE4 set as your default session"
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
    echo "→ Removing existing ~/.xprofile and creating link"
    rm -rf "$XPROFILE_TARGET"
    ln -s "$XPROFILE_SOURCE" "$XPROFILE_TARGET"
    echo "✓ ~/.xprofile linked to repository .xprofile"
else
    echo "→ Creating ~/.xprofile link"
    ln -s "$XPROFILE_SOURCE" "$XPROFILE_TARGET"
    echo "✓ ~/.xprofile linked to repository .xprofile"
fi

#############################################
# 5. Link ~/.config/autostart to repository autostart directory
#############################################
echo "🔗 Setting up ~/.config/autostart link..."

AUTOSTART_SOURCE="$PROJECT_DIR/autostart"
AUTOSTART_TARGET="$HOME/.config/autostart"

# Ensure .config directory exists
mkdir -p "$HOME/.config"

if [ -L "$AUTOSTART_TARGET" ] && [ "$(readlink "$AUTOSTART_TARGET")" = "$AUTOSTART_SOURCE" ]; then
    echo "✓ ~/.config/autostart already linked to repository autostart directory"
elif [ -e "$AUTOSTART_TARGET" ]; then
    echo "→ Removing existing ~/.config/autostart and creating link"
    rm -rf "$AUTOSTART_TARGET"
    ln -s "$AUTOSTART_SOURCE" "$AUTOSTART_TARGET"
    echo "✓ ~/.config/autostart linked to repository autostart directory"
else
    echo "→ Creating ~/.config/autostart link"
    ln -s "$AUTOSTART_SOURCE" "$AUTOSTART_TARGET"
    echo "✓ ~/.config/autostart linked to repository autostart directory"
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
    echo "→ Backing up existing ~/.xscreensaver to ~/.xscreensaver.bak"
    mv "$XSCREENSAVER_TARGET" "${XSCREENSAVER_TARGET}.bak"
    ln -s "$XSCREENSAVER_SOURCE" "$XSCREENSAVER_TARGET"
    echo "✓ ~/.xscreensaver linked to repository .xscreensaver"
else
    echo "→ Creating ~/.xscreensaver link"
    ln -s "$XSCREENSAVER_SOURCE" "$XSCREENSAVER_TARGET"
    echo "✓ ~/.xscreensaver linked to repository .xscreensaver"
fi

#############################################
# 7. Install refresh_display_kvm.sh to /usr/local/bin
#############################################
echo "🔧 Installing refresh_display_kvm.sh to /usr/local/bin..."

REFRESH_SCRIPT_SOURCE="$PROJECT_DIR/refresh_display_kvm.sh"
REFRESH_SCRIPT_TARGET="/usr/local/bin/refresh_display_kvm.sh"

if [ -f "$REFRESH_SCRIPT_SOURCE" ]; then
    if [ -f "$REFRESH_SCRIPT_TARGET" ]; then
        # Compare files to see if update is needed
        if ! cmp -s "$REFRESH_SCRIPT_SOURCE" "$REFRESH_SCRIPT_TARGET"; then
            echo "→ Updating $REFRESH_SCRIPT_TARGET"
            sudo cp "$REFRESH_SCRIPT_SOURCE" "$REFRESH_SCRIPT_TARGET"
            sudo chmod +x "$REFRESH_SCRIPT_TARGET"
            echo "✓ refresh_display_kvm.sh updated in /usr/local/bin"
        else
            echo "✓ refresh_display_kvm.sh already installed and up-to-date"
        fi
    else
        echo "→ Installing refresh_display_kvm.sh to /usr/local/bin"
        sudo cp "$REFRESH_SCRIPT_SOURCE" "$REFRESH_SCRIPT_TARGET"
        sudo chmod +x "$REFRESH_SCRIPT_TARGET"
        echo "✓ refresh_display_kvm.sh installed to /usr/local/bin"
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
    
    # Request sudo upfront with a clear context
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
else
    echo "⚠️  wake_on_kvm.sh not found at $WAKE_SCRIPT, skipping"
fi

echo ""

#############################################
# 9. Completion
#############################################
echo ""
echo "✅ setup_xfce4.sh complete!"
echo ""
echo "Summary of changes:"
echo "  • XFCE4, LightDM, xdotool, and xscreensaver packages installed"
echo "  • LightDM set as default display manager"
echo "  • XFCE4 set as default session (system-wide and user-specific)"
echo "  • ~/.xprofile → $PROJECT_DIR/.xprofile"
echo "  • ~/.config/autostart → $PROJECT_DIR/autostart"
echo "  • ~/.xscreensaver → $PROJECT_DIR/.xscreensaver"
echo "  • refresh_display_kvm.sh installed to /usr/local/bin"
echo "  • KVM switch persistence configured (wake_on_kvm.sh)"
echo ""
echo "Next steps:"
if [[ "$NEEDS_REBOOT" == "true" ]]; then
    echo ""
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ⚠️  DISPLAY MANAGER CHANGED - Action Required"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  ⚠️  Both options will end your current session!"
    echo "  ⚠️  Save your work before proceeding!"
    echo ""
    echo "  Choose ONE of the following:"
    echo ""
    echo "  Option A: Reboot (Recommended)"
    echo "    sudo reboot"
    echo ""
    echo "    Why choose this:"
    echo "      ✓ Graceful shutdown - time to save and close apps"
    echo "      ✓ Clean system state after restart"
    echo "      ✓ Predictable - no surprises"
    echo ""
    echo "  Option B: Restart Display Manager (Faster)"
    echo "    sudo systemctl restart lightdm"
    echo ""
    echo "    Why choose this:"
    echo "      ✓ Faster - takes ~5-10 seconds vs 1-2 minutes"
    echo "      ✗ INSTANT blackout - no graceful shutdown"
    echo "      ✗ This terminal window will vanish mid-command"
    echo "      ✗ More jarring experience"
    echo ""
    echo "  Option S: Skip (Do it manually later)"
    echo ""
    echo "  After either option:"
    echo "    • LightDM login screen will appear"
    echo "    • XFCE4 will be automatically selected"
    echo "    • Your display will stay active with KVM switches"
    echo ""
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [ "$INTERACTIVE" = "true" ]; then
        # Interactive prompt (only when running with TTY)
        while true; do
            echo -n "  Please choose [A/B/S]: "
            read -r choice
            choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')
            
            case "$choice" in
                A)
                    echo ""
                    echo "  ✓ Option A selected: Reboot"
                    echo ""
                    echo "  ⚠️  Last chance to save your work!"
                    echo -n "  Press Enter to reboot now, or Ctrl+C to cancel: "
                    read -r
                    echo ""
                    echo "  Rebooting system..."
                    sudo reboot
                    break
                    ;;
                B)
                    echo ""
                    echo "  ✓ Option B selected: Restart Display Manager"
                    echo ""
                    echo "  ⚠️  Last chance to save your work!"
                    echo "  ⚠️  Screen will go BLACK immediately when you press Enter!"
                    echo -n "  Press Enter to restart display manager now, or Ctrl+C to cancel: "
                    read -r
                    echo ""
                    echo "  Restarting display manager..."
                    sudo systemctl restart lightdm
                    break
                    ;;
                S)
                    echo ""
                    echo "  ✓ Skipping automatic restart"
                    echo ""
                    echo "  To switch to LightDM later, run ONE of these commands:"
                    echo "    sudo reboot"
                    echo "    sudo systemctl restart lightdm"
                    echo ""
                    break
                    ;;
                *)
                    echo "  ✗ Invalid choice. Please enter A, B, or S."
                    ;;
            esac
        done
    else
        # Non-interactive mode (SSH): just print instructions
        echo "  ⚠️  Running in non-interactive mode (SSH detected)"
        echo "  ⚠️  Skipping automatic restart prompt"
        echo ""
        echo "  To complete the setup, run ONE of these commands:"
        echo "    sudo reboot"
        echo "    sudo systemctl restart lightdm"
        echo ""
        echo "  Or run this script again locally (with a display) to get interactive prompts."
    fi
else
    echo "  • Log out and log back in to activate XFCE4 desktop"
    echo "  • Your display will stay active even when KVM switches away"
    echo "  • XFCE4 will be selected automatically at login"
fi



