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
├── README.md                          # This file
├── assert_xfce4.sh                    # XFCE4/LightDM/KVM desktop assert (run via assert_myenv.sh or standalone)
├── wake_on_kvm.sh                     # KVM switch workarounds
├── .xprofile                          # X session startup (xset commands)
├── .xscreensaver                      # Screensaver config (glmatrix)
├── .bashrc                            # DEPRECATED (see warning in file)
├── autostart/
│   ├── xscreensaver.desktop           # Auto-start screensaver
│   ├── refresh-display.desktop        # Refresh display on login
│   └── disable-dpms.desktop.disabled  # Reference (not used)
└── tmp/
    ├── V1.0_COMMIT_SUMMARY.md         # V1.0 release notes
    ├── V1.1_COMMIT_SUMMARY.md         # V1.1 release notes
    ├── DISPLAY_MANAGER_AUTOMATION.md  # Technical details
    └── DISPLAY_MANAGER_RESTART.md     # Reboot vs restart guide
```

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
   bash assert_xfce4.sh
   ```
   
   The script will automatically:
   - Install XFCE4, LightDM, xdotool, and xscreensaver packages
   - **Switch to LightDM display manager** (no manual prompt!)
   - **Set XFCE4 as default session** (no manual selection needed!)
   - Create symbolic links from your home directory to repository config files
   - Run `wake_on_kvm.sh` to configure KVM switch workarounds
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

## How It Works

### assert_xfce4.sh

The desktop assert script performs all configuration automatically (also accepts `--Check` for dry-run and `--Debug`):

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
7. **Install refresh_display_kvm.sh** to `/usr/local/bin`
8. **Run wake_on_kvm.sh**: KVM switch workarounds (see below)
9. **Interactive Restart Prompt** (V1.1+, skipped when there is no TTY, `NONINTERACTIVE=1`, or `--Check`)
   - Option A: Reboot (graceful)
   - Option B: Restart display manager (fast)
   - Option S: Skip (manual later)

### wake_on_kvm.sh

This script performs system-level configuration (requires sudo):

1. **Systemd Inhibit**: Blocks automatic sleep/idle
2. **Screen Blanking**: Adds `xset` commands to `.xprofile`
3. **HDMI Config**: Creates Xorg monitor config to disable DPMS
4. **USB Wake**: Enables wake support for all USB devices + udev rule
5. **Sleep Targets**: Masks systemd sleep/suspend/hibernate targets
6. **Display Refresh**: Creates `/usr/local/bin/refresh_display.sh` script

### Autostart Applications

- **xscreensaver**: Starts screensaver daemon (uses glmatrix)
- **refresh-display**: Runs `xrandr --auto` to reinitialize display after login

## Idempotency

Both scripts are idempotent - safe to run multiple times:
- Checks if configurations already exist before applying
- Won't duplicate settings or break existing configurations
- Useful for updates or re-applying after system changes

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
   bash assert_xfce4.sh
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

