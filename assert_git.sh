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

if [[ -z "$current_name" ]]; then
    if [[ -n "$INPUT_NAME" ]]; then
        target_name="$INPUT_NAME"
    elif $CHECK; then
        target_name="<prompt>"
    else
        read -r -p "Enter git global user.name: " target_name
    fi

    if [[ -z "$target_name" || "$target_name" == "<prompt>" ]]; then
        if $CHECK; then
            echo "Check   : Would prompt for git global user.name"
        else
            echo "Error   : git global user.name is required"
            exit 1
        fi
    elif $CHECK; then
        echo "Check   : Would set git global user.name to '$target_name'"
    else
        echo "Info    : Setting git global user.name to '$target_name'"
        git config --global user.name "$target_name" || {
            echo "Error   : Failed to set git global user.name"
            exit 1
        }
    fi
else
    $DEBUG && echo "Debug   : git global user.name is already set to '$current_name'"
fi

if [[ -z "$current_email" ]]; then
    if [[ -n "$INPUT_EMAIL" ]]; then
        target_email="$INPUT_EMAIL"
    elif $CHECK; then
        target_email="<prompt>"
    else
        read -r -p "Enter git global user.email: " target_email
    fi

    if [[ -z "$target_email" || "$target_email" == "<prompt>" ]]; then
        if $CHECK; then
            echo "Check   : Would prompt for git global user.email"
        else
            echo "Error   : git global user.email is required"
            exit 1
        fi
    elif $CHECK; then
        echo "Check   : Would set git global user.email to '$target_email'"
    else
        echo "Info    : Setting git global user.email to '$target_email'"
        git config --global user.email "$target_email" || {
            echo "Error   : Failed to set git global user.email"
            exit 1
        }
    fi
else
    $DEBUG && echo "Debug   : git global user.email is already set to '$current_email'"
fi

if [[ -n "$INPUT_NAME" && -n "$current_name" && "$current_name" != "$INPUT_NAME" ]]; then
    if $CHECK; then
        echo "Check   : git global user.name already set to '$current_name' (flag requested '$INPUT_NAME')"
    else
        $DEBUG && echo "Debug   : Not overriding existing git global user.name '$current_name'"
    fi
fi

if [[ -n "$INPUT_EMAIL" && -n "$current_email" && "$current_email" != "$INPUT_EMAIL" ]]; then
    if $CHECK; then
        echo "Check   : git global user.email already set to '$current_email' (flag requested '$INPUT_EMAIL')"
    else
        $DEBUG && echo "Debug   : Not overriding existing git global user.email '$current_email'"
    fi
fi

if $CHECK; then
    echo "Result  : Check complete"
else
    echo "Result  : Git global identity asserted successfully"
fi
