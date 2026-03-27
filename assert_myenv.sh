#!/bin/bash

# Assert MyEnv Personal Environment
#
# Ensures all personal development tools and applications are installed.
# This includes IDEs, browsers, terminal emulators, and diagnostic tools.
#
# This script is idempotent and can be run multiple times safely.

# Parse arguments
DEBUG=false
CHECK=false

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
git_assert_script="$script_dir/assert_git.sh"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d)
            DEBUG=true
            ;;
        --Check|-c)
            CHECK=true
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Debug   : Starting: $script_name"
$DEBUG && echo "Debug   : script_dir = $script_dir"
$DEBUG && echo "Debug   : CHECK = $CHECK"
$DEBUG && echo "Debug   : DEBUG = $DEBUG"

# ─────────────────────────────────────────────────────────────────────────────
# Helper: check if an apt package is installed
# ─────────────────────────────────────────────────────────────────────────────
is_package_installed() {
    local pkg=$1
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: install a standard apt package
# ─────────────────────────────────────────────────────────────────────────────
install_package() {
    local pkg=$1
    if is_package_installed "$pkg"; then
        $DEBUG && echo "Debug   : Package '$pkg' is already installed"
        return 0
    fi
    
    if $CHECK; then
        echo "Check   : Would install package: $pkg"
        return 1
    else
        echo "Info    : Installing package: $pkg"
        sudo apt update -qq
        sudo apt install -y "$pkg"
        if [[ $? -eq 0 ]]; then
            echo "Result  : Successfully installed $pkg"
            return 0
        else
            echo "Error   : Failed to install $pkg"
            return 1
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Setup: add external apt repositories that are not in Ubuntu's default repos
# ─────────────────────────────────────────────────────────────────────────────
setup_external_repos() {
    # ── Sublime Text ──────────────────────────────────────────────────────────
    if [[ ! -f /etc/apt/sources.list.d/sublime-text.list ]]; then
        if $CHECK; then
            echo "Check   : Would add Sublime Text apt repository"
        else
            echo "Info    : Adding Sublime Text apt repository"
            wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg \
                | gpg --dearmor \
                | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null
            echo "deb https://download.sublimetext.com/ apt/stable/" \
                | sudo tee /etc/apt/sources.list.d/sublime-text.list > /dev/null
            echo "Result  : Sublime Text repository added"
        fi
    else
        $DEBUG && echo "Debug   : Sublime Text repository already configured"
    fi

    # ── Google Chrome ─────────────────────────────────────────────────────────
    if [[ ! -f /etc/apt/sources.list.d/google-chrome.list ]]; then
        if $CHECK; then
            echo "Check   : Would add Google Chrome apt repository"
        else
            echo "Info    : Adding Google Chrome apt repository"
            wget -qO - https://dl.google.com/linux/linux_signing_key.pub \
                | gpg --dearmor \
                | sudo tee /etc/apt/trusted.gpg.d/google-chrome.gpg > /dev/null
            echo "deb [arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main" \
                | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
            echo "Result  : Google Chrome repository added"
        fi
    else
        $DEBUG && echo "Debug   : Google Chrome repository already configured"
    fi

    # Refresh apt after adding new repos (skip if check-only)
    if ! $CHECK; then
        $DEBUG && echo "Debug   : Running apt update after repo changes"
        sudo apt update -qq
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Setup: install Cursor via AppImage (not available in any apt repository)
# ─────────────────────────────────────────────────────────────────────────────
install_cursor() {
    local install_dir="/opt/cursor"
    local binary_path="$install_dir/usr/share/cursor/cursor"
    local sandbox_path="$install_dir/usr/share/cursor/chrome-sandbox"
    local desktop_file="/usr/share/applications/cursor.desktop"
    local wrapper="/usr/local/bin/cursor"
    local icon_path="$install_dir/usr/share/cursor/resources/app/resources/linux/code.png"

    # Consider Cursor installed if the extracted binary is already in place
    if [[ -f "$binary_path" ]]; then
        $DEBUG && echo "Debug   : Cursor already installed at $binary_path"
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would install Cursor (extracted AppImage) to $install_dir"
        return 1
    fi

    echo "Info    : Installing Cursor"

    # Ensure curl is available
    if ! command -v curl &>/dev/null; then
        echo "Info    : Installing curl (required for Cursor download)"
        sudo apt install -y curl
        if [[ $? -ne 0 ]]; then
            echo "Error   : Failed to install curl"
            return 1
        fi
    fi

    # Ensure jq is available for parsing the download API response
    if ! command -v jq &>/dev/null; then
        echo "Info    : Installing jq (required to parse Cursor download API)"
        sudo apt install -y jq
        if [[ $? -ne 0 ]]; then
            echo "Error   : Failed to install jq"
            return 1
        fi
    fi

    # Resolve the AppImage URL from Cursor's download API
    local api_url="https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable"
    $DEBUG && echo "Debug   : Fetching Cursor download URL from API"

    local download_url
    download_url=$(curl -fsSL "$api_url" | jq -r '.downloadUrl')

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        echo "Error   : Failed to resolve Cursor AppImage download URL from API"
        return 1
    fi

    $DEBUG && echo "Debug   : Cursor download URL: $download_url"

    # Download the AppImage to a temp location
    local tmp_appimage
    tmp_appimage=$(mktemp /tmp/cursor_XXXXXX.AppImage)
    curl -fsSL -L "$download_url" -o "$tmp_appimage"
    if [[ $? -ne 0 ]]; then
        echo "Error   : Failed to download Cursor AppImage"
        rm -f "$tmp_appimage"
        return 1
    fi
    chmod +x "$tmp_appimage"

    # Extract the AppImage — this avoids all FUSE/libfuse2 dependency issues
    # and gives us a proper directory we can fix chrome-sandbox permissions on
    echo "Info    : Extracting Cursor AppImage"
    local tmp_extract_dir
    tmp_extract_dir=$(mktemp -d /tmp/cursor_extract_XXXXXX)
    cd "$tmp_extract_dir"
    "$tmp_appimage" --appimage-extract > /dev/null 2>&1
    if [[ $? -ne 0 || ! -d "$tmp_extract_dir/squashfs-root" ]]; then
        echo "Error   : Failed to extract Cursor AppImage"
        rm -f "$tmp_appimage"
        rm -rf "$tmp_extract_dir"
        return 1
    fi

    # Move extracted files to the install directory
    sudo mkdir -p "$install_dir"
    sudo cp -r "$tmp_extract_dir/squashfs-root/." "$install_dir/"

    # Fix chrome-sandbox permissions — this is the root cause of the sandbox
    # errors on Ubuntu 24.04. The binary must be owned by root with SUID (4755)
    # so that Electron can use it for process isolation.
    if [[ -f "$sandbox_path" ]]; then
        echo "Info    : Fixing chrome-sandbox permissions"
        sudo chown root:root "$sandbox_path"
        sudo chmod 4755 "$sandbox_path"
    else
        echo "Warning : chrome-sandbox not found at $sandbox_path — skipping"
    fi

    # Create a wrapper script on PATH that launches the extracted binary
    if [[ ! -f "$wrapper" ]]; then
        sudo tee "$wrapper" > /dev/null <<WRAPPER
#!/bin/bash
exec "$binary_path" "\$@"
WRAPPER
        sudo chmod +x "$wrapper"
    fi

    # Create a .desktop launcher for the application menu
    if [[ ! -f "$desktop_file" ]]; then
        local icon_arg="$icon_path"
        [[ ! -f "$icon_path" ]] && icon_arg="utilities-terminal"
        sudo tee "$desktop_file" > /dev/null <<DESKTOP
[Desktop Entry]
Name=Cursor
Exec=$binary_path %U
Terminal=false
Type=Application
Icon=$icon_arg
StartupWMClass=Cursor
Comment=Cursor AI Code Editor
Categories=Development;IDE;
DESKTOP
        sudo update-desktop-database 2>/dev/null || true
    fi

    # Clean up temp files
    rm -f "$tmp_appimage"
    rm -rf "$tmp_extract_dir"

    echo "Result  : Successfully installed Cursor"
    return 0
}
# ─────────────────────────────────────────────────────────────────────────────
# Package lists
# ─────────────────────────────────────────────────────────────────────────────

# Packages that require external repos (added above in setup_external_repos)
EXTERNAL_REPO_PACKAGES=(sublime-text google-chrome-stable)

# Standard apt packages (available in Ubuntu's default repositories)
# Include keyring components so Electron apps (Cursor, Chrome, etc.) can use
# Secret Service instead of falling back to plaintext credential storage.
STANDARD_PACKAGES=(terminator gnome-keyring libsecret-1-0 seahorse)

# Network diagnostic tools
NETWORK_PACKAGES=(nmap speedtest-cli)

# Combine all standard apt packages
ALL_APT_PACKAGES=("${EXTERNAL_REPO_PACKAGES[@]}" "${STANDARD_PACKAGES[@]}" "${NETWORK_PACKAGES[@]}")

$DEBUG && echo "Debug   : APT packages to check/install: ${ALL_APT_PACKAGES[*]}"
$DEBUG && echo "Debug   : Custom installs: cursor (AppImage)"

# ─────────────────────────────────────────────────────────────────────────────
# Main installation flow
# ─────────────────────────────────────────────────────────────────────────────

# Step 1: Add external apt repositories before attempting to install from them
setup_external_repos

# Step 2: Install all apt packages
INSTALLED_COUNT=0
ALREADY_INSTALLED_COUNT=0
FAILED_COUNT=0

for pkg in "${ALL_APT_PACKAGES[@]}"; do
    if is_package_installed "$pkg"; then
        ALREADY_INSTALLED_COUNT=$((ALREADY_INSTALLED_COUNT + 1))
        $DEBUG && echo "Debug   : Package '$pkg' is already installed"
    else
        if install_package "$pkg"; then
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
        else
            if ! $CHECK; then
                FAILED_COUNT=$((FAILED_COUNT + 1))
            fi
        fi
    fi
done

# Step 3: Install Cursor via AppImage
if ! install_cursor; then
    if ! $CHECK; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
fi

# Step 4: Assert git global identity configuration
git_assert_args=()
$DEBUG && git_assert_args+=("--Debug")
$CHECK && git_assert_args+=("--Check")

if [[ -x "$git_assert_script" ]]; then
    if ! "$git_assert_script" "${git_assert_args[@]}"; then
        if ! $CHECK; then
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    fi
else
    echo "Warning : Git assert script not found or not executable: $git_assert_script"
    if ! $CHECK; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
if $CHECK; then
    echo "Check   : Would install packages/tools as needed"
    echo "Result  : Check complete"
else
    if [[ $FAILED_COUNT -eq 0 ]]; then
        if [[ $INSTALLED_COUNT -gt 0 ]]; then
            echo "Result  : Successfully installed $INSTALLED_COUNT package(s), $ALREADY_INSTALLED_COUNT already installed"
        else
            echo "Result  : All packages already installed"
        fi
    else
        echo "Error   : Failed to install $FAILED_COUNT package(s)/tool(s)"
        exit 1
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Verify installations
# ─────────────────────────────────────────────────────────────────────────────
if ! $CHECK; then
    echo ""
    echo "Info    : Verifying installations..."

    for pkg in "${ALL_APT_PACKAGES[@]}"; do
        if is_package_installed "$pkg"; then
            $DEBUG && echo "Debug   : ✓ $pkg is installed"
        else
            echo "Warning : $pkg installation verification failed"
        fi
    done

    # Verify Cursor separately (extracted binary, not an apt package)
    if [[ -f /opt/cursor/usr/share/cursor/cursor ]]; then
        $DEBUG && echo "Debug   : ✓ cursor is installed"
    else
        echo "Warning : cursor installation verification failed"
    fi
fi

echo "Result  : MyEnv personal environment configured successfully"
