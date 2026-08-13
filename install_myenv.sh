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

normalize_repo_url() {
    local url="$1"
    local normalized="$url"
    normalized="${normalized#ssh://git@github.com/}"
    normalized="${normalized#git@github.com:}"
    normalized="${normalized#https://github.com/}"
    normalized="${normalized%.git}"
    echo "$normalized"
}

required_assert_files_present() {
    local required=(
        "$INSTALL_DIR/assert/assert_packages.sh"
        "$INSTALL_DIR/assert_git.sh"
        "$INSTALL_DIR/assert_bashrc.sh"
        "$INSTALL_DIR/assert/assert_xfce4.sh"
        "$INSTALL_DIR/assert/assert_dotfiles.sh"
        "$INSTALL_DIR/assert/assert_extensions.sh"
        "$INSTALL_DIR/assert/assert_sublime.sh"
        "$INSTALL_DIR/assert/assert_onedrive.sh"
    )
    local missing=0
    local path
    for path in "${required[@]}"; do
        if [[ ! -f "$path" ]]; then
            echo "Warning : Missing required file: $path"
            missing=1
        fi
    done
    [[ $missing -eq 0 ]]
}

ensure_repo() {
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        echo "Info    : Existing repository found at $INSTALL_DIR"
        local current_origin=""
        current_origin="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
        if [[ -n "$current_origin" ]] && \
           [[ "$(normalize_repo_url "$current_origin")" != "$(normalize_repo_url "$REPO_URL")" ]]; then
            echo "Warning : Existing origin ($current_origin) differs from requested repo ($REPO_URL)"
        fi

        if $CHECK; then
            echo "Check   : Would update existing repository at $INSTALL_DIR"
            return 0
        fi

        local had_local_changes=false
        local stashed_changes=false
        if [[ -n "$(git -C "$INSTALL_DIR" status --porcelain 2>/dev/null)" ]]; then
            had_local_changes=true
            echo "Info    : Local changes detected; stashing before update"
            git -C "$INSTALL_DIR" stash push -u -m "install_myenv_autostash_$(date +%s)" >/dev/null
            stashed_changes=true
        fi

        echo "Info    : Updating existing repository"
        git -C "$INSTALL_DIR" fetch --all --prune
        if ! git -C "$INSTALL_DIR" pull --ff-only; then
            echo "Info    : Fast-forward pull not possible; trying rebase update"
            if ! git -C "$INSTALL_DIR" pull --rebase; then
                echo "Warning : Could not update repository via pull --ff-only or pull --rebase"
                if $stashed_changes; then
                    echo "Info    : Restoring stashed local changes after failed update"
                    git -C "$INSTALL_DIR" stash pop >/dev/null || true
                fi
                return 0
            fi
        fi

        if $stashed_changes; then
            echo "Info    : Re-applying stashed local changes"
            if ! git -C "$INSTALL_DIR" stash pop >/dev/null; then
                echo "Warning : Could not automatically re-apply stashed changes; resolve manually in $INSTALL_DIR"
            fi
        fi

        if ! required_assert_files_present; then
            echo "Warning : Existing repository still missing required files after update"
            local backup_dir="${INSTALL_DIR}.bak.$(date +%Y%m%d%H%M%S)"
            echo "Info    : Moving current directory to $backup_dir and re-cloning"
            mv "$INSTALL_DIR" "$backup_dir"
            git clone "$REPO_URL" "$INSTALL_DIR"
            if $had_local_changes; then
                echo "Warning : Previous local changes are preserved in: $backup_dir"
            fi
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

run_step "assert_packages" bash "$INSTALL_DIR/assert/assert_packages.sh" "${common_args[@]}"
run_step "assert_git" bash "$INSTALL_DIR/assert_git.sh" "${git_args[@]}"
run_step "assert_bashrc" bash "$INSTALL_DIR/assert_bashrc.sh" "${common_args[@]}"
run_step "assert_dotfiles" bash "$INSTALL_DIR/assert/assert_dotfiles.sh" --merge "${common_args[@]}"

if $SKIP_EXTENSIONS; then
    echo "Info    : Skipping assert_extensions (--skip-extensions)"
else
    run_step "assert_extensions" bash "$INSTALL_DIR/assert/assert_extensions.sh" --merge "${common_args[@]}"
fi

run_step "assert_sublime" bash "$INSTALL_DIR/assert/assert_sublime.sh" "${common_args[@]}"
run_step "assert_onedrive" bash "$INSTALL_DIR/assert/assert_onedrive.sh" "${common_args[@]}"

run_step "assert_xfce4" bash "$INSTALL_DIR/assert/assert_xfce4.sh" "${common_args[@]}" "${XFCE_EXTRA_ARGS[@]}"

if $CHECK; then
    echo "Result  : install_myenv check complete"
else
    echo "Result  : install_myenv finished successfully"
fi

exit 0
