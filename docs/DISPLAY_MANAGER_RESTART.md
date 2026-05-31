# Display manager restart vs full reboot

## When LightDM restart is enough

Use `sudo systemctl restart lightdm` (or accept the prompt at the end of `assert/assert_xfce4.sh`) when:

- You changed **session dotfiles** (`~/.xprofile`, autostart, `.xscreensaver`) and need them re-sourced.
- LightDM or the default session was switched to XFCE and you want the login screen without rebooting.

**Effect:** Ends the current graphical session immediately (black screen). Unsaved work in GUI apps is lost.

## When a full reboot is required

Use `sudo reboot` when:

- **`linux-firmware`** was upgraded (AMD GPU freeze fix — new firmware loads at boot).
- **Kernel command line** changed (e.g. `assert/assert_amdgpu.sh --amdgpu-dc-off` and `update-grub`).
- Xorg started **headless** and `refresh_display_kvm.sh` reports “REBOOT REQUIRED” (no device for Screen0).

After reboot, verify AMD mitigations:

```bash
/usr/local/bin/assert_amdgpu.sh --Check
```

## Non-interactive / SSH

```bash
bash ~/myenv/assert/assert_xfce4.sh --no-restart-lightdm    # skip LightDM prompt
bash ~/myenv/assert/assert_xfce4.sh --restart-lightdm       # restart without prompt
```

If `assert_xfce4` exits with a **FULL REBOOT REQUIRED** message, do not restart LightDM — reboot instead.
