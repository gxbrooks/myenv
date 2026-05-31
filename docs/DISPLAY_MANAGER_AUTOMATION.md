# LightDM and XFCE session automation

`assert/assert_xfce4.sh` configures the display stack without manual `dpkg-reconfigure` prompts.

## What is automated

1. **Default display manager** — LightDM via `dpkg-reconfigure` or fallback (`/etc/X11/default-display-manager` + systemd enable).
2. **Default session** — XFCE:
   - System-wide: `/etc/lightdm/lightdm.conf.d/50-myenv-default-session.conf` (`user-session=xfce`)
   - Per-user: `~/.dmrc` (`Session=xfce`)
3. **Repo-linked session files** — `~/.xprofile`, `~/.config/autostart`, `~/.xscreensaver`, Kitty config.
4. **KVM persistence** — runs `diagnose/wake_on_kvm.sh` (sudo): sleep inhibit, USB wake, optional Xorg monitor snippet, installs `refresh_display.sh`.
5. **AMD iGPU** — runs `assert/assert_amdgpu.sh` (firmware, xfwm4 compositor, optional `amdgpu.dc` grub drop-in).
6. **Helpers in `/usr/local/bin`** — `refresh_display_kvm.sh`, `recover_xfce_freeze.sh`, `assert_amdgpu.sh`.

## Orchestration

- Full environment: `bash assert_myenv.sh`
- Desktop only: `bash assert/assert_xfce4.sh`
- Fresh clone: `bash install_myenv.sh`

All assert scripts support `--Check` (dry-run) and `--Debug`.

## Related docs

- [DISPLAY_MANAGER_RESTART.md](DISPLAY_MANAGER_RESTART.md) — reboot vs LightDM restart
- [ubuntu-hdmi-audio-kvm.md](ubuntu-hdmi-audio-kvm.md) — audio after KVM switch
