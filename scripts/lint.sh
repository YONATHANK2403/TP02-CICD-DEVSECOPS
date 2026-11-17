#!/usr/bin/env bash
# Usage: scripts/lint.sh {yamllint|ansible-lint|pylint|vault-check}
set -euo pipefail

REPORT_DIR="${REPORT_DIR:-reports/lint}"
mkdir -p "${REPORT_DIR}"

case "${1:-}" in
  yamllint)
    yamllint -c .yamllint --strict . 2>&1 | tee "${REPORT_DIR}/yamllint.txt"
    ;;
  ansible-lint)
    ansible-lint -c .ansible-lint scripts/deploy.yml 2>&1 | tee "${REPORT_DIR}/ansible-lint.txt"
    ;;
  pylint)
    PYTHONPATH=app pylint --rcfile=.pylintrc app/demo_app app/tests 2>&1 | tee "${REPORT_DIR}/pylint.txt"
    ;;
  vault-check)
    # Guard: the vault file must be encrypted before it ever reaches Git.
    if ! head -n1 vault/secrets.yml | grep -q "^\$ANSIBLE_VAULT;"; then
      echo "ERROR: vault/secrets.yml is NOT encrypted. Run: bash scripts/vault.sh encrypt" >&2
      exit 1
    fi
    echo "OK: vault/secrets.yml is encrypted" | tee "${REPORT_DIR}/vault-check.txt"
    ;;
  *)
    echo "Usage: $0 {yamllint|ansible-lint|pylint|vault-check}" >&2
    exit 2
    ;;
esac
