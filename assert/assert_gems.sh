#!/bin/bash
#
# Assert MyEnv — Ruby gems for documentation tooling (AsciiDoctor PDF/diagram).
# Idempotent. Invoked by assert_myenv.sh or run standalone.
#
# Usage: assert_gems.sh [--Debug|-d] [--Check|-c]

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

is_gem_installed() {
    local gem_name=$1
    gem list -i "$gem_name" >/dev/null 2>&1
}

install_gem() {
    local gem_name=$1
    if is_gem_installed "$gem_name"; then
        $DEBUG && echo "Debug   : Gem '$gem_name' is already installed"
        return 0
    fi

    if $CHECK; then
        echo "Check   : Would install gem: $gem_name"
        return 1
    fi

    if ! command -v gem >/dev/null 2>&1; then
        echo "Error   : gem command not found; install ruby-rubygems via assert_packages.sh"
        return 1
    fi

    echo "Info    : Installing gem: $gem_name"
    if sudo gem install "$gem_name"; then
        echo "Result  : Successfully installed gem $gem_name"
        return 0
    fi
    echo "Error   : Failed to install gem $gem_name"
    return 1
}

GEM_PACKAGES=(asciidoctor-pdf asciidoctor-diagram)

$DEBUG && echo "Debug   : Ruby gems to check/install: ${GEM_PACKAGES[*]}"

INSTALLED_COUNT=0
ALREADY_INSTALLED_COUNT=0
FAILED_COUNT=0
FAILED_STEPS=()

if ! command -v gem >/dev/null 2>&1; then
    if $CHECK; then
        echo "Check   : Would require gem (ruby-rubygems) before installing: ${GEM_PACKAGES[*]}"
        echo "Result  : assert_gems check complete"
        exit 0
    fi
    echo "Error   : gem command not found; run assert_packages.sh first (ruby-rubygems)"
    exit 1
fi

for gem_name in "${GEM_PACKAGES[@]}"; do
    if is_gem_installed "$gem_name"; then
        ALREADY_INSTALLED_COUNT=$((ALREADY_INSTALLED_COUNT + 1))
        $DEBUG && echo "Debug   : Gem '$gem_name' is already installed"
    else
        if install_gem "$gem_name"; then
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
        else
            if ! $CHECK; then
                FAILED_COUNT=$((FAILED_COUNT + 1))
                FAILED_STEPS+=("gem:$gem_name")
                echo "Warning : Installation failed for gem '$gem_name'"
            fi
        fi
    fi
done

if $CHECK; then
    echo "Check   : Would install gems as needed (assert_gems)"
    echo "Result  : assert_gems check complete"
else
    if [[ $FAILED_COUNT -eq 0 ]]; then
        if [[ $INSTALLED_COUNT -gt 0 ]]; then
            echo "Result  : assert_gems: installed $INSTALLED_COUNT gem(s), $ALREADY_INSTALLED_COUNT already present"
        else
            echo "Result  : assert_gems: all gems already installed"
        fi
    else
        echo "Error   : assert_gems: failed steps count: $FAILED_COUNT"
        [[ ${#FAILED_STEPS[@]} -gt 0 ]] && echo "Error   : assert_gems: failed steps: ${FAILED_STEPS[*]}"
        exit 1
    fi
fi

if ! $CHECK; then
    echo ""
    echo "Info    : Verifying gem installations..."
    for gem_name in "${GEM_PACKAGES[@]}"; do
        if is_gem_installed "$gem_name"; then
            $DEBUG && echo "Debug   : ✓ $gem_name is installed"
        else
            echo "Warning : $gem_name installation verification failed"
        fi
    done
fi

echo "Result  : assert_gems finished successfully"
exit 0
