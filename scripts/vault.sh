#!/usr/bin/env bash
# Helper around ansible-vault. Usage: scripts/vault.sh {init|encrypt|edit|view|rekey}
# The vault password lives in .vault_pass (git-ignored) or in $VAULT_PASSWORD_FILE.
set -euo pipefail

PASS_FILE="${VAULT_PASSWORD_FILE:-.vault_pass}"
VAULT_FILE="vault/secrets.yml"
EXAMPLE_FILE="vault/secrets.example.yml"

need_pass() { [ -f "${PASS_FILE}" ] || { echo "Missing ${PASS_FILE}" >&2; exit 1; }; }

case "${1:-}" in
  init)
    # Create YOUR OWN password and YOUR OWN random secrets (replaces the demo vault).
    if [ -f "${PASS_FILE}" ]; then echo "${PASS_FILE} already exists - refusing to overwrite" >&2; exit 1; fi
    umask 077
    openssl rand -base64 24 > "${PASS_FILE}"
    sed -e "s/CHANGE_ME_SECRET_KEY/$(openssl rand -hex 32)/" \
        -e "s/CHANGE_ME_API_TOKEN/$(openssl rand -hex 24)/" \
        -e "s/CHANGE_ME_ADMIN_PASSWORD/$(openssl rand -base64 18 | tr -d '/+=')/" \
        "${EXAMPLE_FILE}" > "${VAULT_FILE}"
    ansible-vault encrypt --vault-password-file "${PASS_FILE}" "${VAULT_FILE}"
    echo "Vault created. Store the content of ${PASS_FILE} in Jenkins (Secret file credential 'ansible-vault-password')."
    ;;
  encrypt) need_pass; ansible-vault encrypt --vault-password-file "${PASS_FILE}" "${VAULT_FILE}" ;;
  edit)    need_pass; ansible-vault edit --vault-password-file "${PASS_FILE}" "${VAULT_FILE}" ;;
  view)    need_pass; ansible-vault view --vault-password-file "${PASS_FILE}" "${VAULT_FILE}" ;;
  rekey)
    need_pass
    umask 077
    openssl rand -base64 24 > "${PASS_FILE}.new"
    ansible-vault rekey --vault-password-file "${PASS_FILE}" --new-vault-password-file "${PASS_FILE}.new" "${VAULT_FILE}"
    mv "${PASS_FILE}.new" "${PASS_FILE}"
    echo "Vault re-keyed. Update the Jenkins credential 'ansible-vault-password' with the new ${PASS_FILE}."
    ;;
  *) echo "Usage: $0 {init|encrypt|edit|view|rekey}" >&2; exit 2 ;;
esac
