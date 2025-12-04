#!/bin/bash
#
# refresh_display_kvm.sh — Force display refresh after KVM switch
#
# This script can be run via SSH even when no user is logged in.
# It refreshes the display at the X server level (LightDM/Xorg).
#
# Usage:
#   ssh Lab1 "sudo /path/to/refresh_display_kvm.sh [--restart-lightdm]"
#   Or run locally: sudo ./refresh_display_kvm.sh [--restart-lightdm]
#
# Options:
#   --restart-lightdm    Restart LightDM service (more aggressive fix)
#
# Requires: sudo privileges

set -uo pipefail
# Don't exit on error (-e) so we can handle timeouts gracefully

RESTART_LIGHTDM=false
if [[ "${1:-}" == "--restart-lightdm" ]]; then
    RESTART_LIGHTDM=true
fi

# Find the active X display (usually :0)
X_DISPLAY=":0"
X_AUTH="/var/run/lightdm/root/:0"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  KVM Display Refresh Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  IMPORTANT: Make sure your KVM switch is set to this machine!"
echo "   If you just switched the KVM, wait 2-3 seconds for it to stabilize."
echo ""
if [ -t 0 ]; then
    # Only prompt if running interactively (not via SSH)
    echo -n "Press Enter to continue (or Ctrl+C to cancel)... "
    read -r
fi
echo ""
echo "🔍 Diagnosing display issue..."

# Check if Xorg is running
if ! pgrep -x Xorg > /dev/null; then
    echo "⚠️  Xorg is not running."
    echo "→ Attempting to start display manager..."
    systemctl start lightdm 2>/dev/null || true
    sleep 2
    if pgrep -x Xorg > /dev/null; then
        echo "✓ Xorg started successfully"
    else
        echo "✗ Failed to start Xorg. Check logs: journalctl -u lightdm"
        exit 1
    fi
fi

# Check LightDM status
if systemctl is-active --quiet lightdm; then
    echo "✓ LightDM is running"
else
    echo "⚠️  LightDM is not active"
    if [ "$RESTART_LIGHTDM" = "true" ]; then
        echo "→ Restarting LightDM..."
        systemctl restart lightdm
        sleep 3
    fi
fi

# Check Xorg logs for display-related errors
echo "🔍 Checking Xorg logs for errors..."
RECENT_ERRORS=$(journalctl -u lightdm --since "5 minutes ago" 2>/dev/null | grep -i "error\|failed\|no screens" | tail -3 || true)
if [ -n "$RECENT_ERRORS" ]; then
    echo "⚠️  Recent Xorg/LightDM errors:"
    echo "$RECENT_ERRORS" | sed 's/^/   /'
fi

# Check Xorg log file directly for "no screens" errors (common when booting headless)
XORG_LOG="/var/log/Xorg.0.log"
if [ -f "$XORG_LOG" ]; then
    NO_SCREENS=$(grep -i "no screens\|no devices detected\|unable to find any" "$XORG_LOG" 2>/dev/null | tail -2 || true)
    NO_DEVICE=$(grep -i "no device specified for screen" "$XORG_LOG" 2>/dev/null | tail -1 || true)
    
    if [ -n "$NO_SCREENS" ]; then
        echo "⚠️  Xorg log shows display detection issues:"
        echo "$NO_SCREENS" | sed 's/^/   /'
        echo "   → This often happens when the system booted headless (no display connected)"
    fi
    
    if [ -n "$NO_DEVICE" ]; then
        echo "⚠️  CRITICAL: Xorg initialized Screen0 without a device:"
        echo "$NO_DEVICE" | sed 's/^/   /'
        echo "   → This means Xorg started headless and cannot detect displays now"
        echo "   → REBOOT REQUIRED: System must boot with KVM switched to this machine"
        REBOOT_NEEDED=true
    else
        REBOOT_NEEDED=false
    fi
fi

echo ""
echo "Refreshing display on $X_DISPLAY..."

# Check if X socket exists (indicates Xorg is fully initialized)
if [ ! -S "/tmp/.X11-unix/X0" ]; then
    echo "⚠️  WARNING: X socket /tmp/.X11-unix/X0 does not exist"
    echo "   → Xorg may not be fully initialized"
    echo "   → This often happens when Xorg started headless"
    REBOOT_NEEDED=true
fi

# Method 1: Use xrandr to re-detect and enable displays
# This works even when no user is logged in
export DISPLAY="$X_DISPLAY"
export XAUTHORITY="$X_AUTH"

