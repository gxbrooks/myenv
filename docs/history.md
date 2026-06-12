# Incident history

## Lab3 XFCE UI freeze — June 2026

### Summary

On **Lab3.lan** (AMD Raphael integrated GPU, PCI `1002:164e`), the XFCE desktop appeared
frozen at the KVM: mouse and keyboard did not respond, while **SSH remained healthy** and
cluster services (Kubernetes, Elasticsearch, etc.) kept running. Recovery required a
**LightDM restart** (`sudo systemctl restart lightdm`) after softer compositor recovery
steps. A **full reboot was not required** for this incident.

### Symptoms

- KVM shows a static desktop; no pointer or keyboard input.
- SSH from Lab1/Lab2 still works.
- `xfwm4` may sit at high CPU or stop processing input.
- Kernel log signature (count with `journalctl -k -b 0 | grep -c 'dm_irq_work_func.*hogged'`):

  ```
  workqueue: dm_irq_work_func [amdgpu] hogged CPU for >10000us N times, consider switching to WQ_UNBOUND
  libEGL warning: DRI3 error: Could not get DRI3 device
  ```

- `glmatrix` (GL screen saver from `~/.xscreensaver`) may be running and adding GPU load.

### Root cause

A known **AMD Raphael / `amdgpu` display-manager IRQ bug**: the `dm_irq_work_func` workqueue
hogs the CPU, which stalls the **xfwm4 compositor** on the DRI3/vblank path. XFCE was
chosen across the lab specifically because it is lighter and more predictable than GNOME
under **KVM switching** between Lab1, Lab2, Lab3, and GaryPC — but the iGPU driver bug
can still wedge the session until the compositor or display stack is reset.

### What myenv does to avoid recurrence

| Layer | Mechanism | Script / config |
|-------|-----------|-----------------|
| **Firmware** | Keep `linux-firmware` current (primary long-term fix; loads after reboot) | `assert/assert_amdgpu.sh` |
| **Compositor** | `xfwm4` `vblank_mode=xpresent`, compositing on when healthy | `assert/assert_amdgpu.sh` |
| **XFCE session** | Suppress hotplug Display dialog; Kitty panel; KVM helpers | `assert/assert_xfce4.sh` |
| **Screen saver** | Timed DPMS via `~/.xscreensaver` (not “never blank”) | `.xscreensaver`, `.xprofile` |
| **KVM display** | `refresh_display.sh` at login; `refresh_display_kvm.sh` for blank display | `diagnose/` |
| **Last-resort kernel** | Optional `amdgpu.dc=0` via grub drop-in (reboot; may affect HDMI audio) | `assert/assert_amdgpu.sh --amdgpu-dc-off` |

Run after login or from SSH to verify mitigations:

```bash
/usr/local/bin/assert_amdgpu.sh --Check
```

### How to detect a freeze

1. **At the KVM** — no input; picture may be static or last frame.
2. **Over SSH** — host responsive; check:

   ```bash
   uptime
   ps aux --sort=-%cpu | head -15
   pgrep -a xfwm4 glmatrix xscreensaver Xorg
   journalctl -k -b 0 | grep -c 'dm_irq_work_func.*hogged'
   timeout 3 xset -display :0 -q    # timeout ⇒ X server wedged
   ```

3. **Health report** — `assert_amdgpu.sh --Check` (IRQ count, firmware, compositor settings).

### Recovery ladder (no full reboot)

Use from **another lab host** once SSH keys are unlocked (`ssh-add ~/.ssh/id_ed25519`).

| Step | When | Command |
|------|------|---------|
| **1. Soft** | First try; compositor stall | `ssh gxbrooks@lab3.lan /usr/local/bin/recover_xfce_freeze.sh` |
| **2. Force** | Step 1 insufficient; kill stuck xfwm4/GL | `ssh gxbrooks@lab3.lan /usr/local/bin/recover_xfce_freeze.sh --force` |
| **3. Escalate** | Automates force + probes X; prompts for LightDM if needed | `ssh gxbrooks@lab3.lan bash /tmp/escalate_xfce_freeze.sh` |
| **4. LightDM** | X/session wedged; **fixed Lab3 June 2026** | `ssh -t gxbrooks@lab3.lan 'sudo systemctl restart lightdm'` |
| **5. KVM refresh** | Login works but KVM picture blank | `sudo /usr/local/bin/refresh_display_kvm.sh` |

One-shot from Lab1 (after `ssh` works):

```bash
bash ~/myenv/diagnose/run_lab3_ui_recovery.sh
```

**Note:** `recover_xfce_freeze.sh --force` disables compositing during recovery. Re-enable
effects only after `assert_amdgpu.sh --Check` looks clean and the GPU is stable.

### Changes added for this incident

| File | Purpose |
|------|---------|
| `diagnose/recover_xfce_freeze.sh` | Added `--force`: recover `XAUTHORITY`/DBus from session processes, deactivate xscreensaver, kill `glmatrix`/stuck `xfwm4`, disable compositing, set `vblank_mode=xpresent`, wake DPMS, reload panel |
| `diagnose/escalate_xfce_freeze.sh` | Escalation wrapper: snapshot, X probe, force recovery, optional LightDM restart |
| `diagnose/run_lab3_ui_recovery.sh` | Lab1 driver: copy scripts, run escalation, post-check |
| `assert/assert_amdgpu.sh` | Idempotent firmware + compositor mitigations (prior commit) |
| `assert/assert_xfce4.sh` | Installs recovery helpers to `/usr/local/bin` |

### Operational notes from this incident

- **SSH keys:** Lab-to-lab recovery requires `id_ed25519` (or `id_rsa`) in the ssh-agent.
  `id_ed25519_github` alone is not authorized on lab hosts. Use `keychain` / `ssh-add`
  before remote recovery (`~/.bashrc` loads `id_ed25519_github` by default — add
  `id_ed25519` to keychain when using lab SSH).
- **Stale `/usr/local/bin`:** If `--force` is “unrecognized”, copy the repo script:
  `sudo cp ~/myenv/diagnose/recover_xfce_freeze.sh /usr/local/bin/`
- **sudo:** LightDM restart needs an interactive TTY (`ssh -t`) and sudo password unless
  passwordless sudo is configured for that command.
- **assert during freeze:** Running `assert_amdgpu.sh` on a wedged session can set
  `use_compositing=true` over SSH without effect; prefer **recover first**, then assert.

### Related docs

- [README.md — AMD iGPU XFCE Freeze](../README.md#amd-igpu-xfce-freeze-lab3--raphael)
- [DISPLAY_MANAGER_RESTART.md](DISPLAY_MANAGER_RESTART.md) — LightDM vs full reboot
- [DISPLAY_MANAGER_AUTOMATION.md](DISPLAY_MANAGER_AUTOMATION.md) — assert_xfce4 automation
