#!/bin/bash
#
# setup_xfce4.sh — Setup XFCE4 desktop environment with myenv configuration
#
# Features:
#   • Installs XFCE4, LightDM, and xdotool if not already installed
#   • Links ~/.xprofile to repository .xprofile
#   • Links ~/.config/autostart to repository autostart directory
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

packages=("xfce4" "lightdm" "xdotool")
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
# 4. Add sourcing of project .bashrc to user's .bashrc
#############################################
echo "🔗 Setting up .bashrc sourcing..."

USER_BASHRC="$HOME/.bashrc"
PROJECT_BASHRC="$PROJECT_DIR/.bashrc"
BASHRC_SOURCE_LINE="source \"$PROJECT_BASHRC\""

# Check if the source line already exists
if [ -f "$USER_BASHRC" ] && grep -qF "$BASHRC_SOURCE_LINE" "$USER_BASHRC"; then
    echo "✓ Project .bashrc already sourced in user's .bashrc"
else
    echo "→ Adding project .bashrc sourcing to user's .bashrc"
    echo "" >> "$USER_BASHRC"
    echo "# Source myenv project .bashrc" >> "$USER_BASHRC"
    echo "$BASHRC_SOURCE_LINE" >> "$USER_BASHRC"
    echo "✓ Project .bashrc sourcing added to user's .bashrc"
fi

#############################################
# 5. Completion
#############################################
echo "✅ setup_xfce4.sh complete!"
echo ""
echo "Summary of changes:"
echo "  • XFCE4, LightDM, and xdotool packages installed/verified"
echo "  • ~/.xprofile linked to repository .xprofile"
echo "  • ~/.config/autostart linked to repository autostart directory"
echo "  • User's .bashrc updated to source project .bashrc"
echo ""
echo "Next steps:"
echo "  • Log out and log back in to activate XFCE4 desktop"
echo "  • Run wake_on_kvm.sh if using KVM switches"
echo "  • Restart or run 'source ~/.bashrc' to activate new bash configuration"



