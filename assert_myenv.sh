#!/bin/bash

# Assert MyEnv Personal Environment
#
# Orchestrates: assert_packages.sh (kitty, Claude Code, Claude Desktop, draw.io, csdm-injector, context-variables .debs),
# assert_gems.sh (AsciiDoctor PDF/diagram gems), assert_git.sh, assert_bashrc.sh,
# assert_dotfiles.sh, assert_extensions.sh, assert_sublime.sh, assert_onedrive.sh,
# assert_xfce4.sh
# Idempotent and safe to run multiple times.
#
# Parameters (CLI flags and values consumed here):
#
#   --Debug | -d
#       Verbose logging: print which repo paths and steps run; forwarded to every
#       child script (assert_packages, assert_git, assert_bashrc, assert_xfce4).
#
#   --Check | -c
#       Dry-run: report what would be installed or changed without modifying the
#       system (no apt installs, no file edits, no git config writes where supported).
#
#   --name | -n <string>
#       Git global user.name for commits (e.g. your real name). Passed through to
#       assert_git.sh; if omitted, assert_git may prompt interactively when unset.
#
#   --email | -e <string>
#       Git global user.email (must match your Git host account). Passed to
#       assert_git.sh; if omitted, assert_git may prompt when unset.
#
#   --Passphrase | -p | -N <string>
#       Passphrase for generating or using the Git SSH private key (~/.ssh/id_ed25519_github).
#       Passed to assert_git.sh; avoids interactive passphrase prompts when set.
#
#   --User | -u <username>
#       Unix account name whose home directory and ~/.ssh are configured (default: current user).
#       Passed to assert_git.sh for SSH key paths and ownership.
#
#   --skip-cursor-extensions
#       Skip assert_extensions.sh (manual override only; normal runs install extensions).
#
#   --restart-lightdm | -r
#       Passed to assert_xfce4.sh: restart LightDM after a live run (useful from SSH/cron).
#
#   --no-restart-lightdm | --skip-lightdm-restart
#       Passed to assert_xfce4.sh: skip LightDM restart without prompting. On an interactive TTY,
#       assert_xfce4 otherwise asks [R]estart or [S]kip; these flags bypass that and skip restart.
#       (Default is already no restart when NONINTERACTIVE=1 or there is no TTY.)
#
#   --skip-firmware-update | --amdgpu-dc-off | --amdgpu-dc-on | --suppress-volman-noise
#       Passed to assert_xfce4.sh (AMD iGPU freeze mitigations). See assert_xfce4.sh header:
#       linux-firmware is kept current by default; --amdgpu-dc-off is an opt-in last-resort
#       kernel workaround (disables AMD Display Core; reboot required; see warnings).

DEBUG=false
CHECK=false
GIT_NAME=""
GIT_EMAIL=""
GIT_PASSPHRASE=""
GIT_USER=""
XFCE_EXTRA_ARGS=()
SKIP_CURSOR_EXTENSIONS=false

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
packages_script="$script_dir/assert/assert_packages.sh"
gems_script="$script_dir/assert/assert_gems.sh"
bashrc_script="$script_dir/assert_bashrc.sh"
git_assert_script="$script_dir/assert_git.sh"
xfce_assert_script="$script_dir/assert/assert_xfce4.sh"
dotfiles_assert_script="$script_dir/assert/assert_dotfiles.sh"
extensions_assert_script="$script_dir/assert/assert_extensions.sh"
sublime_assert_script="$script_dir/assert/assert_sublime.sh"
onedrive_assert_script="$script_dir/assert/assert_onedrive.sh"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d)
            DEBUG=true
            ;;
        --Check|-c)
            CHECK=true
            ;;
        --name|-n)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error   : Missing value for --name|-n"
                exit 1
            fi
            GIT_NAME="$1"
            ;;
        --email|-e)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error   : Missing value for --email|-e"
                exit 1
            fi
            GIT_EMAIL="$1"
            ;;
        --Passphrase|-p|-N)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error   : Missing value for --Passphrase|-p|-N"
                exit 1
            fi
            GIT_PASSPHRASE="$1"
            ;;
        --User|-u)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error   : Missing value for --User|-u"
                exit 1
            fi
            GIT_USER="$1"
            ;;
        --restart-lightdm|-r)
            XFCE_EXTRA_ARGS+=(--restart-lightdm)
            ;;
        --no-restart-lightdm|--skip-lightdm-restart)
            XFCE_EXTRA_ARGS+=(--no-restart-lightdm)
            ;;
        --skip-cursor-extensions)
            SKIP_CURSOR_EXTENSIONS=true
            ;;
        --skip-firmware-update|--amdgpu-dc-off|--amdgpu-dc-on|--suppress-volman-noise)
            XFCE_EXTRA_ARGS+=("$1")
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name."
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--name|-n <git_name>] [--email|-e <git_email>] [--Passphrase|-p|-N <passphrase>] [--User|-u <username>] [--skip-cursor-extensions] [--restart-lightdm|-r] [--no-restart-lightdm] [--skip-lightdm-restart] [--skip-firmware-update] [--amdgpu-dc-off] [--amdgpu-dc-on] [--suppress-volman-noise]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Debug   : Starting: $script_name"
$DEBUG && echo "Debug   : script_dir = $script_dir"

