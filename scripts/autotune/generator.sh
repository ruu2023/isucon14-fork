#!/bin/sh
set -eu

candidate="${1:?candidate is required}"
case "$candidate" in
  payment-check-retry)
    echo "already-applied:d0f0b7cb"
    ;;
  matcher-batch-size-1)
    sed -i '' -E 's/LIMIT [0-9]+",/LIMIT 1",/' webapp/nodejs/src/internal_handlers.ts
    ;;
  matcher-batch-size-5)
    sed -i '' -E 's/LIMIT [0-9]+",/LIMIT 5",/' webapp/nodejs/src/internal_handlers.ts
    ;;
  matcher-batch-size-10)
    sed -i '' -E 's/LIMIT [0-9]+",/LIMIT 10",/' webapp/nodejs/src/internal_handlers.ts
    ;;
  matcher-batch-size-20)
    sed -i '' -E 's/LIMIT [0-9]+",/LIMIT 20",/' webapp/nodejs/src/internal_handlers.ts
    ;;
  matcher-batch-size-50)
    sed -i '' -E 's/LIMIT [0-9]+",/LIMIT 50",/' webapp/nodejs/src/internal_handlers.ts
    ;;
  *)
    echo "unknown candidate: $candidate" >&2
    exit 1
    ;;
esac
