# myenv - KVM-Friendly Ubuntu Desktop Environment

**Latest Version:** V1.1 - Fully Automated Setup with Interactive Prompts

## Overview

This project provides a **fully automated** configuration for Ubuntu mini-PCs to work reliably with KVM (Keyboard-Video-Mouse) switches. It automatically switches to XFCE4 desktop with LightDM, configures display persistence, USB wake support, and prevents common issues like screen blanking, display disconnection, and system sleep.

**New in V1.1:** Complete automation - no manual display manager selection, no manual session selection, interactive restart prompts with user choice.

## Problem Statement

When using KVM switches with Ubuntu systems, several issues commonly occur:
- **Display Disconnection**: Monitors go blank or lose signal when the KVM switches away
- **Screen Blanking**: DPMS (Display Power Management Signaling) turns off the display
- **USB Wake Issues**: Keyboard and mouse don't wake the system after switching back
- **Auto-Sleep**: System may enter sleep/suspend mode when not actively in use

## Solution

This project provides a complete XFCE4 desktop environment configuration with KVM switch workarounds:

### What Gets Configured

1. **XFCE4 Desktop**: Lightweight, stable desktop environment
2. **LightDM Display Manager**: Automatically configured as default (V1.1+)
3. **XFCE4 Default Session**: Automatically selected at login (V1.1+)
4. **Display Persistence**: 
   - Disables DPMS video shutdown
   - Prevents screen blanking
   - Forces HDMI output to stay active
   - Auto-refreshes display on login (for KVM switches)
5. **USB Wake Support**:
   - Enables wakeup for all USB devices
   - Creates persistent udev rules
6. **Sleep Prevention**:
   - Blocks automatic system sleep
   - Masks systemd sleep targets
   - Allows manual suspend when needed
7. **Screensaver**: Configures xscreensaver with `glmatrix` theme

### Repository Structure

```
myenv/
├── README.md
├── assert/                            # Idempotent setup scripts (run via assert_myenv.sh)
│   ├── assert_packages.sh             # apt packages, Cursor, draw.io, csdm-injector, context-variables
│   ├── assert_xfce4.sh                # XFCE4/LightDM/KVM desktop assert
│   ├── assert_amdgpu.sh               # AMD iGPU freeze config; --Check = health report
│   ├── assert_dotfiles.sh             # Cursor settings/keybindings symlinks
│   ├── assert_extensions.sh           # Cursor extensions from extensions.txt (skip in CURSOR_AGENT)
│   ├── assert_gems.sh                 # Ruby gems (asciidoctor-pdf, asciidoctor-diagram, rouge)
│   └── assert_onedrive.sh             # rclone mount OneDrive/SharePoint → $HOME
├── diagnose/                          # On-demand diagnose & repair (not run at install by default)
│   ├── recover_xfce_freeze.sh         # Recover frozen XFCE desktop over SSH (no reboot)
│   ├── refresh_display_kvm.sh         # Full KVM display recovery (sudo, SSH-friendly)
│   ├── refresh_display.sh             # Minimal xrandr --auto (installed to /usr/local/bin)
│   ├── wake_on_kvm.sh                 # KVM persistence (sleep/USB/HDMI); run by assert_xfce4
│   └── diagnose_hdmi_audio.sh         # HDMI audio sinks / optional --set-hdmi
├── xfce/                              # XFCE config only
│   └── myenv-kitty.desktop            # Kitty panel launcher desktop entry
├── kitty/                             # Kitty config only
│   └── kitty.conf
├── docs/
│   ├── ubuntu-hdmi-audio-kvm.md       # HDMI audio after KVM switch
│   ├── DISPLAY_MANAGER_AUTOMATION.md  # LightDM/display-manager automation notes
│   └── DISPLAY_MANAGER_RESTART.md     # Reboot vs LightDM restart guide
├── dotfiles/cursor/                   # Cursor settings, keybindings, extensions.txt
├── autostart/                         # X session autostart .desktop files
├── .xprofile                          # X session startup (xset, refresh_display)
├── .xscreensaver                      # Screensaver config (glmatrix)
├── tmp/                               # Ephemeral notes & scratch (gitignored; not in git)
├── assert_myenv.sh                    # Orchestrator
├── assert/                            # assert_packages.sh, assert_xfce4.sh, …
└── assert_git.sh, assert_bashrc.sh, install_myenv.sh
```

