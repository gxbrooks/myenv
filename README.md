# myenv - KVM-Friendly Ubuntu Desktop Environment

## Overview

This project configures an Ubuntu mini-PC to work reliably with KVM (Keyboard-Video-Mouse) switches by preventing common issues like screen blanking, display disconnection, and USB device sleep.

## Problem Statement

When using KVM switches with Ubuntu systems, several issues commonly occur:
- **Display Disconnection**: Monitors go blank or lose signal when the KVM switches away
- **Screen Blanking**: DPMS (Display Power Management Signaling) turns off the display
- **USB Wake Issues**: Keyboard and mouse don't wake the system after switching back
- **Auto-Sleep**: System may enter sleep/suspend mode when not actively in use

## Solution

This project provides a complete XFCE4 desktop environment configuration with KVM switch workarounds:

### Environment Modifications

1. **XFCE4 Desktop**: Installs a lightweight, stable desktop environment
2. **Display Persistence**: 
   - Disables DPMS video shutdown
   - Prevents screen blanking
   - Forces HDMI output to stay active
   - Auto-refreshes display on login (for KVM switches)
3. **USB Wake Support**:
   - Enables wakeup for all USB devices
   - Creates persistent udev rules
4. **Sleep Prevention**:
   - Blocks automatic system sleep
   - Masks systemd sleep targets
   - Allows manual suspend when needed
5. **Screensaver**: Configures xscreensaver with `glmatrix` theme

### Repository Structure

```
myenv/
├── README.md                    # This file
├── setup_xfce4.sh              # Main setup script
├── wake_on_kvm.sh              # KVM switch workarounds
├── .xprofile                   # X session startup (xset commands)
├── .xscreensaver               # Screensaver config (glmatrix)
├── .bashrc                     # DEPRECATED (see warning in file)
└── autostart/
    ├── xscreensaver.desktop           # Auto-start screensaver
    ├── refresh-display.desktop        # Refresh display on login
    └── disable-dpms.desktop.disabled  # Reference (not used)
```

## Installation

### Prerequisites

- Ubuntu system (tested on Ubuntu mini-PC)
- Sudo privileges
- Git (to clone this repository)

### Setup Instructions

1. **Clone or place this repository** in your home directory:
   ```bash
   git clone <repo-url> ~/myenv
   cd ~/myenv
   ```

2. **Run the setup script**:
   ```bash
   bash setup_xfce4.sh
   ```
   
   This script will:
   - Install XFCE4, LightDM, xdotool, and xscreensaver packages
   - Create symbolic links from your home directory to repository config files
   - Run `wake_on_kvm.sh` to configure KVM switch workarounds
   - Set up autostart entries for display refresh and screensaver

3. **Log out and log back in** to activate the XFCE4 desktop environment

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

2. **Re-run setup if needed**:
   ```bash
   bash setup_xfce4.sh
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

## License

[Specify your license here]

## Contributing

[Add contribution guidelines if applicable]

## Author

Gary Brooks

