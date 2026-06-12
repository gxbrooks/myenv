#!/bin/bash
#
# run_lab3_ui_recovery.sh — From Lab1, diagnose and recover Lab3 frozen UI (no full reboot)
#
# Requires: SSH to gxbrooks@Lab3.lan (unlock keys first: ssh-add ~/.ssh/id_ed25519)
#
set -euo pipefail

LAB3="${LAB3:-gxbrooks@Lab3.lan}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_DIR="/tmp/myenv-recovery-$$"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Lab3 UI recovery from $(hostname)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$LAB3" "hostname" >/dev/null 2>&1; then
    echo "✗ SSH to $LAB3 failed."
    echo "  Unlock keys on Lab1:  ssh-add ~/.ssh/id_ed25519"
    echo "  Test:                 ssh $LAB3 hostname"
    exit 1
fi

echo "✓ SSH to Lab3 OK"
ssh "$LAB3" "mkdir -p $REMOTE_DIR"
scp "$SCRIPT_DIR/recover_xfce_freeze.sh" "$SCRIPT_DIR/escalate_xfce_freeze.sh" "$LAB3:$REMOTE_DIR/"
ssh "$LAB3" "chmod +x $REMOTE_DIR/*.sh"

echo ""
echo "→ Pre-recovery snapshot"
ssh "$LAB3" "uptime; ps aux --sort=-%cpu | head -10; timeout 3 xset -display :0 q 2>&1 | head -2 || echo 'xset: timeout/fail'"

echo ""
echo "→ Escalation (force recovery + LightDM restart if needed)"
ssh -t "$LAB3" "bash $REMOTE_DIR/escalate_xfce_freeze.sh" || {
    echo "→ escalate exited $?, trying LightDM restart directly..."
    ssh -t "$LAB3" "sudo systemctl restart lightdm"
}

echo ""
echo "→ Optional KVM display refresh"
ssh -t "$LAB3" "sudo /usr/local/bin/refresh_display_kvm.sh 2>/dev/null || sudo bash ~/repos/myenv/diagnose/refresh_display_kvm.sh 2>/dev/null || true"

echo ""
echo "→ Post-recovery check"
ssh "$LAB3" "systemctl is-active lightdm; pgrep -a Xorg | head -2; timeout 3 xset -display :0 q 2>&1 | head -2 || true"
ssh "$LAB3" "rm -rf $REMOTE_DIR" 2>/dev/null || true

echo ""
echo "✅ Done. Switch KVM to Lab3 — login screen or desktop should respond within ~10s."
