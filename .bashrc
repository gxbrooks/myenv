# myenv — personal shell hooks (native Linux). Sourced from ~/.bashrc (see assert_myenv.sh).

# Load SSH keys into ssh-agent (install keychain via assert_myenv.sh / apt).
_keychain_keys=()
for _k in id_ed25519 id_ed25519_ansible id_rsa; do
  [[ -f "$HOME/.ssh/$_k" ]] && _keychain_keys+=("$_k")
done
if ((${#_keychain_keys[@]})); then
  command -v keychain >/dev/null 2>&1 && eval "$(keychain --quiet --eval "${_keychain_keys[@]}")"
fi
unset _k _keychain_keys
