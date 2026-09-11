#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
STATE_DIR="${AUTOTUNE_STATE_DIR:-$ROOT/.autotune}"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/tried"

target="${TARGET_SCORE:-10000}"
current="${CURRENT_SCORE:-7477}"

while [ "$current" -lt "$target" ]; do
  candidate=$(CURRENT_SCORE="$current" TARGET_SCORE="$target" ./scripts/autotune/planner.sh)
  case "$candidate" in
    goal-reached|no-candidates)
      echo "$candidate current=$current target=$target"
      exit 0
      ;;
  esac

  printf '%s\n' "$candidate" >> "$STATE_DIR/tried"
  ./scripts/autotune/generator.sh "$candidate"
  ./scripts/autotune/evaluator.sh "$candidate"
  current=$(tail -1 "$STATE_DIR/results.tsv" | awk -F '\t' '{print $2}')
done

echo "goal-reached score=$current target=$target"