Config lives under `xfce/` and `kitty/`; scripts live under `assert/` (setup) and `diagnose/` (repair).
Use `tmp/` for local-only notes (reboot checklists, agent scratch); see `.gitignore`.

## Installation

### Prerequisites

- Ubuntu system (tested on Ubuntu 22.04 LTS / 24.04 LTS)
- Sudo privileges
- Internet connection for package installation

### Setup Instructions

1. **Clone or place this repository** in your home directory:
   ```bash
   git clone https://github.com/gxbrooks/myenv.git ~/myenv
   cd ~/myenv
   ```

2. **Run the desktop assert** (or use `assert_myenv.sh`, which includes this step):
   ```bash
   bash assert/assert_xfce4.sh
   ```
   
   The script will automatically:
   - Install XFCE4, LightDM, xdotool, and xscreensaver packages
   - **Switch to LightDM display manager** (no manual prompt!)
   - **Set XFCE4 as default session** (no manual selection needed!)
   - Create symbolic links from your home directory to repository config files
   - Run `diagnose/wake_on_kvm.sh` to configure KVM switch workarounds
   - Set up autostart entries for display refresh and screensaver
   - **Prompt you to restart** with interactive choice

3. **Choose how to restart** (if display manager changed):
   - **Option A:** Reboot (recommended - graceful shutdown)
   - **Option B:** Restart display manager (faster but instant blackout)
   - **Option S:** Skip (do it manually later)
   
   The script waits for your choice, giving you time to save work!

4. **After restart**, you'll automatically be in XFCE4 - no manual session selection needed!

### What Gets Linked

The setup script creates symbolic links in your home directory pointing to this repository:

| Your Home Directory | → | Repository |
|---------------------|---|------------|
| `~/.xprofile` | → | `~/myenv/.xprofile` |
| `~/.config/autostart` | → | `~/myenv/autostart` |
| `~/.xscreensaver` | → | `~/myenv/.xscreensaver` |

**Benefits of linking**:
- Changes to the repository are immediately reflected in your environment
- Easy to version control your configuration
- Can sync across multiple systems

### Cursor Dotfiles

Cursor configuration now lives in this repository:

| Your Home Directory | → | Repository |
|---------------------|---|------------|
| `~/.config/Cursor/User/settings.json` | → | `~/myenv/dotfiles/cursor/settings.json` |
| `~/.config/Cursor/User/keybindings.json` | → | `~/myenv/dotfiles/cursor/keybindings.json` |
| `~/.config/Cursor/User/snippets/markdown.json` | → | `~/myenv/dotfiles/cursor/snippets/markdown.json` |

Use:
- `bash assert/assert_dotfiles.sh` to assert symlinks (or import first-time files)
- `bash assert/assert_extensions.sh` to assert Cursor extensions from `dotfiles/cursor/extensions.txt`

**Run `assert_myenv.sh` from an external terminal** (kitty, ssh) when steps need `sudo` (apt, gems). Extension install uses the **headless** Cursor CLI and does not open a GUI window per extension.

| Step | Notes |
|------|--------|
| `sudo apt install` / `sudo gem install` | Needs a TTY for your sudo password (Agent sandbox often blocks this) |
| `assert_onedrive.sh` | Needs sudo for rclone (rclone.org binary); Optimiz Microsoft login needs a TTY/browser (skipped in `CURSOR_AGENT`) |
| `assert_extensions.sh` | Uses `/opt/cursor/usr/share/cursor/bin/cursor` (headless cli.js) via `/usr/local/bin/cursor`; dependency-ordered install waves |

