#!/bin/bash

# Assert MyEnv Personal Environment
#
# Orchestrates: assert_packages.sh, assert_git.sh, assert_bashrc.sh
# Idempotent and safe to run multiple times.
#
# Parameters (CLI flags and values consumed here):
#
#   --Debug | -d
#       Verbose logging: print which repo paths and steps run; forwarded to every
#       child script (assert_packages, assert_git, assert_bashrc).
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

DEBUG=false
CHECK=false
GIT_NAME=""
GIT_EMAIL=""
GIT_PASSPHRASE=""
GIT_USER=""

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
packages_script="$script_dir/assert_packages.sh"
bashrc_script="$script_dir/assert_bashrc.sh"
git_assert_script="$script_dir/assert_git.sh"

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
        *)
            echo "Error   : Unrecognized argument $1 in $script_name."
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--name|-n <git_name>] [--email|-e <git_email>] [--Passphrase|-p|-N <passphrase>] [--User|-u <username>]"
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
# FAILED_STEPS — short labels (e.g. assert_packages, assert_git) for the summary line on error.

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

# --- Packages and Cursor (apt repos, AppImage) ---
if ! run_step "assert_packages" "$packages_script" "${common_args[@]}"; then
    echo "Warning : assert_packages step failed"
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
