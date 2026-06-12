#!/bin/bash
#
# escalate_xfce_freeze.sh — Escalate XFCE freeze recovery when recover_xfce_freeze.sh --force failed
#
# Run over SSH from another lab host when the KVM UI is still dead after --force:
#   ssh gxbrooks@lab3.lan "bash /tmp/escalate_xfce_freeze.sh"
#
# Does NOT reboot the machine. May restart LightDM (brief login-screen blackout; other
# services keep running). Requires sudo for LightDM restart.
#
# USAGE
#   escalate_xfce_freeze.sh [--skip-lightdm] [--display :N] [--help|-h]
#
set -uo pipefail

SKIP_LIGHTDM=false
TARGET_DISPLAY=":0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECOVER="$SCRIPT_DIR/recover_xfce_freeze.sh"
[[ -x /usr/local/bin/recover_xfce_freeze.sh ]] && RECOVER=/usr/local/bin/recover_xfce_freeze.sh

show_help() {
    sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^#\s\{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-lightdm) SKIP_LIGHTDM=true ;;
        --display)
            shift
            TARGET_DISPLAY="${1:-:0}"
            ;;
        -h|--help) show_help; exit 0 ;;
        *)
            echo "Usage: $(basename "$0") [--skip-lightdm] [--display :N] [--help|-h]" >&2
            exit 1
            ;;
    esac
    shift
done

hr() { echo "──────────────────────────────────────────────────"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  XFCE freeze escalation — $(hostname) $(date '+%H:%M:%S')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

hr; echo "1. Snapshot (CPU / session)"
uptime
echo ""
ps aux --sort=-%cpu | head -12
echo ""
echo "xfwm4:       $(pgrep -a xfwm4 2>/dev/null || echo '<none>')"
echo "xfce4-sess:  $(pgrep -a xfce4-session 2>/dev/null | head -1 || echo '<none>')"
echo "xscreensaver:$(pgrep -a xscreensaver 2>/dev/null | head -1 || echo '<none>')"
echo "glmatrix:    $(pgrep -a glmatrix 2>/dev/null || echo '<none>')"
echo "Xorg:        $(pgrep -a Xorg 2>/dev/null | head -1 || echo '<none>')"
if command -v journalctl >/dev/null 2>&1; then
    hog="$(journalctl -k -b 0 2>/dev/null | grep -c 'dm_irq_work_func.*hogged' || true)"
    echo "IRQ hog events this boot: ${hog:-0}"
fi

hr; echo "2. Is the X server responding?"
export DISPLAY="$TARGET_DISPLAY"
xset_ok=false
if timeout 3 xset q >/dev/null 2>&1; then
    xset_ok=true
    echo "  ✓ xset responds (X server alive)"
else
    echo "  ✗ xset timed out or failed — X server likely wedged"
fi

hr; echo "3. Kill input grabs (xscreensaver / GL hacks)"
export DISPLAY="$TARGET_DISPLAY"
pid="$(pgrep -u "$USER" -x xfwm4 2>/dev/null | head -1 || true)"
if [[ -n "$pid" && -r "/proc/$pid/environ" ]]; then
    while IFS= read -r line; do
        case "$line" in
            XAUTHORITY=*) export XAUTHORITY="${line#XAUTHORITY=}" ;;
            DBUS_SESSION_BUS_ADDRESS=*) export DBUS_SESSION_BUS_ADDRESS="${line#DBUS_SESSION_BUS_ADDRESS=}" ;;
        esac
    done < <(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null)
fi
command -v xscreensaver-command >/dev/null 2>&1 && xscreensaver-command -deactivate 2>/dev/null || true
pkill -u "$USER" -x xscreensaver 2>/dev/null || true
pkill -u "$USER" -x glmatrix 2>/dev/null || true
echo "  ✓ xscreensaver/glmatrix stopped (if they were running)"

hr; echo "4. Ensure active VT is the graphical seat (tty7)"
if command -v loginctl >/dev/null 2>&1; then
    loginctl list-sessions --no-legend 2>/dev/null | head -5 || true
fi
if [[ -w /dev/tty0 ]] || [[ "$(id -u)" -eq 0 ]]; then
    if command -v chvt >/dev/null 2>&1; then
        (sudo chvt 7 2>/dev/null || chvt 7 2>/dev/null) && echo "  ✓ switched to VT7" \
            || echo "  ⚠️  could not chvt 7 (need sudo or video group)"
    fi
else
    echo "  • skipped chvt (no permission; try: sudo chvt 7 on console)"
fi

hr; echo "5. Re-run compositor recovery (--force)"
if [[ -x "$RECOVER" ]]; then
    bash "$RECOVER" --force --display "$TARGET_DISPLAY" || true
else
    echo "  ⚠️  recover_xfce_freeze.sh not found at $RECOVER"
fi

hr; echo "6. Post-recovery X probe"
if timeout 3 xset q >/dev/null 2>&1; then
    echo "  ✓ xset responds after recovery"
    timeout 2 xset dpms force on 2>/dev/null || true
else
    echo "  ✗ xset still not responding"
fi

if $SKIP_LIGHTDM; then
    hr; echo "7. LightDM restart skipped (--skip-lightdm)"
    echo "If KVM is still frozen, run: sudo systemctl restart lightdm"
    exit 1
fi

hr; echo "7. Restart LightDM (no full reboot — other services stay up)"
echo "  → This restarts Xorg + login session; ~5–10s blackout at KVM."
if sudo -n systemctl restart lightdm 2>/dev/null; then
    echo "  ✓ LightDM restarted"
    sleep 6
    if timeout 3 xset -display "$TARGET_DISPLAY" q >/dev/null 2>&1; then
        echo "  ✓ X server responding after LightDM restart"
    else
        echo "  ⚠️  X not responding yet — wait 10s, switch KVM to this host, press a key"
    fi
    echo ""
    echo "Done. Switch KVM to $(hostname), wait a few seconds, login screen should appear."
    exit 0
fi

echo "  ✗ sudo required for LightDM restart. Run interactively:"
echo "      ssh -t gxbrooks@$(hostname) 'sudo systemctl restart lightdm'"
exit 10
