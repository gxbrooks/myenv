#!/bin/bash
#
# wake_on_kvm.sh — Keep Ubuntu mini-PC displays & USB awake under KVM switches
#
# Features:
#   • Timed screen saver + DPMS (see ~/.xscreensaver; ~/.xprofile only disables X built-in saver)
#   • Keeps HDMI output active even if disconnected by KVM
#   • Enables USB keyboard/mouse wake persistently
#   • Blocks system auto-sleep via systemd-inhibit
#   • Idempotent: safe to run repeatedly
#   • Logs all actions to /var/log/wake_on_kvm.log
#
# WHAT IT DOES / WHEN TO RUN
#   System-level KVM persistence: blocks auto-sleep, enables USB wake, optional Xorg monitor
#   config, installs the minimal refresh_display.sh helper. Invoked by assert_xfce4.sh
#   during setup (requires sudo). Idempotent.
#
# USAGE: wake_on_kvm.sh [--help|-h]
#
# Requires: sudo privileges

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^#\s\{0,1\}//'
    exit 0
fi

LOGFILE="/var/log/wake_on_kvm.log"
mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1
echo "========== $(date): Running wake_on_kvm.sh =========="

# Prefer the invoking user's home when running under sudo.
TARGET_USER="${SUDO_USER:-$USER}"
if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
    TARGET_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    TARGET_HOME="$HOME"
fi
if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    TARGET_HOME="$HOME"
fi

#############################################
# 1. Prevent auto-sleep via systemd-inhibit
#############################################
if pgrep -x "systemd-inhibit" > /dev/null; then
    echo "✓ systemd-inhibit already running"
else
    echo "→ Starting systemd-inhibit to block sleep"
    sudo systemd-inhibit --what="sleep:idle" \
        --why="Prevent auto-sleep but allow manual suspend" \
        --mode="block" \
        sleep infinity &
fi


#############################################
# 2. Remove legacy "never blank" xset lines from ~/.xprofile
#############################################
# Older myenv appended `xset s off -dpms s noblank`, which blocked DPMS all night.
XPROFILE="$TARGET_HOME/.xprofile"
if [ -f "$XPROFILE" ]; then
    if grep -qF 'xset s off -dpms s noblank' "$XPROFILE" 2>/dev/null; then
        echo "→ Removing legacy DPMS-disable line from $XPROFILE"
        sed -i '/^xset s off -dpms s noblank$/d' "$XPROFILE"
    fi
    if grep -qF '# Disable screen blanking and DPMS' "$XPROFILE" 2>/dev/null; then
        sed -i '/^# Disable screen blanking and DPMS$/d' "$XPROFILE"
    fi
    echo "✓ $XPROFILE checked for legacy DPMS-disable lines"
else
    echo "⚠️  $XPROFILE not found (assert_xfce4 links it from the repo)"
fi


#############################################
# 3. Force HDMI output to stay active
#############################################
XORG_CONF_DIR="/usr/share/X11/xorg.conf.d"
MONITOR_CONF="$XORG_CONF_DIR/10-monitor.conf"
if [[ -z "${DISPLAY:-}" ]] || ! command -v xrandr >/dev/null 2>&1; then
    echo "⚠️  DISPLAY/xrandr unavailable (likely SSH or headless); skipping HDMI probe/config"
else
    HDMI_OUT="$(xrandr 2>/dev/null | awk '/ connected/{print $1; exit}' || true)"

    if [ -z "$HDMI_OUT" ]; then
        echo "⚠️  No active HDMI output detected via xrandr, skipping HDMI config"
    else
        echo "Detected HDMI output: $HDMI_OUT"
        if [ -f "$MONITOR_CONF" ] && grep -q "$HDMI_OUT" "$MONITOR_CONF"; then
            echo "✓ HDMI config already present in $MONITOR_CONF"
        else
            echo "→ Writing persistent HDMI configuration to $MONITOR_CONF"
            sudo mkdir -p "$XORG_CONF_DIR"
            sudo tee "$MONITOR_CONF" > /dev/null <<EOF
