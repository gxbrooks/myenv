#!/bin/bash
#
# diagnose_hdmi_audio.sh — List audio devices and optionally set default HDMI sink
#
# Run on the Ubuntu machine (interactive session). No sudo required for normal
# PipeWire/PulseAudio user commands.
#
# WHAT IT DOES / WHEN TO RUN
#   Lists PipeWire/PulseAudio sinks and cards; optional --set-hdmi picks the first HDMI
#   sink as default. Use after a KVM switch when browser/system audio is on the wrong
#   device. Complements display scripts in diagnose/ (see docs/ubuntu-hdmi-audio-kvm.md).
#
# USAGE: diagnose_hdmi_audio.sh [--set-hdmi] [--help|-h]
#
set -euo pipefail

SET_HDMI=false
case "${1:-}" in
  -h|--help)
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^#\s\{0,1\}//'
    exit 0
    ;;
  --set-hdmi) SET_HDMI=true ;;
esac

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  HDMI audio diagnosis (PipeWire / PulseAudio)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if command -v wpctl >/dev/null 2>&1; then
  echo "── wpctl status (Audio section) ──"
  wpctl status 2>/dev/null | sed -n '/Audio/,/^$/p' || wpctl status
  echo ""
fi

if command -v pactl >/dev/null 2>&1; then
  echo "── pactl get-default-sink ──"
  pactl get-default-sink 2>/dev/null || true
  echo ""
  echo "── pactl list short sinks ──"
  pactl list short sinks 2>/dev/null || true
  echo ""
  echo "── pactl list short cards ──"
  pactl list short cards 2>/dev/null || true
  echo ""
fi

if command -v aplay >/dev/null 2>&1; then
  echo "── aplay -l ──"
  aplay -l 2>/dev/null || true
  echo ""
fi

if [[ "$SET_HDMI" == true ]]; then
  if ! command -v pactl >/dev/null 2>&1; then
    echo "pactl not found; cannot --set-hdmi automatically."
    exit 1
  fi
  # Pick first sink whose name contains hdmi (case-insensitive)
  SINK_LINE=$(pactl list short sinks 2>/dev/null | awk 'tolower($0) ~ /hdmi/ {print; exit}')
  if [[ -z "${SINK_LINE:-}" ]]; then
    echo "No sink with 'hdmi' in the name found. Set default manually in Settings → Sound,"
    echo "or run: pactl set-default-sink '<name>'"
    exit 1
  fi
  SINK_NAME=$(echo "$SINK_LINE" | awk '{print $2}')
  echo "→ Setting default sink to: $SINK_NAME"
  pactl set-default-sink "$SINK_NAME"
  pactl set-sink-mute "$SINK_NAME" 0
  pactl set-sink-volume "$SINK_NAME" 50%
  echo "Done. Retry audio in the browser."
fi
