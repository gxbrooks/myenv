#!/bin/bash
#
# Assert MyEnv — apt repos, packages, Cursor (AppImage), draw.io desktop (.deb),
# csdm-injector and context-variables (.deb via apt).
# Idempotent. Invoked by assert_myenv.sh or run standalone.
#
# Usage: assert_packages.sh [--Debug|-d] [--Check|-c]
#
# csdm-injector: ~/repos/csdm-injector (CSDM_INJECTOR_SRC / CSDM_INJECTOR_FORCE=1)
# context-variables: ~/repos/context-variables (CONTEXT_VARIABLES_SRC / CONTEXT_VARIABLES_FORCE=1)
#   → generate-contexts / vars-grid on PATH

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

# Check each apt package; install only when missing. Verbose groups print every item.
assert_apt_packages() {
    local verbose=$1
    shift
    local pkgs=("$@")
    local pkg

    for pkg in "${pkgs[@]}"; do
        if is_package_installed "$pkg"; then
            ALREADY_INSTALLED_COUNT=$((ALREADY_INSTALLED_COUNT + 1))
            if $verbose || $DEBUG; then
                echo "✓ $pkg is already installed"
            else
                $DEBUG && echo "Debug   : Package '$pkg' is already installed"
            fi
        else
            if $verbose; then
                echo "○ $pkg is not installed"
            fi
            if install_package "$pkg"; then
                INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
                if $verbose && ! $CHECK; then
                    echo "✓ $pkg installed"
                fi
            else
                if ! $CHECK; then
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    FAILED_STEPS+=("apt:$pkg")
                    echo "Warning : Installation failed for package '$pkg'"
                fi
            fi
        fi
    done
}

verify_docs_toolchain() {
    local cmd version

    echo ""
    echo "Info    : Verifying documentation toolchain commands..."
    for cmd in asciidoctor plantuml dot; do
        if command -v "$cmd" >/dev/null 2>&1; then
            case "$cmd" in
                asciidoctor) version="$(asciidoctor --version 2>&1 | head -1)" ;;
                plantuml) version="$(plantuml -version 2>&1 | head -1)" ;;
                dot) version="$(dot -V 2>&1 | head -1)" ;;
            esac
            echo "✓ $cmd — $version"
        else
            echo "Warning : $cmd not found in PATH"
            return 1
        fi
    done
    return 0
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

