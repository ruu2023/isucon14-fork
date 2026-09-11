#!/bin/sh
set -eu

candidate="${1:?candidate is required}"
STATE_DIR="${AUTOTUNE_STATE_DIR:-$PWD/.autotune}"
mkdir -p "$STATE_DIR"

if [ "$candidate" = "payment-check-retry" ]; then
  echo "candidate already evaluated: $candidate"
  exit 0
fi

./webapp/nodejs/node_modules/.bin/tsc --noEmit
git add webapp/nodejs/src/internal_handlers.ts
git commit -m "perf: tune matcher batch size ($candidate)"
./scripts/deploy.sh
./scripts/bench.sh | tee "$STATE_DIR/$candidate.log"
score=$(sed -n 's/.*結果 pass=.*スコア=\([0-9][0-9]*\).*/\1/p' "$STATE_DIR/$candidate.log" | tail -1)
errors=$(sed -n 's/.*種別エラー数=\(.*\)$/\1/p' "$STATE_DIR/$candidate.log" | tail -1)
printf '%s\t%s\t%s\n' "$candidate" "${score:-0}" "${errors:-unknown}" >> "$STATE_DIR/results.tsv"
echo "candidate=$candidate score=${score:-0} errors=${errors:-unknown}"
