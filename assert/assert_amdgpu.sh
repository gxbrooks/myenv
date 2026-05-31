#!/bin/bash
#
# assert_amdgpu.sh — Assert the AMD iGPU configuration that avoids the XFCE freeze
#
# WHAT IT DOES / WHEN TO RUN
#   Idempotently applies every mitigation for the AMD Raphael iGPU "dm_irq_work_func
#   hogged CPU" bug, which stalls the xfwm4 compositor and freezes the desktop (mouse
#   and keyboard appear dead at the KVM while SSH stays alive). It is invoked automatically
#   by assert_xfce4.sh after the XFCE session is configured, and can also be run standalone
#   (it is installed to /usr/local/bin) — including over SSH after a reboot to verify the
#   fix held.
#
#   It performs every action it safely can WITHOUT rebooting:
#     1. Keeps linux-firmware current (the primary fix; outdated GPU firmware is the usual
#        trigger). A reboot is needed only to LOAD the new firmware — the script tells you.
#     2. Forces xfwm4 vblank_mode=xpresent + use_compositing=true (reduces GPU contention).
#     3. Optionally adds/removes the amdgpu.dc=0 kernel parameter (opt-in last resort).
#
#   Each step is skipped when already satisfied, so re-running is cheap and safe. When a
#   reboot is required, the script prints the exact reboot command and the single post-reboot
#   command to verify the fix, and exits with status 10 so callers can surface it.
#
# USAGE
#   assert_amdgpu.sh [--Check|-c] [--Debug|-d] [--skip-firmware-update]
#                    [--amdgpu-dc-off | --amdgpu-dc-on] [--help|-h]
#
# FLAGS
#   --Check, -c            Dry-run + health report only. Makes no changes; prints what a
#                          live run would do plus current GPU/firmware/IRQ/compositor state.
#                          This is also the recommended post-reboot verification command.
#   --Debug, -d            Verbose logging.
#   --skip-firmware-update Do not upgrade linux-firmware (e.g. offline / CI runs).
#   --amdgpu-dc-off        Opt-in LAST RESORT: add `amdgpu.dc=0` to the kernel command line
#                          via /etc/default/grub.d, disabling AMD Display Core to bypass the
#                          buggy IRQ path. Runs update-grub; reboot required.
#                          WARNING: on Raphael/DCN hardware this can disable HDMI/DP audio
#                          and may yield NO display at boot. Use only after a firmware update
#                          + reboot did not stop the freeze. Revert with --amdgpu-dc-on.
#   --amdgpu-dc-on         Remove the myenv amdgpu.dc grub drop-in (revert --amdgpu-dc-off).
#   --help, -h             Show this help and exit.
#
# EXIT STATUS
#   0   Completed; no reboot required (or --Check).
#   10  Completed; a reboot is required to apply firmware/kernel changes.
#   1   Argument or fatal error.
#
# Requires: sudo privileges for live (non-check) firmware/grub changes.

set -uo pipefail

CHECK=false
DEBUG=false
SKIP_FIRMWARE_UPDATE=false
AMDGPU_DC_OFF=false
AMDGPU_DC_ON=false
script_name="$(basename "${BASH_SOURCE[0]}")"

show_help() {
    sed -n '2,47p' "${BASH_SOURCE[0]}" | sed 's/^#\s\{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --Check|-c) CHECK=true ;;
        --Debug|-d) DEBUG=true ;;
        --skip-firmware-update) SKIP_FIRMWARE_UPDATE=true ;;
        --amdgpu-dc-off) AMDGPU_DC_OFF=true ;;
        --amdgpu-dc-on) AMDGPU_DC_ON=true ;;
        --help|-h) show_help; exit 0 ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." >&2
            echo "Usage   : $script_name [--Check|-c] [--Debug|-d] [--skip-firmware-update] [--amdgpu-dc-off|--amdgpu-dc-on] [--help|-h]" >&2
            exit 1
            ;;
    esac
    shift
done

if $AMDGPU_DC_OFF && $AMDGPU_DC_ON; then
    echo "Error   : --amdgpu-dc-off and --amdgpu-dc-on are mutually exclusive." >&2
    exit 1
fi

