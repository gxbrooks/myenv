# myenv — personal shell hooks (native Linux). Sourced from ~/.bashrc (see assert_myenv.sh).

# Load SSH keys into ssh-agent via keychain (install keychain via assert_myenv.sh / apt).
# Prefer keychain over raw ssh-add so passphrases are cached per login session.
# Keys must match assert_git.sh (id_ed25519_github) and enable_user_for_ssh_client.sh (id_ed25519_ansible).
_keychain_keys=()
for _k in id_ed25519_github id_ed25519 id_ed25519_ansible id_rsa; do
  [[ -f "$HOME/.ssh/$_k" ]] && _keychain_keys+=("$_k")
done
if ((${#_keychain_keys[@]})); then
  command -v keychain >/dev/null 2>&1 && eval "$(keychain --quiet --eval "${_keychain_keys[@]}")"
fi
unset _k _keychain_keys
