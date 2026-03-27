#!/bin/bash

# Assert Git and SSH Client Identity Configuration
#
# Ensures global git user.name/user.email are set and a user SSH key exists
# for Git operations across projects.
# This script is idempotent and can be run multiple times safely.

DEBUG=false
CHECK=false
INPUT_NAME=""
INPUT_EMAIL=""
INPUT_PASSPHRASE=""
USERNAME="$(whoami)"

script_name="$(basename "${BASH_SOURCE[0]}")"

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
            INPUT_NAME="$1"
            ;;
        --email|-e)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error   : Missing value for --email|-e"
                exit 1
            fi
            INPUT_EMAIL="$1"
            ;;
        --Passphrase|-p|-N)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error   : Missing value for --Passphrase|-p|-N"
                exit 1
            fi
            INPUT_PASSPHRASE="$1"
            ;;
        --User|-u)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error   : Missing value for --User|-u"
                exit 1
            fi
            USERNAME="$1"
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
$DEBUG && echo "Debug   : CHECK = $CHECK"
$DEBUG && echo "Debug   : DEBUG = $DEBUG"
$DEBUG && echo "Debug   : INPUT_NAME = ${INPUT_NAME:-<unset>}"
$DEBUG && echo "Debug   : INPUT_EMAIL = ${INPUT_EMAIL:-<unset>}"
$DEBUG && echo "Debug   : INPUT_PASSPHRASE = ${INPUT_PASSPHRASE:+[REDACTED]}"
$DEBUG && echo "Debug   : USERNAME = $USERNAME"

if ! command -v git >/dev/null 2>&1; then
    if $CHECK; then
        echo "Check   : Would require git to be installed"
        exit 1
    fi
    echo "Error   : git is not installed. Install git before running $script_name."
    exit 1
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
    if $CHECK; then
        echo "Check   : Would require openssh-client to be installed"
        exit 1
    fi
    echo "Error   : openssh-client is not installed (missing ssh-keygen)."
    echo "Info    : Install openssh-client, then re-run $script_name."
    exit 1
fi

HOME_DIR="$(eval echo "~$USERNAME")"
SSH_DIR="$HOME_DIR/.ssh"
PRIVATE_KEY="$SSH_DIR/id_ed25519"
PUBLIC_KEY="$SSH_DIR/id_ed25519.pub"

if [[ -d "$SSH_DIR" ]]; then
    $DEBUG && echo "Debug   : .ssh directory exists for user '$USERNAME'"
else
    if $CHECK; then
        echo "Check   : Would create .ssh directory for user '$USERNAME'"
    else
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        chown "$USERNAME:$USERNAME" "$SSH_DIR"
        echo "Info    : Created .ssh directory for user '$USERNAME'"
    fi
fi

if [[ -f "$PRIVATE_KEY" && -f "$PUBLIC_KEY" ]]; then
    $DEBUG && echo "Debug   : Git SSH keypair already exists for user '$USERNAME'"
else
    if $CHECK; then
        echo "Check   : Would generate Git SSH keypair for user '$USERNAME'"
    else
        ssh_passphrase="$INPUT_PASSPHRASE"
        if [[ -z "$ssh_passphrase" ]]; then
            read -r -s -p "Enter passphrase for ~/.ssh/id_ed25519: " ssh_passphrase
            echo ""
            read -r -s -p "Confirm passphrase: " ssh_passphrase_confirm
            echo ""
            if [[ "$ssh_passphrase" != "$ssh_passphrase_confirm" ]]; then
                echo "Error   : Passphrase confirmation does not match."
                exit 1
            fi
        fi

        ssh-keygen -q -t ed25519 \
            -f "$PRIVATE_KEY" \
            -N "$ssh_passphrase" \
            -C "$USERNAME@$(hostname)" || {
            echo "Error   : Failed to generate Git SSH keypair"
            exit 1
        }
        chmod 600 "$PRIVATE_KEY"
        chmod 644 "$PUBLIC_KEY"
        chown "$USERNAME:$USERNAME" "$PRIVATE_KEY" "$PUBLIC_KEY"
        echo "Info    : Generated Git SSH keypair for user '$USERNAME'"
    fi
fi

if [[ -f "$PRIVATE_KEY" && "$(stat -c "%a" "$PRIVATE_KEY")" -ne 600 ]]; then
    if $CHECK; then
        echo "Check   : Would set private key permissions to 600"
    else
        chmod 600 "$PRIVATE_KEY"
        chown "$USERNAME:$USERNAME" "$PRIVATE_KEY"
        echo "Info    : Fixed private key permissions"
    fi
fi

if [[ -f "$PUBLIC_KEY" && "$(stat -c "%a" "$PUBLIC_KEY")" -ne 644 ]]; then
    if $CHECK; then
        echo "Check   : Would set public key permissions to 644"
    else
        chmod 644 "$PUBLIC_KEY"
        chown "$USERNAME:$USERNAME" "$PUBLIC_KEY"
        echo "Info    : Fixed public key permissions"
    fi
fi

current_name="$(git config --global --get user.name || true)"
current_email="$(git config --global --get user.email || true)"

if [[ -n "$INPUT_NAME" ]]; then
    if $CHECK; then
        echo "Check   : Would set git global user.name to '$INPUT_NAME'"
    else
        echo "Info    : Setting git global user.name to '$INPUT_NAME'"
        git config --global user.name "$INPUT_NAME" || {
            echo "Error   : Failed to set git global user.name"
            exit 1
        }
        current_name="$INPUT_NAME"
    fi
fi

if [[ -n "$INPUT_EMAIL" ]]; then
    if $CHECK; then
        echo "Check   : Would set git global user.email to '$INPUT_EMAIL'"
    else
        echo "Info    : Setting git global user.email to '$INPUT_EMAIL'"
        git config --global user.email "$INPUT_EMAIL" || {
            echo "Error   : Failed to set git global user.email"
            exit 1
        }
        current_email="$INPUT_EMAIL"
    fi
fi

if [[ -z "$current_name" ]]; then
    if $CHECK; then
        echo "Check   : Would prompt for git global user.name"
    else
        read -r -p "Enter git global user.name: " target_name
        if [[ -z "$target_name" ]]; then
            echo "Error   : git global user.name is required"
            exit 1
        fi
        echo "Info    : Setting git global user.name to '$target_name'"
        git config --global user.name "$target_name" || {
            echo "Error   : Failed to set git global user.name"
            exit 1
        }
    fi
else
    $DEBUG && echo "Debug   : git global user.name is set to '$current_name'"
fi

if [[ -z "$current_email" ]]; then
    if $CHECK; then
        echo "Check   : Would prompt for git global user.email"
    else
        read -r -p "Enter git global user.email: " target_email
        if [[ -z "$target_email" ]]; then
            echo "Error   : git global user.email is required"
            exit 1
        fi
        echo "Info    : Setting git global user.email to '$target_email'"
        git config --global user.email "$target_email" || {
            echo "Error   : Failed to set git global user.email"
            exit 1
        }
    fi
else
    $DEBUG && echo "Debug   : git global user.email is set to '$current_email'"
fi

if $CHECK; then
    echo "Result  : Check complete"
else
    echo "Result  : Git and SSH identity asserted successfully"
    echo "Next    : Add public key to GitHub: https://github.com/settings/keys"
    echo "Next    : Public key path: $PUBLIC_KEY"
fi
