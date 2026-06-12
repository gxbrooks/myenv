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
#   recover_xfce_freeze.sh [--keep-compositor] [--force] [--display :N] [--help|-h]
#
# FLAGS
#   (no flags)          Disable compositing, then xfwm4 --replace (full recovery).
#   --keep-compositor   Only restart xfwm4; leave compositing as-is (xpresent). Use once
#                       the GPU fix is confirmed and you want desktop effects back.
#   --force             Kill stuck xfwm4/xscreensaver GL, deactivate lock screen, restart
#                       panel. Use when a plain --replace did not restore input.
#   --display :N        Target a specific X display (default :0).
#   --help, -h          Show this help and exit.
#
set -uo pipefail

KEEP_COMPOSITOR=false
FORCE=false
TARGET_DISPLAY=":0"

show_help() {
    sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^#\s\{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-compositor) KEEP_COMPOSITOR=true ;;
        --force) FORCE=true ;;
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
            echo "Usage   : $(basename "$0") [--keep-compositor] [--force] [--display :N] [--help|-h]" >&2
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
    $FORCE && reexec_args+=(--force)
    exec sudo -u "$SESSION_USER" env DISPLAY="$TARGET_DISPLAY" "$0" "${reexec_args[@]}"
fi

export DISPLAY="$TARGET_DISPLAY"

# Recover session env from a live XFCE process (SSH sessions lack XAUTHORITY/DBUS).
recover_session_env_from_pid() {
    local pid="$1"
    [[ -n "$pid" && -r "/proc/$pid/environ" ]] || return 1
    local line
    while IFS= read -r line; do
        case "$line" in
            XAUTHORITY=*)
                [[ -z "${XAUTHORITY:-}" ]] && export XAUTHORITY="${line#XAUTHORITY=}"
                ;;
            DBUS_SESSION_BUS_ADDRESS=*)
                [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && export DBUS_SESSION_BUS_ADDRESS="${line#DBUS_SESSION_BUS_ADDRESS=}"
                ;;
        esac
    done < <(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null)
}

for pname in xfwm4 xfce4-session xfconfd xfce4-panel; do
    pid="$(pgrep -u "$USER" -x "$pname" 2>/dev/null | head -1 || true)"
    recover_session_env_from_pid "$pid"
    [[ -n "${XAUTHORITY:-}" && -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && break
done

# Fallback XAUTHORITY paths if not found in process environ.
if [[ -z "${XAUTHORITY:-}" ]]; then
    for cand in "$HOME/.Xauthority" "/var/run/lightdm/$USER/xauthority" "/run/lightdm/$USER/xauthority"; do
        if [[ -f "$cand" ]]; then
            export XAUTHORITY="$cand"
            break
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

if command -v xscreensaver-command >/dev/null 2>&1; then
    echo "→ Deactivating xscreensaver lock/blank (if active)..."
    xscreensaver-command -deactivate >/dev/null 2>&1 && echo "  ✓ xscreensaver deactivated" \
        || echo "  • xscreensaver not active or unreachable"
fi

if $FORCE; then
    echo "→ --force: stopping GL screen saver hacks and stuck compositor..."
    pkill -u "$USER" -x glmatrix 2>/dev/null || true
    pkill -u "$USER" -f 'xscreensaver.*-root' 2>/dev/null || true
    if pgrep -u "$USER" -x xfwm4 >/dev/null 2>&1; then
        echo "  → killing existing xfwm4 (stuck compositor)"
        killall -u "$USER" -w xfwm4 2>/dev/null || killall -u "$USER" xfwm4 2>/dev/null || true
        sleep 1
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
        if xfconf-query -c xfwm4 -p /general/vblank_mode -s xpresent -t string --create 2>/dev/null; then
            echo "  ✓ vblank_mode set to xpresent"
        fi
    else
        echo "⚠️  xfconf-query not found; skipping compositor disable"
    fi
fi

if command -v xset >/dev/null 2>&1; then
    echo "→ Waking display (xset dpms force on)..."
    timeout 2 xset dpms force on 2>/dev/null || true
fi

echo "→ Replacing the window manager (xfwm4 --replace)..."
if $FORCE && ! pgrep -u "$USER" -x xfwm4 >/dev/null 2>&1; then
    nohup xfwm4 >/dev/null 2>&1 &
else
    nohup xfwm4 --replace >/dev/null 2>&1 &
fi
disown 2>/dev/null || true
sleep 2

if command -v xfce4-panel >/dev/null 2>&1 && $FORCE; then
    echo "→ Reloading xfce4-panel..."
    xfce4-panel -r 2>/dev/null || true
fi

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
