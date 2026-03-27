#!/bin/bash

# Assert Git Identity Configuration
#
# Ensures global git user.name and user.email are set.
# This script is idempotent and can be run multiple times safely.

DEBUG=false
CHECK=false
INPUT_NAME=""
INPUT_EMAIL=""

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
        *)
            echo "Error   : Unrecognized argument $1 in $script_name."
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--name|-n <git_name>] [--email|-e <git_email>]"
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

if ! command -v git >/dev/null 2>&1; then
    if $CHECK; then
        echo "Check   : Would require git to be installed"
        exit 1
    fi
    echo "Error   : git is not installed. Install git before running $script_name."
    exit 1
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
    echo "Result  : Git global identity asserted successfully"
fi
