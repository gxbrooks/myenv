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

# Function to check if a package is installed
is_package_installed() {
    local pkg=$1
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

# Function to install a package
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

# Personal desktop applications
DESKTOP_PACKAGES=(cursor sublime-text google-chrome-stable terminator)

# Network diagnostic tools
NETWORK_PACKAGES=(nmap speedtest-cli)

# Combine all packages
ALL_PACKAGES=("${DESKTOP_PACKAGES[@]}" "${NETWORK_PACKAGES[@]}")

$DEBUG && echo "Debug   : Packages to check/install: ${ALL_PACKAGES[*]}"

# Track installation results
INSTALLED_COUNT=0
ALREADY_INSTALLED_COUNT=0
FAILED_COUNT=0

# Process each package
for pkg in "${ALL_PACKAGES[@]}"; do
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

# Summary
if $CHECK; then
    echo "Check   : Would install ${#ALL_PACKAGES[@]} package(s) if needed"
    echo "Result  : Check complete"
else
    if [[ $FAILED_COUNT -eq 0 ]]; then
        if [[ $INSTALLED_COUNT -gt 0 ]]; then
            echo "Result  : Successfully installed $INSTALLED_COUNT package(s), $ALREADY_INSTALLED_COUNT already installed"
        else
            echo "Result  : All ${#ALL_PACKAGES[@]} package(s) already installed"
        fi
    else
        echo "Error   : Failed to install $FAILED_COUNT package(s)"
        exit 1
    fi
fi

# Verify installations
if ! $CHECK; then
    echo ""
    echo "Info    : Verifying installations..."
    
    for pkg in "${ALL_PACKAGES[@]}"; do
        if is_package_installed "$pkg"; then
            $DEBUG && echo "Debug   : ✓ $pkg is installed"
        else
            echo "Warning : $pkg installation verification failed"
        fi
    done
fi

echo "Result  : MyEnv personal environment configured successfully"

