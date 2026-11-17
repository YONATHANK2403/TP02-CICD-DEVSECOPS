#!/usr/bin/env bash
# Usage: scripts/connectivity-test.sh <host> <port> <label>
# Connectivity / smoke tests against a deployed environment. Exit 1 if any test fails.
set -uo pipefail

HOST="${1:?host required}"
PORT="${2:?port required}"
LABEL="${3:-env}"
RETRIES="${RETRIES:-20}"
DELAY="${DELAY:-3}"
MAX_LATENCY_MS="${MAX_LATENCY_MS:-1000}"
REPORT_DIR="${REPORT_DIR:-reports/connectivity}"
REPORT="${REPORT_DIR}/${LABEL}.txt"
BASE_URL="http://${HOST}:${PORT}"
FAILED=0

mkdir -p "${REPORT_DIR}"
: > "${REPORT}"

log() { echo "$*" | tee -a "${REPORT}"; }
pass() { log "PASS  $*"; }
fail() { log "FAIL  $*"; FAILED=1; }

log "== Connectivity tests (${LABEL}) -> ${BASE_URL} =="

# 1. TCP port reachable (with retries while the container starts)
ok=0
for _ in $(seq 1 "${RETRIES}"); do
  if (exec 3<>"/dev/tcp/${HOST}/${PORT}") 2>/dev/null; then ok=1; break; fi
  sleep "${DELAY}"
done
if [ "${ok}" -eq 1 ]; then pass "TCP ${HOST}:${PORT} reachable"; else fail "TCP ${HOST}:${PORT} unreachable"; fi

# 2. /health returns 200 (with retries)
code=000
for _ in $(seq 1 "${RETRIES}"); do
  code="$(curl -s -o /tmp/health.json -w '%{http_code}' --max-time 5 "${BASE_URL}/health" || true)"
  [ "${code}" = "200" ] && break
  sleep "${DELAY}"
done
if [ "${code}" = "200" ]; then pass "GET /health -> 200"; else fail "GET /health -> ${code}"; fi

# 3. Health payload: status ok and secrets injected from the vault
if [ "${code}" = "200" ]; then
  if jq -e '.status == "ok"' /tmp/health.json >/dev/null; then pass "health.status == ok"; else fail "health.status != ok"; fi
  if jq -e '.secrets_loaded == true' /tmp/health.json >/dev/null; then
    pass "secrets injected from the vault (secrets_loaded == true)"
  else
    fail "secrets NOT injected (secrets_loaded != true)"
  fi
fi

# 4. Landing page
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${BASE_URL}/" || true)"
if [ "${code}" = "200" ]; then pass "GET / -> 200"; else fail "GET / -> ${code}"; fi

# 5. Unknown route must be a clean 404
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${BASE_URL}/does-not-exist" || true)"
if [ "${code}" = "404" ]; then pass "GET /does-not-exist -> 404"; else fail "GET /does-not-exist -> ${code} (expected 404)"; fi

# 6. Latency budget
latency_s="$(curl -s -o /dev/null -w '%{time_total}' --max-time 5 "${BASE_URL}/health" || echo 99)"
latency_ms="$(awk -v t="${latency_s}" 'BEGIN { printf "%d", t * 1000 }')"
if [ "${latency_ms}" -le "${MAX_LATENCY_MS}" ]; then
  pass "latency ${latency_ms} ms <= ${MAX_LATENCY_MS} ms"
else
  fail "latency ${latency_ms} ms > ${MAX_LATENCY_MS} ms"
fi

if [ "${FAILED}" -ne 0 ]; then
  log "== RESULT: FAILED =="
  exit 1
fi
log "== RESULT: PASSED =="
