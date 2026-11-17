#!/usr/bin/env bash
# Usage: scripts/notify.sh <STATUS> <message>
# Sends a notification to a Slack/Discord/Teams-compatible webhook when
# NOTIFY_WEBHOOK_URL is set. Always appends to reports/notifications.log.
set -uo pipefail

STATUS="${1:-INFO}"
MESSAGE="${2:-no message}"
TEXT="[${STATUS}] ${MESSAGE}"

mkdir -p reports
echo "$(date -u +%FT%TZ) ${TEXT}" >> reports/notifications.log

if [ -z "${NOTIFY_WEBHOOK_URL:-}" ]; then
  echo "NOTIFY_WEBHOOK_URL not set: notification written to reports/notifications.log only"
  exit 0
fi

# jq builds the JSON safely (no shell injection through the message)
payload="$(jq -n --arg t "${TEXT}" '{text: $t, content: $t}')"
if curl -fsS --max-time 10 -X POST -H 'Content-Type: application/json' -d "${payload}" "${NOTIFY_WEBHOOK_URL}" >/dev/null; then
  echo "Notification sent"
else
  echo "WARNING: webhook call failed (the pipeline result is not affected)" >&2
fi
exit 0