hr()   { echo "──────────────────────────────────────────────────"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠️  $*"; }
info() { echo "  • $*"; }

GRUB_DROPIN="/etc/default/grub.d/99-myenv-amdgpu.cfg"
REBOOT_REQUIRED=false

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AMD iGPU freeze mitigation — $(hostname) $(date '+%Y-%m-%d %H:%M')"
$CHECK && echo "  (check mode: report only, no changes)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

#############################################
# 0. Detect AMD GPU (no-op on other hardware)
#############################################
hr; echo "GPU / driver"
GPU_LINE="$(lspci -nn 2>/dev/null | grep -Ei 'vga|display|3d' || true)"
HAVE_AMD_GPU=false
if [[ -n "$GPU_LINE" ]]; then
    echo "$GPU_LINE" | sed 's/^/  /'
    if echo "$GPU_LINE" | grep -qi 'AMD\|ATI\|1002:'; then
        HAVE_AMD_GPU=true
    fi
    echo "$GPU_LINE" | grep -qi 'raphael\|1002:164e' \
        && warn "AMD Raphael iGPU — affected by the dm_irq_work_func freeze bug"
else
    warn "No GPU line from lspci"
fi
if [[ -r /sys/module/amdgpu/version ]]; then
    info "amdgpu module version: $(cat /sys/module/amdgpu/version)"
fi
$DEBUG && echo "Debug   : HAVE_AMD_GPU=$HAVE_AMD_GPU CHECK=$CHECK"

if ! $HAVE_AMD_GPU; then
    hr
    echo "No AMD GPU detected — no AMD-specific mitigations needed. Nothing to do."
    echo "Result  : assert_amdgpu complete (no-op on non-AMD hardware)"
    exit 0
fi

#############################################
# 1. linux-firmware freshness (primary fix; download/install, no reboot here)
#############################################
hr; echo "linux-firmware (primary fix — keep current)"
if $SKIP_FIRMWARE_UPDATE; then
    info "skipped (--skip-firmware-update)"
elif ! command -v apt-cache >/dev/null 2>&1; then
    warn "apt-cache unavailable; cannot manage linux-firmware"
else
    fw_installed="$(dpkg-query -W -f='${Version}' linux-firmware 2>/dev/null || echo '')"
    fw_candidate="$(apt-cache policy linux-firmware 2>/dev/null | awk '/Candidate:/{print $2}')"
    info "installed:  ${fw_installed:-<none>}"
    info "candidate:  ${fw_candidate:-unknown}"
    if [[ -z "$fw_installed" ]]; then
        warn "linux-firmware not installed; skipping"
    elif [[ -z "$fw_candidate" || "$fw_candidate" == "(none)" ]]; then
        ok "no candidate info (apt index may be stale); leaving firmware as-is"
    elif [[ "$fw_candidate" == "$fw_installed" ]]; then
        ok "linux-firmware is up to date"
    elif $CHECK; then
        echo "  Check   : would upgrade linux-firmware $fw_installed → $fw_candidate (then reboot)"
    else
        echo "  → upgrading linux-firmware $fw_installed → $fw_candidate (sudo)"
        sudo apt update -qq || true
        if sudo apt install --only-upgrade -y linux-firmware; then
            ok "linux-firmware upgraded (reboot required to load new GPU firmware)"
            REBOOT_REQUIRED=true
        else
            warn "linux-firmware upgrade failed; retry: sudo apt install --only-upgrade linux-firmware"
        fi
    fi
fi

#############################################
# 2. xfwm4 compositor (mitigation: xpresent vblank, compositing on)
#############################################
hr; echo "xfwm4 compositor (mitigation)"
if ! command -v xfconf-query >/dev/null 2>&1; then
    warn "xfconf-query not in PATH; skipped compositor settings"
elif [[ -z "${DISPLAY:-}" ]] || ! xfconf-query -c xfwm4 -l >/dev/null 2>&1; then
    warn "xfwm4 xfconf channel not reachable (no DISPLAY / not in an XFCE session); skipped"
else
    cur_vblank="$(xfconf-query -c xfwm4 -p /general/vblank_mode -v 2>/dev/null || echo '<unset>')"
    cur_comp="$(xfconf-query -c xfwm4 -p /general/use_compositing -v 2>/dev/null || echo '<unset>')"
    info "vblank_mode:     $cur_vblank  (target: xpresent)"
    info "use_compositing: $cur_comp  (target: true)"
    if $CHECK; then
        [[ "$cur_vblank" != "xpresent" ]] && echo "  Check   : would set vblank_mode=xpresent"
        [[ "$cur_comp" != "true" ]] && echo "  Check   : would set use_compositing=true"
    else
        if [[ "$cur_vblank" != "xpresent" ]]; then
            xfconf-query -c xfwm4 -p /general/vblank_mode -s xpresent -t string --create 2>/dev/null \
                && ok "set vblank_mode=xpresent" || warn "could not set vblank_mode"
        fi
        if [[ "$cur_comp" != "true" ]]; then
            xfconf-query -c xfwm4 -p /general/use_compositing -s true -t bool --create 2>/dev/null \
                && ok "set use_compositing=true" || warn "could not set use_compositing"
        fi
        [[ "$cur_vblank" == "xpresent" && "$cur_comp" == "true" ]] && ok "compositor already configured"
    fi
fi

#############################################
# 3. amdgpu.dc kernel parameter (opt-in last resort)
#############################################
hr; echo "amdgpu kernel parameters"
LIVE_CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"
if echo "$LIVE_CMDLINE" | grep -qw 'amdgpu.dc=0'; then
    info "live cmdline: amdgpu.dc=0 ACTIVE (Display Core disabled)"
else
    info "live cmdline: amdgpu.dc not set (Display Core enabled — normal)"
fi
if [[ -f "$GRUB_DROPIN" ]]; then
    info "grub drop-in present: $GRUB_DROPIN"
fi

if $AMDGPU_DC_OFF; then
    if [[ -f "$GRUB_DROPIN" ]] && grep -q 'amdgpu.dc=0' "$GRUB_DROPIN" 2>/dev/null; then
        ok "amdgpu.dc=0 already configured in $GRUB_DROPIN"
    elif $CHECK; then
        echo "  Check   : would write $GRUB_DROPIN (amdgpu.dc=0) and run update-grub"
        warn "amdgpu.dc=0 disables Display Core (may drop HDMI/DP audio; risk of no display on DCN/Raphael)"
    else
        warn "applying amdgpu.dc=0 — disables AMD Display Core."
        echo "      This can disable HDMI/DP audio and, on some Raphael/DCN units, leave NO display at boot."
        echo "      Recover via SSH: bash $script_name --amdgpu-dc-on && sudo reboot"
        sudo mkdir -p "$(dirname "$GRUB_DROPIN")"
        sudo tee "$GRUB_DROPIN" > /dev/null <<'EOF'
# Managed by myenv assert/assert_amdgpu.sh (--amdgpu-dc-off)
# Last-resort workaround for the AMD Raphael iGPU dm_irq_work_func freeze:
# disable AMD Display Core so vsync/IRQs avoid the buggy dc path.
# Remove with: assert_amdgpu.sh --amdgpu-dc-on   (or delete this file + update-grub)
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT amdgpu.dc=0"
EOF
        if sudo update-grub; then
            ok "amdgpu.dc=0 added (reboot required)"
            REBOOT_REQUIRED=true
        else
            warn "update-grub failed; review $GRUB_DROPIN manually"
        fi
    fi
elif $AMDGPU_DC_ON; then
    if [[ ! -f "$GRUB_DROPIN" ]]; then
        ok "no myenv amdgpu grub drop-in present (nothing to revert)"
    elif $CHECK; then
        echo "  Check   : would remove $GRUB_DROPIN and run update-grub (revert amdgpu.dc=0)"
    else
        echo "  → removing $GRUB_DROPIN (re-enabling AMD Display Core)"
        sudo rm -f "$GRUB_DROPIN"
        if sudo update-grub; then
            ok "amdgpu.dc override removed (reboot required)"
            REBOOT_REQUIRED=true
        else
            warn "update-grub failed; review grub config manually"
        fi
    fi
else
    info "amdgpu.dc unmanaged (enable the last-resort workaround with --amdgpu-dc-off)"
fi

#############################################
# 4. Health signals (kernel IRQ hog, REG_WAIT, DRI3)
#############################################
hr; echo "Health signals"
DM_IRQ_ACTIVE=false
if command -v journalctl >/dev/null 2>&1; then
    HOG_LINES="$(journalctl -k -b 0 2>/dev/null | grep 'dm_irq_work_func.*hogged' || true)"
    if [[ -n "$HOG_LINES" ]]; then
        DM_IRQ_ACTIVE=true
        last_n="$(echo "$HOG_LINES" | tail -1 | sed -n 's/.*hogged CPU for >[0-9]*us \([0-9]*\) times.*/\1/p')"
        warn "dm_irq_work_func hog events this boot: $(echo "$HOG_LINES" | wc -l | tr -d ' ') (latest count: ${last_n:-?})"
        echo "      (rising counts mean the freeze is actively degrading the session)"
    else
        ok "no dm_irq_work_func hog events this boot"
    fi
    journalctl -k -b 0 2>/dev/null | grep -q 'REG_WAIT timeout.*optc' \
        && warn "boot-time amdgpu REG_WAIT timeout present (driver/firmware mismatch indicator)"
else
    warn "journalctl unavailable; cannot scan kernel log"
fi
XSE="$HOME/.xsession-errors"
if [[ -f "$XSE" ]]; then
    dri3="$(grep -c 'DRI3\|libEGL' "$XSE" 2>/dev/null)"; dri3="${dri3:-0}"
    [[ "$dri3" -gt 0 ]] && warn "$dri3 DRI3/libEGL warning(s) in ~/.xsession-errors (HW accel falling back to software)"
fi

#############################################
# 5. Result + next steps
#############################################
hr
if $CHECK; then
    if $DM_IRQ_ACTIVE; then
        echo "VERDICT : freeze bug ACTIVE this boot."
        echo "  • Apply mitigations (live):  bash $script_name"
        echo "  • If it persists after a firmware update + reboot, last resort:"
        echo "       bash $script_name --amdgpu-dc-off && sudo reboot"
    else
        echo "VERDICT : no freeze signature this boot. Configuration looks healthy."
    fi
    echo "Result  : assert_amdgpu check complete (no changes applied)"
    exit 0
fi

if $REBOOT_REQUIRED; then
    echo "⚠️  REBOOT REQUIRED to load new firmware / kernel parameters."
    echo ""
    echo "  Reboot now:"
    echo "      sudo reboot"
    echo ""
    echo "  After reboot, verify the fix held (single command):"
    echo "      $script_name --Check        # or: /usr/local/bin/$script_name --Check"
    echo ""
    echo "  (That reports whether dm_irq events are gone and, if not, the next step.)"
    echo "Result  : assert_amdgpu finished (reboot required)"
    exit 10
fi

echo "Result  : assert_amdgpu finished successfully (no reboot required)"
exit 0
