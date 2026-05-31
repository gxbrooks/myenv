#!/bin/bash
#
# recover_xfce_freeze.sh — Recover a frozen XFCE desktop without a reboot
#
# WHAT IT DOES / WHEN TO RUN
#   Run this when the XFCE desktop is frozen by the AMD Raphael iGPU "dm_irq_work_func
#   hogged CPU" bug: the mouse/keyboard appear dead at the KVM while SSH still works.
#   The xfwm4 compositor has stalled on the broken amdgpu DRI3/vblank path; disabling
#   the compositor stops it hammering the GPU and replacing xfwm4 restores input — all
#   without a reboot. Typically run over SSH from another machine while frozen:
#       ssh gxbrooks@lab3.lan "/usr/local/bin/recover_xfce_freeze.sh"
#
#   This is a stop-gap, not the fix. Apply the permanent mitigation afterwards with
#   assert/assert_amdgpu.sh (updates linux-firmware) and reboot.
#
#   Run as the user who owns the graphical session (NOT root). If invoked via sudo it
#   re-execs itself as the session owner.
#
# USAGE
#   recover_xfce_freeze.sh [--keep-compositor] [--display :N] [--help|-h]
#
# FLAGS
#   (no flags)          Disable compositing, then xfwm4 --replace (full recovery).
#   --keep-compositor   Only restart xfwm4; leave compositing as-is (xpresent). Use once
#                       the GPU fix is confirmed and you want desktop effects back.
#   --display :N        Target a specific X display (default :0).
#   --help, -h          Show this help and exit.
#
set -uo pipefail

KEEP_COMPOSITOR=false
TARGET_DISPLAY=":0"

show_help() {
    sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^#\s\{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-compositor) KEEP_COMPOSITOR=true ;;
        --display)
            shift
            TARGET_DISPLAY="${1:-:0}"
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error   : Unrecognized argument $1" >&2
            echo "Usage   : $(basename "$0") [--keep-compositor] [--display :N] [--help|-h]" >&2
            exit 1
            ;;
    esac
    shift
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  XFCE freeze recovery (AMD iGPU compositor stall)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# If running as root (e.g. via sudo), hand off to the session owner so xfconf/
# xfwm4 talk to the right D-Bus / X session.
if [[ "$(id -u)" -eq 0 ]]; then
    SESSION_USER="${SUDO_USER:-}"
    if [[ -z "$SESSION_USER" ]]; then
        SESSION_USER="$(ps -o user= -C xfwm4 2>/dev/null | head -1 || true)"
    fi
    if [[ -z "$SESSION_USER" || "$SESSION_USER" == "root" ]]; then
        echo "✗ Could not determine the graphical session owner. Re-run as that user."
        exit 1
    fi
    echo "→ Re-executing as session owner: $SESSION_USER"
    reexec_args=(--display "$TARGET_DISPLAY")
    $KEEP_COMPOSITOR && reexec_args+=(--keep-compositor)
    exec sudo -u "$SESSION_USER" env DISPLAY="$TARGET_DISPLAY" "$0" "${reexec_args[@]}"
fi

export DISPLAY="$TARGET_DISPLAY"

# Recover XAUTHORITY if not already set (SSH sessions usually lack it).
if [[ -z "${XAUTHORITY:-}" ]]; then
    for cand in "$HOME/.Xauthority" "/var/run/lightdm/$USER/xauthority" "/run/lightdm/$USER/xauthority"; do
        if [[ -f "$cand" ]]; then
            export XAUTHORITY="$cand"
            break
        fi
    done
fi

# Recover the D-Bus session bus from a running session process so xfconf-query
# can reach xfconfd (needed to toggle the compositor).
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    for pname in xfce4-session xfconfd xfwm4 xfce4-panel; do
        pid="$(pgrep -u "$USER" -x "$pname" 2>/dev/null | head -1 || true)"
        if [[ -n "$pid" && -r "/proc/$pid/environ" ]]; then
            addr="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
                | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -1)"
            if [[ -n "$addr" ]]; then
                export DBUS_SESSION_BUS_ADDRESS="$addr"
                break
            fi
        fi
    done
fi

echo "→ DISPLAY=$DISPLAY  XAUTHORITY=${XAUTHORITY:-<unset>}"
echo "→ DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-<unset>}"

if ! command -v xfwm4 >/dev/null 2>&1; then
    echo "✗ xfwm4 not found in PATH; is this an XFCE session?"
    exit 1
fi

# Quick health note: surface the IRQ-hog signature if present (informational).
if command -v journalctl >/dev/null 2>&1; then
    hog="$(journalctl -k -b 0 2>/dev/null | grep -c 'dm_irq_work_func.*hogged' || true)"
    if [[ "${hog:-0}" -gt 0 ]]; then
        echo "ℹ️  amdgpu dm_irq_work_func hog events this boot: $hog (the freeze trigger)"
    fi
fi

if [[ "$KEEP_COMPOSITOR" == true ]]; then
    echo "→ Restarting xfwm4 only (compositor left unchanged)..."
else
    if command -v xfconf-query >/dev/null 2>&1; then
        echo "→ Disabling xfwm4 compositing to release the GPU..."
        if xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null; then
            echo "  ✓ use_compositing set to false"
        else
            echo "  ⚠️  Could not set use_compositing (xfconfd unreachable?); continuing"
        fi
    else
        echo "⚠️  xfconf-query not found; skipping compositor disable"
    fi
fi

echo "→ Replacing the window manager (xfwm4 --replace)..."
nohup xfwm4 --replace >/dev/null 2>&1 &
disown 2>/dev/null || true
sleep 2

if pgrep -u "$USER" -x xfwm4 >/dev/null 2>&1; then
    echo "✓ xfwm4 is running. The desktop should now respond to mouse/keyboard."
else
    echo "⚠️  xfwm4 not detected after restart. Try a LightDM restart as a last resort:"
    echo "     ssh -t $USER@\$(hostname) 'sudo systemctl restart lightdm'"
fi

echo ""
echo "Next steps to stop the freeze recurring:"
echo "  • Apply the permanent GPU fix: bash ~/myenv/assert/assert_amdgpu.sh   (updates linux-firmware), then reboot"
echo "  • Diagnose:                    /usr/local/bin/assert_amdgpu.sh --Check"
echo "  • Re-enable effects once GPU is stable: $(basename "$0") --keep-compositor"
echo "    then: DISPLAY=$DISPLAY xfconf-query -c xfwm4 -p /general/use_compositing -s true"
