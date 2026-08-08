# myenv — personal shell hooks (native Linux). Sourced from ~/.bashrc (see assert_myenv.sh).

# csdm-injector — load local secrets (XDG). File is never in the myenv git tree.
# Create/seed via assert_bashrc.sh → ~/.config/csdm-injector/env (mode 0600).
_csdm_env="${XDG_CONFIG_HOME:-$HOME/.config}/csdm-injector/env"
if [[ -f "${_csdm_env}" && -r "${_csdm_env}" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "${_csdm_env}"
  set +a
fi
unset _csdm_env

# Load SSH keys into ssh-agent via keychain (install keychain via assert_myenv.sh / apt).
# Prefer keychain over raw ssh-add so passphrases are cached per login session.
# Only id_ed25519_<purpose> keys (e.g. _github, _ansible). Legacy id_ed25519 / id_rsa are deprecated.
# New use cases → generate a new id_ed25519_<purpose> and wire it in assert_git / enable_user_for_ssh_client / here.
_keychain_keys=()
for _k in id_ed25519_github id_ed25519_ansible; do
  [[ -f "$HOME/.ssh/$_k" ]] && _keychain_keys+=("$_k")
done
if ((${#_keychain_keys[@]})); then
  command -v keychain >/dev/null 2>&1 && eval "$(keychain --quiet --eval "${_keychain_keys[@]}")"
fi
unset _k _keychain_keys

# Spark observability client sanity assertions.
# Run on new interactive shells to detect drift in cluster endpoints/mounts/env.
if [[ $- == *i* ]]; then
  _spark_obs_root="${HOME}/repos/spark-observability"
  _spark_assert="${_spark_obs_root}/linux/assert_client_sanity.sh"
  if [[ -x "${_spark_assert}" ]]; then
    "${_spark_assert}" >/tmp/assert_client_sanity.log 2>&1 || {
      echo "Warning: spark client sanity check reported issues. See /tmp/assert_client_sanity.log"
    }
  fi
  unset _spark_obs_root _spark_assert
fi