common_args=()
$DEBUG && common_args+=(--Debug)
$CHECK && common_args+=(--Check)

# FAILED_COUNT — number of orchestrated steps that exited non-zero (missing script, chmod, or runtime failure).
# FAILED_STEPS — short labels (e.g. assert_packages, assert_git, assert_xfce4) for the summary line on error.

FAILED_COUNT=0
FAILED_STEPS=()

# run_step <step_label> <path_to_script> [args...]
#   step_label — used only in FAILED_STEPS / diagnostics (not passed to the script).
#   path_to_script — must exist and be executable.
#   remaining args — forwarded verbatim to the child script (e.g. --Debug, --name …).

run_step() {
    local label=$1
    local script_path=$2
    shift 2
    if [[ ! -f "$script_path" ]]; then
        echo "Error   : Script not found: $script_path"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_STEPS+=("$label:missing")
        return 1
    fi
    if [[ ! -x "$script_path" ]]; then
        echo "Error   : Script not executable: $script_path"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_STEPS+=("$label:not_executable")
        return 1
    fi
    if ! "$script_path" "$@"; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_STEPS+=("$label")
        return 1
    fi
    return 0
}

# --- Packages, Cursor (AppImage), draw.io (.deb), csdm-injector (.deb via apt) ---
if ! run_step "assert_packages" "$packages_script" "${common_args[@]}"; then
    echo "Warning : assert_packages step failed"
fi

# --- Ruby gems (AsciiDoctor PDF/diagram; requires ruby-rubygems from assert_packages) ---
if ! run_step "assert_gems" "$gems_script" "${common_args[@]}"; then
    echo "Warning : assert_gems step failed"
fi

# --- Git identity and SSH (all git/SSH logic lives in assert_git.sh) ---
git_assert_args=("${common_args[@]}")
[[ -n "$GIT_NAME" ]] && git_assert_args+=(--name "$GIT_NAME")
[[ -n "$GIT_EMAIL" ]] && git_assert_args+=(--email "$GIT_EMAIL")
[[ -n "$GIT_PASSPHRASE" ]] && git_assert_args+=(--Passphrase "$GIT_PASSPHRASE")
[[ -n "$GIT_USER" ]] && git_assert_args+=(--User "$GIT_USER")

if ! run_step "assert_git" "$git_assert_script" "${git_assert_args[@]}"; then
    echo "Warning : assert_git step failed"
fi

# --- ~/.bashrc hook for myenv/.bashrc ---
if ! run_step "assert_bashrc" "$bashrc_script" "${common_args[@]}"; then
    echo "Warning : assert_bashrc step failed"
fi

# --- Cursor settings/keybindings managed in repo dotfiles/cursor ---
if ! run_step "assert_dotfiles" "$dotfiles_assert_script" "${common_args[@]}"; then
    echo "Warning : assert_dotfiles step failed"
fi

# --- Cursor extension list enforcement from repo dotfiles/cursor/extensions.txt ---
if [[ -n "${CURSOR_AGENT:-}" ]] && ! $SKIP_CURSOR_EXTENSIONS; then
    SKIP_CURSOR_EXTENSIONS=true
    echo "Info    : Skipping assert_extensions (CURSOR_AGENT — avoid GUI side effects during agent session)"
fi
if $SKIP_CURSOR_EXTENSIONS; then
    echo "Info    : Skipping assert_extensions (--skip-cursor-extensions)"
else
    if ! run_step "assert_extensions" "$extensions_assert_script" "${common_args[@]}"; then
        echo "Warning : assert_extensions step failed"
    fi
fi

# --- Sublime Text Package Control + Pretty JSON from repo dotfiles/sublime ---
if ! run_step "assert_sublime" "$sublime_assert_script" "${common_args[@]}"; then
    echo "Warning : assert_sublime step failed"
fi

# --- OneDrive / SharePoint folders under $HOME (rclone mount) ---
if ! run_step "assert_onedrive" "$onedrive_assert_script" "${common_args[@]}"; then
    echo "Warning : assert_onedrive step failed"
fi

# --- XFCE4 desktop, LightDM, KVM helpers (Ubuntu UI parity across lab hosts) ---
if ! run_step "assert_xfce4" "$xfce_assert_script" "${common_args[@]}" "${XFCE_EXTRA_ARGS[@]}"; then
    echo "Warning : assert_xfce4 step failed"
fi

# --- Summary ---
if $CHECK; then
    echo "Result  : MyEnv check complete (all steps dry-run where applicable)"
else
    if [[ $FAILED_COUNT -gt 0 ]]; then
        echo "Error   : MyEnv completed with $FAILED_COUNT failure(s): ${FAILED_STEPS[*]}"
        exit 1
    fi
    echo "Result  : MyEnv personal environment configured successfully"
fi

exit 0
