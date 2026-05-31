#!/bin/bash
#
# refresh_display.sh — Minimal display reinit (xrandr --auto)
#
# WHAT IT DOES / WHEN TO RUN
#   Re-runs xrandr --auto to pick up a display after login or a KVM switch. Used by
#   ~/.xprofile and autostart on session start. For a full KVM recovery over SSH (headless
#   boot, LightDM restart, DRM hotplug), use diagnose/refresh_display_kvm.sh instead.
#
# USAGE: refresh_display.sh [--help|-h]
#
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^#\s\{0,1\}//'
    exit 0
fi

xrandr --auto 2>/dev/null || true