# Get the connected output name with timeout to prevent hanging
OUTPUT=""
if OUTPUT_RAW=$(timeout 3 xrandr 2>/dev/null); then
    OUTPUT=$(echo "$OUTPUT_RAW" | awk '/ connected/{print $1; exit}')
    echo "xrandr detected outputs:"
    echo "$OUTPUT_RAW" | head -15 | sed 's/^/   /'
    
    # Also check for disconnected outputs (they might be the display we need)
    DISCONNECTED=$(echo "$OUTPUT_RAW" | awk '/disconnected/{print $1; exit}' || true)
    if [ -n "$DISCONNECTED" ] && [ -z "$OUTPUT" ]; then
        echo "   → Found disconnected output: $DISCONNECTED (may be the display we need)"
    fi
fi

if [ -z "$OUTPUT" ]; then
    echo "⚠️  No connected display detected via xrandr"
    
    # Check if xrandr is hanging (common when Xorg has no device for Screen0)
    if ! timeout 1 xset -q >/dev/null 2>&1; then
        echo "⚠️  CRITICAL: X server is not responding (xset/xrandr hang)"
        echo "   → This indicates Xorg is in a bad state (likely started headless)"
        echo "   → REBOOT REQUIRED: System must boot with KVM switched to this machine"
        REBOOT_NEEDED=true
    fi
    
    # Try to force hotplug detection by writing to sysfs (if available)
    if [ -d /sys/class/drm ] && [ "$REBOOT_NEEDED" != "true" ]; then
        echo "→ Attempting to trigger display hotplug detection..."
        for card in /sys/class/drm/card*/status; do
            if [ -f "$card" ]; then
                # Try to trigger a status change to force re-detection
                echo "detect" > "$card" 2>/dev/null || true
            fi
        done
        sleep 1
    fi
    
    echo "→ Trying xrandr --auto..."
    timeout 3 xrandr --auto 2>/dev/null || echo "⚠️  xrandr --auto failed or timed out"
    
    # Try to detect again after --auto
    sleep 2
    if OUTPUT_RAW=$(timeout 3 xrandr 2>/dev/null); then
        OUTPUT=$(echo "$OUTPUT_RAW" | awk '/ connected/{print $1; exit}')
        if [ -n "$OUTPUT" ]; then
            echo "✓ Display detected after --auto: $OUTPUT"
        else
            # Show all outputs (connected and disconnected) for debugging
            echo "   All xrandr outputs:"
            echo "$OUTPUT_RAW" | grep -E "^[A-Z]" | sed 's/^/      /'
        fi
    fi
    
    # If still no display, check hardware and try to enable connected outputs
    if [ -z "$OUTPUT" ]; then
        echo "→ Checking hardware display connections..."
        if command -v dmesg >/dev/null 2>&1; then
            DISPLAY_HW=$(dmesg | grep -i "drm\|display\|vga\|hdmi" | tail -5 || true)
            if [ -n "$DISPLAY_HW" ]; then
                echo "   Recent display hardware messages:"
                echo "$DISPLAY_HW" | sed 's/^/   /'
            fi
        fi
        
        # Check DRM devices and try to enable connected ones
        if [ -d /sys/class/drm ]; then
            echo "   DRM devices:"
            CONNECTED_DRM=""
            for dev in /sys/class/drm/card*-*; do
                if [ -d "$dev" ] && [ "$(basename "$dev")" != "card0-Writeback-1" ]; then
                    STATUS=$(cat "$dev/status" 2>/dev/null || echo "unknown")
                    DEV_NAME=$(basename "$dev")
                    echo "      $DEV_NAME: $STATUS"
                    
                    # Extract the output name (e.g., HDMI-A-1 from card0-HDMI-A-1)
                    if [ "$STATUS" = "connected" ]; then
                        OUTPUT_NAME=$(echo "$DEV_NAME" | sed 's/^card[0-9]*-//')
                        CONNECTED_DRM="$OUTPUT_NAME"
                    fi
                fi
            done
            
            # If we found a connected DRM device but xrandr doesn't see it, try to enable it
            if [ -n "$CONNECTED_DRM" ]; then
                echo ""
                echo "→ Found connected hardware output: $CONNECTED_DRM"
                echo "   → Attempting to enable it via xrandr..."
                
                # First, check if xrandr knows about this output at all (even if disconnected)
                if OUTPUT_RAW=$(timeout 3 xrandr 2>/dev/null); then
                    if echo "$OUTPUT_RAW" | grep -q "^$CONNECTED_DRM"; then
                        echo "   → xrandr knows about $CONNECTED_DRM, trying to enable it..."
                        # Try to set a mode (this will fail if no modes available, but might trigger detection)
                        timeout 3 xrandr --output "$CONNECTED_DRM" --auto 2>/dev/null || {
                            # If --auto fails, try to get available modes and set one
                            MODES=$(timeout 3 xrandr 2>/dev/null | grep -A 10 "^$CONNECTED_DRM" | grep -E "^\s+[0-9]+x[0-9]+" | head -1 | awk '{print $1}' || true)
                            if [ -n "$MODES" ]; then
                                echo "   → Trying to set mode $MODES on $CONNECTED_DRM..."
                                timeout 3 xrandr --output "$CONNECTED_DRM" --mode "$MODES" 2>/dev/null || true
                            else
                                echo "   → No modes available for $CONNECTED_DRM"
                            fi
                        }
                        
                        # Check again if it's now connected
                        sleep 1
                        if OUTPUT_RAW=$(timeout 3 xrandr 2>/dev/null); then
                            if echo "$OUTPUT_RAW" | grep "^$CONNECTED_DRM" | grep -q " connected"; then
                                OUTPUT="$CONNECTED_DRM"
                                echo "   ✓ Successfully enabled $CONNECTED_DRM!"
                            fi
                        fi
                    else
                        echo "   ⚠️  xrandr doesn't know about $CONNECTED_DRM"
                        echo "   → This means Xorg hasn't initialized this output as a screen"
                        echo "   → A full Xorg restart (via LightDM) may be needed"
                    fi
                fi
            fi
        fi
    fi
