#!/bin/bash
#
# install_myenv.sh
#
# Bootstrap installer/updater for myenv:
#  - Clone myenv if missing
#  - Update existing clone (fast-forward only when clean)
#  - Run all assert scripts
#
# Usage:
#   bash install_myenv.sh
#   bash install_myenv.sh --dir ~/repos/myenv --repo-url https://github.com/gxbrooks/myenv.git
#   bash install_myenv.sh --skip-extensions
#   bash install_myenv.sh --Check
#

set -euo pipefail

DEBUG=false
CHECK=false
SKIP_EXTENSIONS=false

REPO_URL="https://github.com/gxbrooks/myenv.git"
INSTALL_DIR="$HOME/myenv"

GIT_NAME=""
GIT_EMAIL=""
GIT_PASSPHRASE=""
GIT_USER=""
XFCE_EXTRA_ARGS=()

script_name="$(basename "${BASH_SOURCE[0]}")"

usage() {
    cat <<EOF
Usage: $script_name [options]

Options:
  --repo-url <url>                     Git URL for myenv clone/update
  --dir <path>                         Install/update path (default: ~/myenv)
  --Debug, -d                          Enable verbose logging
  --Check, -c                          Dry-run mode where supported
  --skip-extensions                    Skip Cursor extension assert/install
  --name, -n <git_name>                Pass through to assert_git.sh
  --email, -e <git_email>              Pass through to assert_git.sh
  --Passphrase, -p, -N <passphrase>    Pass through to assert_git.sh
  --User, -u <username>                Pass through to assert_git.sh
  --restart-lightdm, -r                Pass through to assert_xfce4.sh
  --no-restart-lightdm                 Pass through to assert_xfce4.sh
  --help, -h                           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-url)
            shift
            [[ -n "${1:-}" ]] || { echo "Error   : Missing value for --repo-url"; exit 1; }
            REPO_URL="$1"
            ;;
        --dir)
            shift
            [[ -n "${1:-}" ]] || { echo "Error   : Missing value for --dir"; exit 1; }
            INSTALL_DIR="$1"
            ;;
        --Debug|-d)
            DEBUG=true
            ;;
        --Check|-c)
            CHECK=true
            ;;
        --skip-extensions)
            SKIP_EXTENSIONS=true
            ;;
        --name|-n)
            shift
            [[ -n "${1:-}" ]] || { echo "Error   : Missing value for --name|-n"; exit 1; }
            GIT_NAME="$1"
            ;;
        --email|-e)
            shift
            [[ -n "${1:-}" ]] || { echo "Error   : Missing value for --email|-e"; exit 1; }
            GIT_EMAIL="$1"
            ;;
        --Passphrase|-p|-N)
            shift
            [[ -n "${1:-}" ]] || { echo "Error   : Missing value for --Passphrase|-p|-N"; exit 1; }
            GIT_PASSPHRASE="$1"
            ;;
        --User|-u)
            shift
            [[ -n "${1:-}" ]] || { echo "Error   : Missing value for --User|-u"; exit 1; }
            GIT_USER="$1"
            ;;
        --restart-lightdm|-r)
            XFCE_EXTRA_ARGS+=(--restart-lightdm)
            ;;
        --no-restart-lightdm)
            XFCE_EXTRA_ARGS+=(--no-restart-lightdm)
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Error   : Unrecognized argument $1"
            usage
            exit 1
            ;;
    esac
    shift
done

INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

if ! command -v git >/dev/null 2>&1; then
    echo "Error   : git is required but not found in PATH"
    exit 1
fi

$DEBUG && echo "Debug   : REPO_URL=$REPO_URL"
$DEBUG && echo "Debug   : INSTALL_DIR=$INSTALL_DIR"
$DEBUG && echo "Debug   : CHECK=$CHECK"
$DEBUG && echo "Debug   : SKIP_EXTENSIONS=$SKIP_EXTENSIONS"

ensure_repo() {
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        echo "Info    : Existing repository found at $INSTALL_DIR"
        local current_origin=""
        current_origin="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
        if [[ -n "$current_origin" && "$current_origin" != "$REPO_URL" ]]; then
            echo "Warning : Existing origin ($current_origin) differs from requested repo ($REPO_URL)"
        fi

        if $CHECK; then
            echo "Check   : Would update existing repository at $INSTALL_DIR"
            return 0
        fi

        if [[ -n "$(git -C "$INSTALL_DIR" status --porcelain 2>/dev/null)" ]]; then
            echo "Warning : Repository has local changes; skipping git pull/update"
            echo "Info    : Continuing with asserts on current working tree"
            return 0
        fi

        echo "Info    : Updating existing repository (fast-forward only)"
        git -C "$INSTALL_DIR" fetch --all --prune
        if ! git -C "$INSTALL_DIR" pull --ff-only; then
            echo "Warning : Could not fast-forward pull; continuing with local checkout"
        fi
        return 0
    fi

    if [[ -e "$INSTALL_DIR" ]]; then
        echo "Error   : $INSTALL_DIR exists but is not a git repository"
        echo "Info    : Move/remove it, or pass a different --dir path"
        exit 1
    fi

    if $CHECK; then
        echo "Check   : Would clone $REPO_URL to $INSTALL_DIR"
        return 0
    fi

    echo "Info    : Cloning $REPO_URL to $INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
}

run_step() {
    local label="$1"
    shift
    if ! "$@"; then
        echo "Error   : Step failed: $label"
        return 1
    fi
    return 0
}

ensure_repo

if $CHECK && [[ ! -d "$INSTALL_DIR" ]]; then
    echo "Check   : Skipping asserts because repository is not cloned in --Check mode"
    echo "Result  : install_myenv check complete"
    exit 0
fi

common_args=()
$DEBUG && common_args+=(--Debug)
$CHECK && common_args+=(--Check)

git_args=("${common_args[@]}")
[[ -n "$GIT_NAME" ]] && git_args+=(--name "$GIT_NAME")
[[ -n "$GIT_EMAIL" ]] && git_args+=(--email "$GIT_EMAIL")
[[ -n "$GIT_PASSPHRASE" ]] && git_args+=(--Passphrase "$GIT_PASSPHRASE")
[[ -n "$GIT_USER" ]] && git_args+=(--User "$GIT_USER")

echo "Info    : Running myenv asserts from $INSTALL_DIR"

run_step "assert_packages" bash "$INSTALL_DIR/assert_packages.sh" "${common_args[@]}"
run_step "assert_git" bash "$INSTALL_DIR/assert_git.sh" "${git_args[@]}"
run_step "assert_bashrc" bash "$INSTALL_DIR/assert_bashrc.sh" "${common_args[@]}"
run_step "assert_dotfiles" bash "$INSTALL_DIR/assert/assert_dotfiles.sh" --merge "${common_args[@]}"

if $SKIP_EXTENSIONS; then
    echo "Info    : Skipping assert_extensions (--skip-extensions)"
else
    run_step "assert_extensions" bash "$INSTALL_DIR/assert/assert_extensions.sh" --merge "${common_args[@]}"
fi

run_step "assert_xfce4" bash "$INSTALL_DIR/assert_xfce4.sh" "${common_args[@]}" "${XFCE_EXTRA_ARGS[@]}"

if $CHECK; then
    echo "Result  : install_myenv check complete"
else
    echo "Result  : install_myenv finished successfully"
fi

exit 0