`assert_packages.sh` ensures `/usr/local/bin/cursor` execs the headless CLI script, **not** the Electron binary. The old wrapper (`exec /opt/cursor/.../cursor`) caused a new Cursor window on every `--list-extensions` / `--install-extension` call.

The Agent sets `CURSOR_AGENT` in the shell; `assert_myenv.sh` skips extension install during agent sessions. Run full assert from kitty when sudo or extension sync is required.

See [Cursor terminal / sandbox docs](https://cursor.com/docs/agent/tools/terminal) if the Agent reports sandbox restrictions.

### csdm-injector credentials (local env — not in git)

Sensitive `SN_*` variables are **not** stored in this repository. Best practice for a
small related block of CLI secrets on a Linux workstation:

| Practice | Choice here |
|----------|-------------|
| Location | XDG config: `~/.config/csdm-injector/env` |
| Permissions | directory `0700`, file `0600` |
| Format | shell `KEY=value` (dotenv), single-quote passwords with metacharacters |
| Loading | myenv `.bashrc` sources the file with `set -a` when it exists |
| Template | `dotfiles/csdm-injector/env.example` (placeholders only) |

`assert_bashrc.sh` creates the directory, copies the example to `env` **once** (never
overwrites an existing `env`), and refreshes `env.example` beside it. Fill in real
values locally; open a new shell (or `set -a; source ~/.config/csdm-injector/env; set +a`).

Optional overrides: `XDG_CONFIG_HOME`, or set `CSDM_INJECTOR_SRC` when building the `.deb`.

### OneDrive (Optimiz and later accounts)

`assert/assert_onedrive.sh` keeps Microsoft OneDrive folders available under `$HOME` using
[rclone](https://rclone.org/onedrive/) (`rclone mount` with VFS cache). Ubuntu's `rclone`
package is too old for current OneDrive Business auth, so the script installs the
[official rclone.org binary](https://rclone.org/install/).

| Account | Portal | Local folder | rclone remote |
|---------|--------|--------------|---------------|
| Optimiz (OneDrive for Business) | https://optimiz-my.sharepoint.com/my | `~/OneDrive-Optimiz` | `onedrive-optimiz:` |

Tokens live in `~/.config/rclone/rclone.conf` (not in git). Each account has its own
remote and a `systemd --user` unit (`rclone-onedrive-<id>.service`) so a later personal
OneDrive or another company's tenant can be added without colliding. To add an account,
append a row to `ONEDRIVE_ACCOUNTS` in `assert/assert_onedrive.sh`.

Microsoft login cannot be fully automated. On an interactive TTY the script opens rclone's
browser OAuth. From an agent session or cron it installs rclone and prints:

```bash
rclone config create onedrive-optimiz onedrive config_type=onedrive
```

Re-run `bash assert/assert_onedrive.sh` after that so the user unit can mount
`onedrive-optimiz:` on `~/OneDrive-Optimiz`. If rclone's default Azure app is blocked by
the tenant, set `RCLONE_ONEDRIVE_CLIENT_ID` and `RCLONE_ONEDRIVE_CLIENT_SECRET` to a
tenant-approved app and re-run.

The script removes leftover abraunegg `onedrive` units/config if they are present.

### AsciiDoc and PlantUML (documentation builds)

`assert_packages.sh` installs `asciidoctor`, `graphviz`, and `plantuml`; **`draw.io` desktop** (official `.deb` from [jgraph/drawio-desktop](https://github.com/jgraph/drawio-desktop) GitHub releases — provides the `drawio` CLI for GUI editing and headless SVG/PNG export); **`csdm-injector`** (builds a local `.deb` from [`~/repos/csdm-injector`](https://github.com/gxbrooks/csdm-injector); override with `CSDM_INJECTOR_SRC` / `CSDM_INJECTOR_FORCE=1`); and **`context-variables`** (builds from [`~/repos/context-variables`](https://github.com/gxbrooks/context-variables); `CONTEXT_VARIABLES_SRC` / `CONTEXT_VARIABLES_FORCE=1` — provides `generate-contexts` / `vars-grid`). `assert_gems.sh` installs `asciidoctor-pdf`, `asciidoctor-diagram`, and `rouge` (server-side source highlighting for HTML/PDF). Together they render `[plantuml]` blocks in `.adoc` files to HTML and PDF (no Mermaid CLI or Kroki required).

After `assert_myenv.sh`, build a document from its directory:

```bash
asciidoctor -r asciidoctor-diagram -a toc=left -a sectnums doc.adoc
asciidoctor-pdf -r asciidoctor-diagram doc.adoc
```

## How It Works

### assert/assert_xfce4.sh

The desktop assert script performs all configuration automatically (also accepts `--Check` for dry-run and `--Debug`). It lives in `assert/`; the repo root is its parent directory.

1. **Install Packages**: XFCE4, LightDM, xdotool, xscreensaver
2. **Set LightDM as Default Display Manager** (V1.1+)
   - Detects current display manager
   - Switches to LightDM non-interactively
   - Fallback method if dpkg-reconfigure fails
3. **Set XFCE4 as Default Session** (V1.1+)
   - System-wide: `/etc/lightdm/lightdm.conf.d/50-myenv-default-session.conf`
   - User-specific: `~/.dmrc`
4. **Link ~/.xprofile**: X session startup commands
5. **Link ~/.config/autostart**: Autostart directory
6. **Link ~/.xscreensaver**: Screensaver configuration
7. **Install helpers** to `/usr/local/bin`: `refresh_display_kvm.sh`, `recover_xfce_freeze.sh`, `assert_amdgpu.sh`
8. **AMD iGPU freeze mitigation**: runs `assert/assert_amdgpu.sh` (firmware, compositor, optional `amdgpu.dc`)
9. **Run `diagnose/wake_on_kvm.sh`**: KVM switch workarounds (see below)
10. **Interactive Restart Prompt** (V1.1+, skipped when there is no TTY, `NONINTERACTIVE=1`, `--Check`, or when a full reboot is pending)
   - Option A: Reboot (graceful)
   - Option B: Restart display manager (fast)
   - Option S: Skip (manual later)

### diagnose/wake_on_kvm.sh

This script performs system-level configuration (requires sudo; invoked by `assert_xfce4.sh`):

1. **Systemd Inhibit**: Blocks automatic sleep/idle
2. **Legacy xprofile cleanup**: Removes old DPMS-disable lines if present
3. **HDMI Config**: Optional Xorg monitor config when `DISPLAY` and `xrandr` are available
4. **USB Wake**: Enables wake support for all USB devices + udev rule
5. **Sleep Targets**: Masks systemd sleep/suspend/hibernate targets
6. **Display Refresh**: Installs `diagnose/refresh_display.sh` → `/usr/local/bin/refresh_display.sh`

### Autostart Applications

- **xscreensaver**: Starts screensaver daemon (uses glmatrix)
- **refresh-display**: Runs `xrandr --auto` to reinitialize display after login

## Idempotency

Both scripts are idempotent - safe to run multiple times:
- Checks if configurations already exist before applying
- Won't duplicate settings or break existing configurations
- Useful for updates or re-applying after system changes

## AMD iGPU XFCE Freeze (Lab3 / Raphael)

On hosts with an **AMD Raphael integrated GPU** (e.g. Lab3, PCI `1002:164e`), the XFCE
desktop can freeze: the mouse/keyboard stop responding at the KVM while SSH stays alive.
The root cause is a kernel `amdgpu` bug where the display-manager interrupt handler hogs
the CPU, stalling the `xfwm4` compositor:

```
workqueue: dm_irq_work_func [amdgpu] hogged CPU for >10000us N times, consider switching to WQ_UNBOUND
libEGL warning: DRI3 error: Could not get DRI3 device
```

### What the setup does about it

`assert/assert_xfce4.sh` delegates all GPU-freeze handling to **`assert/assert_amdgpu.sh`**,
an idempotent script run once the XFCE session is configured. It performs every action
short of a reboot, and only those still needed:

1. **Keeps `linux-firmware` current** (the highest-priority fix — outdated GPU firmware
   is the usual trigger). Skip with `--skip-firmware-update`.
2. **Forces `xfwm4 vblank_mode=xpresent` + `use_compositing=true`** (mitigation that reduces
   GPU contention; it does *not* by itself stop the IRQ hog).
3. **Optional last-resort kernel workaround** via `--amdgpu-dc-off` (see warning below).

When firmware or kernel parameters change, a **reboot** is required to load them; the script
prints the reboot command and the single post-reboot verification command and exits with
status `10`. `assert_xfce4.sh` also installs `assert_amdgpu.sh` and `recover_xfce_freeze.sh`
to `/usr/local/bin`, and supports `--suppress-volman-noise` for the benign KVM USB log spam.

You can run the GPU config standalone at any time:

```bash
bash ~/myenv/assert/assert_amdgpu.sh            # apply mitigations (idempotent)
bash ~/myenv/assert/assert_amdgpu.sh --Check    # diagnose only (no changes)
```

### Recovering a live freeze (no reboot)

From another machine over SSH (the desktop is frozen but SSH works):

```bash
ssh gxbrooks@lab3.lan "/usr/local/bin/recover_xfce_freeze.sh"
```

This disables compositing and restarts `xfwm4`, restoring input immediately. Once the GPU
fix is confirmed stable you can restore effects with `recover_xfce_freeze.sh --keep-compositor`
then re-enable compositing.

### Diagnosing

```bash
/usr/local/bin/assert_amdgpu.sh --Check       # or: bash ~/myenv/assert/assert_amdgpu.sh --Check
```

Reports the GPU/driver, installed vs. available `linux-firmware`, IRQ-hog count this boot,
`amdgpu.dc` kernel-parameter state, compositor settings, and DRI3 errors — and a verdict on
whether the freeze bug is active this boot.

### Last-resort kernel workaround (`amdgpu.dc=0`)

If freezes persist **after** a firmware update + reboot:

```bash
bash ~/myenv/assert/assert_amdgpu.sh --amdgpu-dc-off   # writes /etc/default/grub.d/99-myenv-amdgpu.cfg, runs update-grub
sudo reboot
```

> ⚠️ **Warning:** `amdgpu.dc=0` disables the AMD Display Core. This can disable HDMI/DP
> audio and reduce display capabilities, and on some Raphael/DCN units may result in **no
> display at boot**. Because Lab3 is reachable over SSH it is recoverable — revert with
> `bash ~/myenv/assert/assert_amdgpu.sh --amdgpu-dc-on && sudo reboot`. Use only as a last resort.

## Diagnose scripts (roles and overlap)

| Script | When to use | Installed to `/usr/local/bin`? |
|--------|-------------|--------------------------------|
| `assert/assert_amdgpu.sh` | **Setup + verify** AMD iGPU freeze mitigations (firmware, compositor, optional grub). `--Check` = health report. | Yes (by `assert_xfce4`) |
| `diagnose/recover_xfce_freeze.sh` | **Live freeze** — mouse dead at KVM, SSH works; disable compositor + restart xfwm4 (`--force` kills stuck xfwm4/GL). | Yes |
| `diagnose/escalate_xfce_freeze.sh` | **Escalation** — force recovery + X probe; restarts LightDM if sudo allows (no full reboot). | Yes |
| `diagnose/run_lab3_ui_recovery.sh` | **Lab1 driver** — SCP scripts to a lab host and run escalation (run from repo, not installed). | No |
| `diagnose/refresh_display_kvm.sh` | **Blank display** after KVM / headless boot; full xrandr/DRM/LightDM recovery (sudo). | Yes |
| `diagnose/refresh_display.sh` | **Login / session** — minimal `xrandr --auto`; used by `.xprofile` and autostart. | Yes (via `wake_on_kvm`) |
| `diagnose/wake_on_kvm.sh` | **Install-time** KVM persistence (sleep, USB wake, Xorg). Not for ad-hoc repair. | No (run from repo) |
| `diagnose/diagnose_hdmi_audio.sh` | **Wrong audio sink** after KVM; list sinks or `--set-hdmi`. | No (run from repo) |

### Simplification recommendations

1. **Keep `refresh_display.sh` and `refresh_display_kvm.sh` separate** — different scope (3-line login helper vs. 300-line SSH recovery). Overlap was reduced: `wake_on_kvm` no longer embeds a duplicate heredoc; it installs the repo's `diagnose/refresh_display.sh`.
2. **Do not merge `recover_xfce_freeze` into `refresh_display_kvm`** — freeze recovery targets a responsive-but-stuck compositor; KVM refresh targets a blank or undetected display.
3. **`assert_amdgpu --Check` is the post-reboot verifier** — no separate diagnose-only GPU script needed.
4. **Optional future trim**: install `diagnose_hdmi_audio.sh` to `/usr/local/bin` for parity, or fold `--set-hdmi` into a single `diagnose/kvm.sh` wrapper — not done now to avoid scope creep.
5. **`wake_on_kvm.sh` stays install-only** — run from `assert_xfce4`, not copied to `/usr/local/bin`; avoids two ways to apply the same system policy.

All diagnose scripts support `--help` / `-h` for usage and flags.

## Troubleshooting

### Display still blanks after KVM switch
- Check that `.xprofile` is being sourced: `cat ~/.xprofile`
- Verify xset commands: `xset q | grep DPMS`
- Ensure Xorg config exists: `ls /usr/share/X11/xorg.conf.d/10-monitor.conf`

### USB devices not waking system
- Check udev rule: `cat /etc/udev/rules.d/90-usb-wakeup.rules`
- List USB wakeup status: `grep . /sys/bus/usb/devices/*/power/wakeup`
- Reload udev: `sudo udevadm control --reload`

### System still auto-sleeping
- Check systemd inhibit: `systemd-inhibit --list`
- Verify masked targets: `systemctl status sleep.target`
- Check logs: `tail /var/log/wake_on_kvm.log`

## Logs

All operations are logged to:
```
/var/log/wake_on_kvm.log
```

## Maintenance

To update your configuration:

1. **Pull latest changes**:
   ```bash
   cd ~/myenv
   git pull
   ```

2. **Re-run desktop assert if needed**:
   ```bash
   bash assert/assert_xfce4.sh
   ```

3. **Log out and log back in** to apply X session changes

## Uninstallation

To remove these configurations:

1. **Delete symbolic links**:
   ```bash
   rm ~/.xprofile
   rm ~/.config/autostart
   rm ~/.xscreensaver
   ```

2. **Restore original configs** (if you had backups):
   ```bash
   mv ~/.xscreensaver.bak ~/.xscreensaver
   ```

3. **Remove system configurations** (optional):
   ```bash
   sudo rm /usr/share/X11/xorg.conf.d/10-monitor.conf
   sudo rm /etc/udev/rules.d/90-usb-wakeup.rules
   sudo rm /usr/local/bin/refresh_display.sh
   sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
   ```

## Version History

### V1.1 (Current)
- ✨ **Automated display manager switching** - No manual `dpkg-reconfigure` prompt
- ✨ **Automated session selection** - No manual gear icon clicking at login
- ✨ **Interactive restart prompt** - Choose reboot, DM restart, or skip
- 📝 Enhanced documentation with technical guides
- 🔧 Graceful vs instant blackout warnings
- ✅ Complete automation from fresh Ubuntu to XFCE4

### V1.0
- ✅ Initial stable release
- ✅ XFCE4 + LightDM installation
- ✅ KVM switch workarounds (display, USB, sleep)
- ✅ Symlink-based configuration management
- ✅ Idempotent scripts
- 📝 Comprehensive README

## License

[Specify your license here]

## Contributing

[Add contribution guidelines if applicable]

## Author

Gary Brooks

## Repository

- **GitHub**: https://github.com/gxbrooks/myenv
- **Latest Release**: V1.1
- **Issues**: https://github.com/gxbrooks/myenv/issues

