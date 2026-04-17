#!/bin/bash
#
# Assert MyEnv — apt repos, packages, and Cursor (AppImage).
# Idempotent. Invoked by assert_myenv.sh or run standalone.
#
# Usage: assert_packages.sh [--Debug|-d] [--Check|-c]

DEBUG=false
CHECK=false

script_name="$(basename "${BASH_SOURCE[0]}")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d) DEBUG=true ;;
        --Check|-c) CHECK=true ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." >&2
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c]" >&2
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Debug   : Starting: $script_name"
$DEBUG && echo "Debug   : script_dir = $script_dir"
$DEBUG && echo "Debug   : CHECK = $CHECK"

is_package_installed() {
    local pkg=$1
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

install_package() {
    local pkg=$1
    if is_package_installed "$pkg"; then
        $DEBUG && echo "Debug   : Package '$pkg' is already installed"
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would install package: $pkg"
        return 1
    fi
    echo "Info    : Installing package: $pkg"
    sudo apt update -qq
    sudo apt install -y "$pkg"
    if [[ $? -eq 0 ]]; then
        echo "Result  : Successfully installed $pkg"
        return 0
    fi
    echo "Error   : Failed to install $pkg"
    return 1
}

setup_external_repos() {
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

    if ! $CHECK; then
        $DEBUG && echo "Debug   : Running apt update after repo changes"
        sudo apt update -qq
    fi
}

install_cursor() {
    local install_dir="/opt/cursor"
    local binary_path="$install_dir/usr/share/cursor/cursor"
    local sandbox_path="$install_dir/usr/share/cursor/chrome-sandbox"
    local desktop_file="/usr/share/applications/cursor.desktop"
    local wrapper="/usr/local/bin/cursor"
    local icon_path="$install_dir/usr/share/cursor/resources/app/resources/linux/code.png"

    if [[ -f "$binary_path" ]]; then
        $DEBUG && echo "Debug   : Cursor already installed at $binary_path"
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would install Cursor (extracted AppImage) to $install_dir"
        return 1
    fi

    echo "Info    : Installing Cursor"

    if ! command -v curl &>/dev/null; then
        echo "Info    : Installing curl (required for Cursor download)"
        sudo apt install -y curl || {
            echo "Error   : Failed to install curl"
            return 1
        }
    fi

    if ! command -v jq &>/dev/null; then
        echo "Info    : Installing jq (required to parse Cursor download API)"
        sudo apt install -y jq || {
            echo "Error   : Failed to install jq"
            return 1
        }
    fi

    local api_url="https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable"
    $DEBUG && echo "Debug   : Fetching Cursor download URL from API"

    local download_url
    download_url=$(curl -fsSL "$api_url" | jq -r '.downloadUrl')

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        echo "Error   : Failed to resolve Cursor AppImage download URL from API"
        return 1
    fi

    $DEBUG && echo "Debug   : Cursor download URL: $download_url"

    local tmp_appimage
    tmp_appimage=$(mktemp /tmp/cursor_XXXXXX.AppImage)
    curl -fsSL -L "$download_url" -o "$tmp_appimage" || {
        echo "Error   : Failed to download Cursor AppImage"
        rm -f "$tmp_appimage"
        return 1
    }
    chmod +x "$tmp_appimage"

    echo "Info    : Extracting Cursor AppImage"
    local tmp_extract_dir
    tmp_extract_dir=$(mktemp -d /tmp/cursor_extract_XXXXXX)
    cd "$tmp_extract_dir" || return 1
    "$tmp_appimage" --appimage-extract > /dev/null 2>&1
    if [[ $? -ne 0 || ! -d "$tmp_extract_dir/squashfs-root" ]]; then
        echo "Error   : Failed to extract Cursor AppImage"
        rm -f "$tmp_appimage"
        rm -rf "$tmp_extract_dir"
        return 1
    fi

    sudo mkdir -p "$install_dir"
    sudo cp -r "$tmp_extract_dir/squashfs-root/." "$install_dir/"

    if [[ -f "$sandbox_path" ]]; then
        echo "Info    : Fixing chrome-sandbox permissions"
        sudo chown root:root "$sandbox_path"
        sudo chmod 4755 "$sandbox_path"
    else
        echo "Warning : chrome-sandbox not found at $sandbox_path — skipping"
    fi

    if [[ ! -f "$wrapper" ]]; then
        sudo tee "$wrapper" > /dev/null <<WRAPPER
#!/bin/bash
exec "$binary_path" "\$@"
WRAPPER
        sudo chmod +x "$wrapper"
    fi

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

    rm -f "$tmp_appimage"
    rm -rf "$tmp_extract_dir"

    echo "Result  : Successfully installed Cursor"
    return 0
}

EXTERNAL_REPO_PACKAGES=(sublime-text google-chrome-stable)
STANDARD_PACKAGES=(terminator gnome-keyring libsecret-1-0 seahorse gh openssh-client keychain okular xfce4-screenshooter)
NETWORK_PACKAGES=(nmap speedtest-cli)
ALL_APT_PACKAGES=("${EXTERNAL_REPO_PACKAGES[@]}" "${STANDARD_PACKAGES[@]}" "${NETWORK_PACKAGES[@]}")

$DEBUG && echo "Debug   : APT packages to check/install: ${ALL_APT_PACKAGES[*]}"

INSTALLED_COUNT=0
ALREADY_INSTALLED_COUNT=0
FAILED_COUNT=0
FAILED_STEPS=()

setup_external_repos

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
                FAILED_STEPS+=("apt:$pkg")
                echo "Warning : Installation failed for package '$pkg'"
            fi
        fi
    fi
done

if ! install_cursor; then
    if ! $CHECK; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_STEPS+=("tool:cursor")
        echo "Warning : Cursor installation step failed"
    fi
fi

if $CHECK; then
    echo "Check   : Would install packages/tools as needed (assert_packages)"
    echo "Result  : assert_packages check complete"
else
    if [[ $FAILED_COUNT -eq 0 ]]; then
        if [[ $INSTALLED_COUNT -gt 0 ]]; then
            echo "Result  : assert_packages: installed $INSTALLED_COUNT package(s), $ALREADY_INSTALLED_COUNT already present"
        else
            echo "Result  : assert_packages: all apt packages already installed"
        fi
    else
        echo "Error   : assert_packages: failed steps count: $FAILED_COUNT"
        [[ ${#FAILED_STEPS[@]} -gt 0 ]] && echo "Error   : assert_packages: failed steps: ${FAILED_STEPS[*]}"
        exit 1
    fi
fi

if ! $CHECK; then
    echo ""
    echo "Info    : Verifying package installations..."
    for pkg in "${ALL_APT_PACKAGES[@]}"; do
        if is_package_installed "$pkg"; then
            $DEBUG && echo "Debug   : ✓ $pkg is installed"
        else
            echo "Warning : $pkg installation verification failed"
        fi
    done
    if [[ -f /opt/cursor/usr/share/cursor/cursor ]]; then
        $DEBUG && echo "Debug   : ✓ cursor is installed"
    else
        echo "Warning : cursor installation verification failed"
    fi
fi

echo "Result  : assert_packages finished successfully"
exit 0
