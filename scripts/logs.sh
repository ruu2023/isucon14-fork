#!/bin/bash
set -euo pipefail

# ==============================================================================
# ISUCON14 Log Viewer
# ==============================================================================

REMOTE_USER_HOST="${REMOTE_HOST:-win-note@100.109.170.11}"
REMOTE_DIR="${REMOTE_DIR:-/home/win-note/isucon14}"
COMPOSE_FILE="${COMPOSE_FILE:-compose-go.yml}"
SERVICE="${1:-}"

if [ -z "${SERVICE}" ]; then
  echo "Streaming logs for all services (compose: ${COMPOSE_FILE})..."
  ssh -t "${REMOTE_USER_HOST}" "cd ${REMOTE_DIR}/development && docker compose -f ${COMPOSE_FILE} logs -f --tail=100"
else
  echo "Streaming logs for service '${SERVICE}'..."
  ssh -t "${REMOTE_USER_HOST}" "cd ${REMOTE_DIR}/development && docker compose -f ${COMPOSE_FILE} logs -f --tail=100 ${SERVICE}"
fi