# Resolve headless Cursor CLI launcher (shell script), not the Electron binary.
# AppImage extract layout uses usr/share/cursor/bin/cursor; some installs use bin/cursor.
resolve_cursor_cli_script() {
    local candidate
    for candidate in \
        /opt/cursor/usr/share/cursor/bin/cursor \
        /opt/cursor/bin/cursor; do
        if [[ -x "$candidate" ]] && ! file "$candidate" 2>/dev/null | grep -q 'ELF'; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# /usr/local/bin/cursor must invoke bin/cursor (headless cli.js), not the Electron binary.
# Exec'ing the binary directly boots a GUI window for every --list-extensions / --install-extension call.
ensure_cursor_cli_wrapper() {
    local cli_script
    local wrapper="/usr/local/bin/cursor"

    if ! cli_script="$(resolve_cursor_cli_script)"; then
        $DEBUG && echo "Debug   : Cursor CLI script not found — skipping wrapper update"
        return 0
    fi

    if $CHECK; then
        if [[ ! -f "$wrapper" ]] || ! grep -qF "$cli_script" "$wrapper" 2>/dev/null; then
            echo "Check   : Would update $wrapper to exec headless Cursor CLI ($cli_script)"
        fi
        return 0
    fi

    if [[ -f "$wrapper" ]] && grep -qF "$cli_script" "$wrapper" 2>/dev/null; then
        $DEBUG && echo "Debug   : $wrapper already points to headless Cursor CLI"
        return 0
    fi

    echo "Info    : Updating $wrapper to use headless Cursor CLI ($cli_script)"
    sudo tee "$wrapper" > /dev/null <<WRAPPER
#!/bin/bash
exec "$cli_script" "\$@"
WRAPPER
    sudo chmod +x "$wrapper"
    echo "Result  : Cursor CLI wrapper updated (headless — no window per extension operation)"
}

install_cursor() {
    local install_dir="/opt/cursor"
    local binary_path="$install_dir/usr/share/cursor/cursor"
    local cli_script="$install_dir/bin/cursor"
    local sandbox_path="$install_dir/usr/share/cursor/chrome-sandbox"
    local desktop_file="/usr/share/applications/cursor.desktop"
    local wrapper="/usr/local/bin/cursor"
    local icon_path="$install_dir/usr/share/cursor/resources/app/resources/linux/code.png"

    if [[ -f "$binary_path" ]]; then
        $DEBUG && echo "Debug   : Cursor already installed at $binary_path"
        ensure_cursor_cli_wrapper
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
exec "$cli_script" "\$@"
WRAPPER
        sudo chmod +x "$wrapper"
    fi

    ensure_cursor_cli_wrapper

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

is_drawio_installed() {
    command -v drawio >/dev/null 2>&1
}

# draw.io desktop — official .deb from jgraph/drawio-desktop (not in Ubuntu apt).
# Provides /usr/bin/drawio for GUI editing and headless export (-x -f svg).
install_drawio() {
    if is_drawio_installed; then
        $DEBUG && echo "Debug   : draw.io desktop already installed ($(command -v drawio))"
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would install draw.io desktop (.deb from GitHub releases)"
        return 1
    fi

    echo "Info    : Installing draw.io desktop"

    if ! command -v curl &>/dev/null; then
        echo "Info    : Installing curl (required for draw.io download)"
        sudo apt install -y curl || {
            echo "Error   : Failed to install curl"
            return 1
        }
    fi

    if ! command -v jq &>/dev/null; then
        echo "Info    : Installing jq (required to parse draw.io release API)"
        sudo apt install -y jq || {
            echo "Error   : Failed to install jq"
            return 1
        }
    fi

    local api_url="https://api.github.com/repos/jgraph/drawio-desktop/releases/latest"
    $DEBUG && echo "Debug   : Fetching draw.io release from GitHub API"

    local deb_url deb_name
    deb_url=$(curl -fsSL "$api_url" | jq -r '.assets[] | select(.name | test("^drawio-amd64-.*\\.deb$")) | .browser_download_url' | head -1)
    deb_name=$(basename "$deb_url")

    if [[ -z "$deb_url" || "$deb_url" == "null" ]]; then
        echo "Error   : Failed to resolve draw.io .deb download URL from GitHub releases"
        return 1
    fi

    $DEBUG && echo "Debug   : draw.io download URL: $deb_url"

    local tmp_deb
    tmp_deb=$(mktemp /tmp/drawio_XXXXXX.deb)
    curl -fsSL -L "$deb_url" -o "$tmp_deb" || {
        echo "Error   : Failed to download draw.io .deb"
        rm -f "$tmp_deb"
        return 1
    }

    echo "Info    : Installing $deb_name"
    sudo apt install -y "$tmp_deb" || {
        echo "Error   : Failed to install draw.io desktop package"
        rm -f "$tmp_deb"
        return 1
    }
    rm -f "$tmp_deb"

    if is_drawio_installed; then
        echo "Result  : Successfully installed draw.io desktop ($deb_name)"
        return 0
    fi

    echo "Error   : draw.io package installed but drawio command not found in PATH"
    return 1
}

is_csdm_injector_installed() {
    is_package_installed csdm-injector && command -v csdm-inject >/dev/null 2>&1
}

# Resolve csdm-injector git checkout (build-deb.sh source tree).
resolve_csdm_injector_src() {
    local myenv_root candidate
    myenv_root="$(cd "$script_dir/.." && pwd)"
    local candidates=(
        "${CSDM_INJECTOR_SRC:-}"
        "${HOME}/repos/csdm-injector"
        "$(cd "${myenv_root}/.." && pwd)/csdm-injector"
    )
    for candidate in "${candidates[@]}"; do
        [[ -z "$candidate" ]] && continue
        if [[ -f "${candidate}/packaging/build-deb.sh" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

ensure_csdm_injector_src() {
    local src
    if src="$(resolve_csdm_injector_src)"; then
        echo "$src"
        return 0
    fi

    local dest="${HOME}/repos/csdm-injector"
    if $CHECK; then
        echo "Check   : Would clone https://github.com/gxbrooks/csdm-injector.git → $dest" >&2
        return 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "Error   : git is required to clone csdm-injector" >&2
        return 1
    fi

    mkdir -p "$(dirname "$dest")"
    echo "Info    : Cloning csdm-injector into $dest" >&2
    if git clone --depth 1 https://github.com/gxbrooks/csdm-injector.git "$dest"; then
        echo "$dest"
        return 0
    fi
    echo "Error   : Failed to clone csdm-injector (try SSH or set CSDM_INJECTOR_SRC)" >&2
    return 1
}

# csdm-injector — build local .deb (packaging/build-deb.sh) and install via apt.
# Not in Ubuntu archives; same pattern as draw.io (local .deb → apt install).
install_csdm_injector() {
    if is_csdm_injector_installed && [[ "${CSDM_INJECTOR_FORCE:-0}" != "1" ]]; then
        local ver
        ver="$(dpkg-query -W -f='${Version}' csdm-injector 2>/dev/null || echo '?')"
        if $CHECK; then
            echo "Check   : csdm-injector already installed ($ver); would rebuild if CSDM_INJECTOR_FORCE=1"
        else
            $DEBUG && echo "Debug   : csdm-injector already installed ($ver)"
            echo "✓ csdm-injector is already installed ($ver)"
        fi
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would build and apt-install csdm-injector .deb from source checkout"
        return 1
    fi

    echo "Info    : Installing csdm-injector (Debian package via apt)"

    local build_deps=(python3 python3-venv python3-pip rsync dpkg-dev fakeroot)
    local dep
    for dep in "${build_deps[@]}"; do
        if ! is_package_installed "$dep"; then
            echo "Info    : Installing build dependency: $dep"
            sudo apt update -qq
            sudo apt install -y "$dep" || {
                echo "Error   : Failed to install build dependency $dep"
                return 1
            }
        fi
    done

    # ensurepip often needs the versioned venv package (e.g. python3.12-venv).
    local py_minor
    py_minor="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
    if [[ -n "$py_minor" ]] && ! python3 -c 'import ensurepip' >/dev/null 2>&1; then
        echo "Info    : Installing python${py_minor}-venv (ensurepip)"
        sudo apt install -y "python${py_minor}-venv" || true
    fi

    local src
    if ! src="$(ensure_csdm_injector_src)"; then
        return 1
    fi
    $DEBUG && echo "Debug   : csdm-injector source: $src"

    echo "Info    : Building csdm-injector .deb (./packaging/build-deb.sh)"
    if ! (cd "$src" && ./packaging/build-deb.sh); then
        echo "Error   : Failed to build csdm-injector .deb"
        return 1
    fi

    local deb
    deb="$(ls -1t "$src"/dist/csdm-injector_*_all.deb 2>/dev/null | head -1 || true)"
    if [[ -z "$deb" || ! -f "$deb" ]]; then
        echo "Error   : No csdm-injector_*.deb found under $src/dist"
        return 1
    fi

    # Copy to /tmp so apt's _apt user can read the archive (avoids $HOME sandbox note).
    local tmp_deb
    tmp_deb="$(mktemp /tmp/csdm-injector_XXXXXX.deb)"
    cp -f "$deb" "$tmp_deb"

    # Drop legacy install.sh symlinks that would shadow /usr/bin wrappers.
    sudo rm -f /usr/local/bin/csdm-inject /usr/local/bin/csdm-delete \
        /usr/local/bin/csdm-diff /usr/local/bin/csdm-validate

    echo "Info    : apt install $(basename "$deb")"
    if ! sudo apt install -y "$tmp_deb"; then
        echo "Error   : Failed to apt-install csdm-injector"
        rm -f "$tmp_deb"
        return 1
    fi
    rm -f "$tmp_deb"

    if is_csdm_injector_installed; then
        echo "Result  : Successfully installed csdm-injector ($(dpkg-query -W -f='${Version}' csdm-injector))"
        return 0
    fi
    echo "Error   : csdm-injector package installed but csdm-inject not on PATH"
    return 1
}

is_context_variables_installed() {
    is_package_installed context-variables && command -v generate-contexts >/dev/null 2>&1
}

resolve_context_variables_src() {
    local myenv_root candidate
    myenv_root="$(cd "$script_dir/.." && pwd)"
    local candidates=(
        "${CONTEXT_VARIABLES_SRC:-}"
        "${HOME}/repos/context-variables"
        "$(cd "${myenv_root}/.." && pwd)/context-variables"
    )
    for candidate in "${candidates[@]}"; do
        [[ -z "$candidate" ]] && continue
        if [[ -f "${candidate}/packaging/build-deb.sh" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

ensure_context_variables_src() {
    local src
    if src="$(resolve_context_variables_src)"; then
        echo "$src"
        return 0
    fi

    local dest="${HOME}/repos/context-variables"
    if $CHECK; then
        echo "Check   : Would clone https://github.com/gxbrooks/context-variables.git → $dest" >&2
        return 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "Error   : git is required to clone context-variables" >&2
        return 1
    fi

    mkdir -p "$(dirname "$dest")"
    echo "Info    : Cloning context-variables into $dest" >&2
    if git clone --depth 1 https://github.com/gxbrooks/context-variables.git "$dest"; then
        echo "$dest"
        return 0
    fi
    echo "Error   : Failed to clone context-variables (or set CONTEXT_VARIABLES_SRC)" >&2
    return 1
}

# context-variables — build local .deb and install via apt (generate-contexts / vars-grid).
install_context_variables() {
    if is_context_variables_installed && [[ "${CONTEXT_VARIABLES_FORCE:-0}" != "1" ]]; then
        local ver
        ver="$(dpkg-query -W -f='${Version}' context-variables 2>/dev/null || echo '?')"
        if $CHECK; then
            echo "Check   : context-variables already installed ($ver); would rebuild if CONTEXT_VARIABLES_FORCE=1"
        else
            $DEBUG && echo "Debug   : context-variables already installed ($ver)"
            echo "✓ context-variables is already installed ($ver)"
        fi
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would build and apt-install context-variables .deb from source checkout"
        return 1
    fi

    echo "Info    : Installing context-variables (Debian package via apt)"

    local build_deps=(python3 python3-venv python3-pip python3-yaml rsync dpkg-dev fakeroot)
    local dep
    for dep in "${build_deps[@]}"; do
        if ! is_package_installed "$dep"; then
            echo "Info    : Installing build dependency: $dep"
            sudo apt update -qq
            sudo apt install -y "$dep" || {
                echo "Error   : Failed to install build dependency $dep"
                return 1
            }
        fi
    done

    local py_minor
    py_minor="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
    if [[ -n "$py_minor" ]] && ! python3 -c 'import ensurepip' >/dev/null 2>&1; then
        echo "Info    : Installing python${py_minor}-venv (ensurepip)"
        sudo apt install -y "python${py_minor}-venv" || true
    fi

    local src
    if ! src="$(ensure_context_variables_src)"; then
        return 1
    fi
    $DEBUG && echo "Debug   : context-variables source: $src"

    echo "Info    : Building context-variables .deb (./packaging/build-deb.sh)"
    if ! (cd "$src" && ./packaging/build-deb.sh); then
        echo "Error   : Failed to build context-variables .deb"
        return 1
    fi

    local deb
    deb="$(ls -1t "$src"/dist/context-variables_*_all.deb 2>/dev/null | head -1 || true)"
    if [[ -z "$deb" || ! -f "$deb" ]]; then
        echo "Error   : No context-variables_*.deb found under $src/dist"
        return 1
    fi

    local tmp_deb
    tmp_deb="$(mktemp /tmp/context-variables_XXXXXX.deb)"
    cp -f "$deb" "$tmp_deb"

    sudo rm -f /usr/local/bin/generate-contexts /usr/local/bin/vars-grid

    echo "Info    : apt install $(basename "$deb")"
    if ! sudo apt install -y "$tmp_deb"; then
        echo "Error   : Failed to apt-install context-variables"
        rm -f "$tmp_deb"
        return 1
    fi
    rm -f "$tmp_deb"

    if is_context_variables_installed; then
        echo "Result  : Successfully installed context-variables ($(dpkg-query -W -f='${Version}' context-variables))"
        return 0
    fi
    echo "Error   : context-variables package installed but generate-contexts not on PATH"
    return 1
}

# Ensure Debian x-terminal-emulator alternative points at kitty (XFCE helpers use it).
ensure_kitty_default_terminal() {
    local kitty_bin="/usr/bin/kitty"

    if $CHECK; then
        if [[ -x "$kitty_bin" ]]; then
            local current
            current=$(readlink -f /etc/alternatives/x-terminal-emulator 2>/dev/null || true)
            if [[ "$current" == "$kitty_bin" ]]; then
                echo "Check   : x-terminal-emulator already resolves to kitty"
            else
                echo "Check   : Would run: sudo update-alternatives --set x-terminal-emulator $kitty_bin"
            fi
        else
            echo "Check   : Would set x-terminal-emulator to kitty after the kitty package is installed"
        fi
        return 0
    fi

    if [[ ! -x "$kitty_bin" ]]; then
        echo "Warning : kitty not found at $kitty_bin; cannot set default terminal"
        return 1
    fi

    local current
    current=$(readlink -f /etc/alternatives/x-terminal-emulator 2>/dev/null || true)
    if [[ "$current" == "$kitty_bin" ]]; then
        $DEBUG && echo "Debug   : x-terminal-emulator already resolves to kitty"
        echo "Result  : Default terminal (x-terminal-emulator) is already kitty"
        return 0
    fi

    echo "Info    : Setting default terminal to kitty (update-alternatives x-terminal-emulator)"
    if sudo update-alternatives --set x-terminal-emulator "$kitty_bin"; then
        echo "Result  : Default terminal set to kitty"
        return 0
    fi
    echo "Warning : Could not set x-terminal-emulator to kitty (update-alternatives failed)"
    return 1
}

EXTERNAL_REPO_PACKAGES=(sublime-text google-chrome-stable)
STANDARD_PACKAGES=(kitty kitty-terminfo gnome-keyring libsecret-1-0 seahorse gh openssh-client keychain okular xfce4-screenshooter libreoffice)
DOCS_PACKAGES=(asciidoctor ruby-rubygems graphviz plantuml)
NETWORK_PACKAGES=(nmap speedtest-cli)
ALL_APT_PACKAGES=("${EXTERNAL_REPO_PACKAGES[@]}" "${STANDARD_PACKAGES[@]}" "${DOCS_PACKAGES[@]}" "${NETWORK_PACKAGES[@]}")

$DEBUG && echo "Debug   : APT packages to check/install: ${ALL_APT_PACKAGES[*]}"

INSTALLED_COUNT=0
ALREADY_INSTALLED_COUNT=0
FAILED_COUNT=0
FAILED_STEPS=()

setup_external_repos

echo ""
echo "📄 AsciiDoc / documentation toolchain (apt)..."
assert_apt_packages true "${DOCS_PACKAGES[@]}"

echo ""
echo "Info    : Checking remaining apt packages..."
assert_apt_packages false "${EXTERNAL_REPO_PACKAGES[@]}" "${STANDARD_PACKAGES[@]}" "${NETWORK_PACKAGES[@]}"

if ! install_cursor; then
    if ! $CHECK; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_STEPS+=("tool:cursor")
        echo "Warning : Cursor installation step failed"
    fi
else
    ensure_cursor_cli_wrapper
fi

if ! install_drawio; then
    if ! $CHECK; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_STEPS+=("tool:drawio")
        echo "Warning : draw.io desktop installation step failed"
    fi
fi

if ! install_csdm_injector; then
    if ! $CHECK; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_STEPS+=("tool:csdm-injector")
        echo "Warning : csdm-injector installation step failed"
    fi
fi

if ! install_context_variables; then
    if ! $CHECK; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_STEPS+=("tool:context-variables")
        echo "Warning : context-variables installation step failed"
    fi
fi

ensure_kitty_default_terminal || true

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
    verify_docs_toolchain || true
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
    if is_drawio_installed; then
        $DEBUG && echo "Debug   : ✓ drawio is installed ($(drawio --version 2>&1 | head -1 || echo 'drawio'))"
    else
        echo "Warning : draw.io desktop (drawio) installation verification failed"
    fi
    if is_csdm_injector_installed; then
        $DEBUG && echo "Debug   : ✓ csdm-injector is installed ($(dpkg-query -W -f='${Version}' csdm-injector) → $(command -v csdm-inject))"
    else
        echo "Warning : csdm-injector (csdm-inject) installation verification failed"
    fi
    if is_context_variables_installed; then
        $DEBUG && echo "Debug   : ✓ context-variables is installed ($(dpkg-query -W -f='${Version}' context-variables) → $(command -v generate-contexts))"
    else
        echo "Warning : context-variables (generate-contexts) installation verification failed"
    fi
    if [[ -x /usr/bin/kitty ]]; then
        cur=$(readlink -f /etc/alternatives/x-terminal-emulator 2>/dev/null || true)
        if [[ "$cur" == "/usr/bin/kitty" ]]; then
            $DEBUG && echo "Debug   : ✓ x-terminal-emulator is kitty"
        else
            echo "Warning : x-terminal-emulator is not kitty (currently: ${cur:-unknown})"
        fi
    fi
fi

echo "Result  : assert_packages finished successfully"
exit 0
