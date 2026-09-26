#!/bin/bash
set -euo pipefail

# ==============================================================================
# ISUCON14 Deployment Script
# ==============================================================================

REMOTE_USER_HOST="${REMOTE_HOST:-win-note@100.109.170.11}"
REMOTE_DIR="${REMOTE_DIR:-/home/win-note/isucon14}"
COMPOSE_FILE="${COMPOSE_FILE:-compose-node.yml}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "========================================================"
echo " [ISUCON14 Deploy] Starting deployment"
echo " Target:     ${REMOTE_USER_HOST}:${REMOTE_DIR}"
echo " Compose:    ${COMPOSE_FILE}"
echo " Source:     ${PROJECT_ROOT}"
echo "========================================================"

# 1. Sync files using rsync
echo "[1/4] Syncing files to remote server..."
rsync -avz \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='node_modules' \
  --exclude='.task' \
  --exclude='tmp' \
  --exclude='*.log' \
  --exclude='slow-logs' \
  --exclude='.vscode' \
  --exclude='.DS_Store' \
  --exclude='.beads' \
  --exclude='development/mysql' \
  --exclude='bench/bench' \
  --exclude='webapp/go/isuride' \
  --exclude='webapp/go/webapp' \
  --exclude='webapp/nodejs/node_modules' \
  --exclude='webapp/nodejs/dist' \
  "${PROJECT_ROOT}/" "${REMOTE_USER_HOST}:${REMOTE_DIR}/"

# 2. Reset logs on remote
echo "[2/4] Resetting remote query / access logs..."
ssh "${REMOTE_USER_HOST}" "bash -s" << 'REMOTECOMMAND'
  if docker ps --format "{{.Names}}" | grep -q "development-db-1"; then
    SLOW_LOG_FILE=$(docker exec development-db-1 mysql -N -s -uroot -pisucon -e "SELECT @@global.slow_query_log_file" 2>/dev/null || true)
    if [ -n "$SLOW_LOG_FILE" ]; then
      docker exec development-db-1 sh -c "> '$SLOW_LOG_FILE'" 2>/dev/null || true
    fi
    docker exec development-db-1 mysql -uroot -pisucon -e "SET GLOBAL slow_query_log = 1; SET GLOBAL long_query_time = 0;" 2>/dev/null || true
  fi

  # Reset Nginx access log
  mkdir -p ~/isucon14/development/nginx/logs
  chmod 777 ~/isucon14/development/nginx/logs 2>/dev/null || true
  > ~/isucon14/development/nginx/logs/access_ltsv.log 2>/dev/null || true
  chmod 666 ~/isucon14/development/nginx/logs/access_ltsv.log 2>/dev/null || true
  if docker ps --format "{{.Names}}" | grep -q "nginx"; then
    docker exec nginx nginx -s reopen 2>/dev/null || true
  fi
REMOTECOMMAND

# 3. Rebuild & restart docker compose services (with tunnel-net overlay)
echo "[3/4] Rebuilding and restarting containers on remote..."
ssh "${REMOTE_USER_HOST}" "bash -s" << REMOTECOMMAND
  set -e
  cd "${REMOTE_DIR}/development"
  
  COMPOSE_CMD="docker compose -f ${COMPOSE_FILE}"
  REMOTE_OVERLAY="${COMPOSE_FILE%.yml}.remote.yml"
  if [ -f "\${REMOTE_OVERLAY}" ]; then
    COMPOSE_CMD="\${COMPOSE_CMD} -f \${REMOTE_OVERLAY}"
  fi

  \${COMPOSE_CMD} up -d --build
REMOTECOMMAND

# 4. Healthcheck
echo "[4/4] Verifying health check..."
ssh "${REMOTE_USER_HOST}" "bash -s" << 'REMOTECOMMAND'
  sleep 3
  curl -s -i -X POST http://localhost:8080/api/initialize -H "Content-Type: application/json" -d '{"payment_server":"http://host.docker.internal:12345"}' | head -n 10
REMOTECOMMAND

echo ""
echo "========================================================"
echo " [ISUCON14 Deploy] Deployment completed successfully!"
echo " Public URL: https://isucon14.ruu-dev.com"
echo "========================================================"
