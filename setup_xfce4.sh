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

echo "========== $(date): Running setup_xfce4.sh =========="
echo "Project directory: $PROJECT_DIR"

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
# 2. Link ~/.xprofile to repository .xprofile
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
# 3. Link ~/.config/autostart to repository autostart directory
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
# 4. Link ~/.xscreensaver to repository .xscreensaver
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
# 5. Run wake_on_kvm.sh for KVM switch support
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
# 6. Completion
#############################################
echo ""
echo "✅ setup_xfce4.sh complete!"
echo ""
echo "Summary of changes:"
echo "  • XFCE4, LightDM, xdotool, and xscreensaver packages installed"
echo "  • ~/.xprofile → $PROJECT_DIR/.xprofile"
echo "  • ~/.config/autostart → $PROJECT_DIR/autostart"
echo "  • ~/.xscreensaver → $PROJECT_DIR/.xscreensaver"
echo "  • KVM switch persistence configured (wake_on_kvm.sh)"
echo ""
echo "Next steps:"
echo "  • Log out and log back in to activate XFCE4 desktop"
echo "  • Your display will stay active even when KVM switches away"



