#!/bin/bash
set -euo pipefail

# ==============================================================================
# ISUCON14 Benchmark Runner
# ==============================================================================

REMOTE_USER_HOST="${REMOTE_HOST:-win-note@100.109.170.11}"
REMOTE_DIR="${REMOTE_DIR:-/home/win-note/isucon14}"

echo "========================================================"
echo " [ISUCON14 Bench] Starting benchmark on ${REMOTE_USER_HOST}"
echo "========================================================"

ssh -t "${REMOTE_USER_HOST}" "cd ${REMOTE_DIR} && ./bench-with-slowlog.sh $*"

echo ""
echo "========================================================"
echo " [ISUCON14 Bench] Benchmark completed!"
echo "========================================================"