else
    echo "✓ Detected output: $OUTPUT"
    # Force the display to reinitialize with timeout
    timeout 3 xrandr --output "$OUTPUT" --auto 2>/dev/null || echo "⚠️  Failed to refresh $OUTPUT (may have timed out)"
fi

# Method 2: Disable DPMS and wake the display (with timeouts)
echo "→ Disabling DPMS and screen blanking..."
timeout 2 xset -dpms 2>/dev/null || true
timeout 2 xset s off 2>/dev/null || true
timeout 2 xset s noblank 2>/dev/null || true

# Method 3: Send a wake signal (if supported)
timeout 2 xset dpms force on 2>/dev/null || true

# Method 4: If requested, restart LightDM (most aggressive)
# This is especially important if the system booted headless
if [ "$RESTART_LIGHTDM" = "true" ]; then
    echo ""
    echo "🔄 Restarting LightDM (this will cause a brief blackout)..."
    echo "   → This forces Xorg to re-detect displays with the KVM connected"
    systemctl restart lightdm
    sleep 5  # Give it more time to fully initialize
    echo "✓ LightDM restarted"
    
    # Try to detect display again after restart
    sleep 2
    if OUTPUT_RAW=$(timeout 3 xrandr 2>/dev/null); then
        OUTPUT=$(echo "$OUTPUT_RAW" | awk '/ connected/{print $1; exit}')
        if [ -n "$OUTPUT" ]; then
            echo "✓ Display detected after LightDM restart: $OUTPUT"
        fi
    fi
fi

echo ""
echo "✅ Display refresh attempted."
echo ""

# Check if reboot is needed
if [ "${REBOOT_NEEDED:-false}" = "true" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ⚠️  REBOOT REQUIRED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Xorg started without a display device and cannot recover."
    echo ""
    echo "To fix:"
    echo "  1. Switch your KVM to Lab1 NOW"
    echo "  2. Wait 2-3 seconds for KVM to stabilize"
    echo "  3. Reboot Lab1: sudo reboot"
    echo ""
    echo "After reboot with KVM connected, Xorg will detect the display"
    echo "and the login screen should appear automatically."
    echo ""
elif [ -z "$OUTPUT" ]; then
    echo "⚠️  Display still not detected. Try:"
    echo "   1. Run with --restart-lightdm: sudo $0 --restart-lightdm"
    echo "   2. Check KVM switch is properly connected"
    echo "   3. Check display cable connections"
    echo "   4. Try restarting LightDM manually: sudo systemctl restart lightdm"
    echo "   5. Check Xorg logs: journalctl -u lightdm -n 50"
    echo "   6. If Xorg log shows 'No device specified for screen', REBOOT is required"
else
    echo "If display is still blank:"
    echo "   1. Wait 5-10 seconds after switching KVM"
    echo "   2. Press any key or move the mouse"
    echo "   3. The LightDM login screen should appear"
    echo "   4. If still blank, try: sudo $0 --restart-lightdm"
fi

