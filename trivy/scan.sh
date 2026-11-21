#!/usr/bin/env bash
# Usage: trivy/scan.sh <image[:tag]>
#
# Security gate policy (override with environment variables):
#   BLOCK_SEVERITIES  severities that BLOCK the deployment   (default: CRITICAL)
#   WARN_SEVERITIES   severities that only raise a warning   (default: HIGH)
#   IGNORE_UNFIXED    ignore CVEs without an available fix   (default: true)
# Any secret found in the image is blocking.
#
# Exit codes:  0 = validated | 1 = BLOCKED | 2 = validated with warnings | 3 = scan error (fail closed)
set -uo pipefail

IMAGE="${1:?usage: $0 <image>}"
REPORT_DIR="${REPORT_DIR:-reports/trivy}"
BLOCK_SEVERITIES="${BLOCK_SEVERITIES:-CRITICAL}"
WARN_SEVERITIES="${WARN_SEVERITIES:-HIGH}"
IGNORE_UNFIXED="${IGNORE_UNFIXED:-true}"
TRIVY_TIMEOUT="${TRIVY_TIMEOUT:-30m}"
IGNORE_FILE="${IGNORE_FILE:-trivy/.trivyignore}"
HTML_TEMPLATE="${HTML_TEMPLATE:-/opt/trivy/templates/html.tpl}"
JSON="${REPORT_DIR}/trivy-report.json"

mkdir -p "${REPORT_DIR}"

common_args=(--scanners "vuln,secret" --timeout "${TRIVY_TIMEOUT}" --severity "UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL")
[ "${IGNORE_UNFIXED}" = "true" ] && common_args+=(--ignore-unfixed)
[ -f "${IGNORE_FILE}" ] && common_args+=(--ignorefile "${IGNORE_FILE}")

echo "==> Trivy scan of ${IMAGE} (block: ${BLOCK_SEVERITIES} | warn: ${WARN_SEVERITIES} | ignore-unfixed: ${IGNORE_UNFIXED} | timeout: ${TRIVY_TIMEOUT})"

# 1. Full machine-readable report (also the source of truth for the gate)
if ! trivy image "${common_args[@]}" --format json --output "${JSON}" "${IMAGE}"; then
  echo "ERROR: Trivy failed to run (DB download? image missing?) -> failing closed" >&2
  exit 3
fi

# 2. Human-readable reports (never decide the result)
if [ -f "${HTML_TEMPLATE}" ]; then
  trivy convert --format template --template "@${HTML_TEMPLATE}" --output "${REPORT_DIR}/trivy-report.html" "${JSON}" || true
fi
trivy convert --format table --severity "${WARN_SEVERITIES},${BLOCK_SEVERITIES}" --output "${REPORT_DIR}/trivy-report.txt" "${JSON}" || true
cat "${REPORT_DIR}/trivy-report.txt" 2>/dev/null || true

# 3. Gate decision
count_vulns() {
  jq --arg sevs "$1" '[.Results[]?.Vulnerabilities[]? | .Severity as $s | select(($sevs | split(",")) | any(. == $s))] | length' "${JSON}"
}
blocking="$(count_vulns "${BLOCK_SEVERITIES}")"
warnings="$(count_vulns "${WARN_SEVERITIES}")"
secrets="$(jq '[.Results[]?.Secrets[]?] | length' "${JSON}")"

{
  echo "Image               : ${IMAGE}"
  echo "Blocking (${BLOCK_SEVERITIES}) : ${blocking}"
  echo "Warnings (${WARN_SEVERITIES})  : ${warnings}"
  echo "Secrets found       : ${secrets}"
} | tee "${REPORT_DIR}/summary.txt"

if [ "${blocking}" -gt 0 ] || [ "${secrets}" -gt 0 ]; then
  echo "SECURITY GATE: BLOCKED"
  jq -r --arg sevs "${BLOCK_SEVERITIES}" '.Results[]?.Vulnerabilities[]? | .Severity as $s | select(($sevs | split(",")) | any(. == $s)) | "  \(.Severity)  \(.VulnerabilityID)  \(.PkgName) \(.InstalledVersion) -> fixed in \(.FixedVersion // "n/a")"' "${JSON}"
  exit 1
fi
if [ "${warnings}" -gt 0 ]; then
  echo "SECURITY GATE: PASSED WITH WARNINGS"
  exit 2
fi
echo "SECURITY GATE: PASSED"
exit 0