Section "Monitor"
    Identifier "$HDMI_OUT"
    Option "DPMS" "true"
EndSection

Section "Device"
    Identifier "Intel Graphics"
    Driver "modesetting"
    Option "HotPlug" "false"
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Option "AutoAddGPU" "false"
EndSection
EOF
        fi
    fi
fi

# Older installs wrote Option "DPMS" "false" here; that blocked monitor power-off forever.
if [ -f "$MONITOR_CONF" ] && grep -q 'Option "DPMS" "false"' "$MONITOR_CONF" 2>/dev/null; then
    echo "→ Updating $MONITOR_CONF: enable DPMS for timed monitor blank"
    sudo sed -i 's/Option "DPMS" "false"/Option "DPMS" "true"/' "$MONITOR_CONF"
fi


#############################################
# 4. Enable USB wake for all devices
#############################################
echo "🔍 Enabling USB wakeup support for all capable devices..."

for f in /sys/bus/usb/devices/*/power/wakeup; do
  if [ -f "$f" ]; then
    current=$(cat "$f")
    if [ "$current" != "enabled" ] && [ "$current" != "on" ]; then
      echo "→ Enabling wake on: $f"
      echo enabled | sudo tee "$f" > /dev/null
    fi
  fi
done
echo "✓ USB wake enabled for all applicable devices"

# Persistent udev rule
UDEV_RULE='/etc/udev/rules.d/90-usb-wakeup.rules'
UDEV_CONTENT='# Enable USB device wake support
ACTION=="add", SUBSYSTEM=="usb", TEST=="power/wakeup", ATTR{power/wakeup}="enabled"'

if [ -f "$UDEV_RULE" ] && grep -q "power/wakeup" "$UDEV_RULE"; then
    echo "✓ Persistent udev rule already exists at $UDEV_RULE"
else
    echo "→ Creating persistent udev rule at $UDEV_RULE"
    echo "$UDEV_CONTENT" | sudo tee "$UDEV_RULE" > /dev/null
    sudo udevadm control --reload
    echo "✓ Udev rule installed and reloaded"
fi


#############################################
# 5. Disable system sleep targets (persistent)
#############################################
mask_targets=(sleep.target suspend.target hibernate.target hybrid-sleep.target)

for target in "${mask_targets[@]}"; do
    if systemctl is-enabled "$target" 2>/dev/null | grep -q masked; then
        echo "✓ $target already masked"
    else
        echo "→ Masking $target"
        sudo systemctl mask "$target"
    fi
done


#############################################
# 6. Optional: ensure xrandr auto-refresh command exists
#############################################
XRANDR_SCRIPT="/usr/local/bin/refresh_display.sh"
REFRESH_SOURCE="$SCRIPT_DIR/refresh_display.sh"
if [ -f "$XRANDR_SCRIPT" ] && [ -f "$REFRESH_SOURCE" ] && cmp -s "$REFRESH_SOURCE" "$XRANDR_SCRIPT"; then
    echo "✓ $XRANDR_SCRIPT already installed and up-to-date"
elif [ ! -f "$REFRESH_SOURCE" ]; then
    echo "⚠️  $REFRESH_SOURCE not found; skipping refresh_display.sh install"
elif [ -f "$XRANDR_SCRIPT" ] && ! cmp -s "$REFRESH_SOURCE" "$XRANDR_SCRIPT"; then
    echo "→ Updating $XRANDR_SCRIPT from repo"
    sudo cp "$REFRESH_SOURCE" "$XRANDR_SCRIPT"
    sudo chmod +x "$XRANDR_SCRIPT"
else
    echo "→ Installing refresh_display.sh to $XRANDR_SCRIPT"
    sudo cp "$REFRESH_SOURCE" "$XRANDR_SCRIPT"
    sudo chmod +x "$XRANDR_SCRIPT"
fi


#############################################
# 7. Completion
#############################################
echo "✅ wake_on_kvm.sh complete. HDMI/USB wake persistence and systemd sleep inhibit applied."
echo "Log written to: $LOGFILE"
