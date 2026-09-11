#!/bin/sh
set -eu

STATE_DIR="${AUTOTUNE_STATE_DIR:-$PWD/.autotune}"
mkdir -p "$STATE_DIR"

TARGET_SCORE="${TARGET_SCORE:-10000}"
CURRENT_SCORE="${CURRENT_SCORE:-7477}"

if [ "$CURRENT_SCORE" -ge "$TARGET_SCORE" ]; then
  echo "goal-reached"
  exit 0
fi

for candidate in payment-check-retry matcher-batch-size-5 matcher-batch-size-20; do
  if ! grep -Fxq "$candidate" "$STATE_DIR/tried" 2>/dev/null; then
    echo "$candidate"
    exit 0
  fi
done

echo "no-candidates"
