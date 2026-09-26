#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
HOME_DIR="${HOME:-/home/win-note}"
SLOW_LOGDIR="${HOME_DIR}/slow-logs"
ALP_LOGDIR="${HOME_DIR}/access-logs"
mkdir -p "$SLOW_LOGDIR" "$ALP_LOGDIR"

NGINX_LOG="${HOME_DIR}/isucon14/development/nginx/logs/access_ltsv.log"

SLOW_LOG_FILE=$(docker exec development-db-1 mysql -N -s -uroot -pisucon \
  -e "SELECT @@global.slow_query_log_file" 2>/dev/null || true)

echo "[1/6] ログの初期化（MySQLスロークエリログ & Nginxアクセスログ）"
if [ -n "$SLOW_LOG_FILE" ]; then
  docker exec development-db-1 sh -c "> '$SLOW_LOG_FILE'" 2>/dev/null || true
  docker exec development-db-1 mysql -uroot -pisucon -e "SET GLOBAL slow_query_log = 1; SET GLOBAL long_query_time = 0;" 2>/dev/null || true
fi

mkdir -p "$(dirname "$NGINX_LOG")"
chmod 777 "$(dirname "$NGINX_LOG")" 2>/dev/null || true
> "$NGINX_LOG" 2>/dev/null || true
chmod 666 "$NGINX_LOG" 2>/dev/null || true
if docker ps --format "{{.Names}}" | grep -q "nginx"; then
  docker exec nginx nginx -s reopen 2>/dev/null || true
fi

echo "[2/6] webappコンテナを再起動(新しいDB接続で記録させるため)"
docker restart development-webapp-1 > /dev/null
sleep 3
if docker ps --format "{{.Names}}" | grep -q "^nginx$"; then
  docker exec nginx nginx -s reload 2>/dev/null || true
fi
for i in $(seq 1 20); do
  if curl -fsS -o /dev/null http://localhost:8080/index.html; then
    break
  fi
  sleep 1
done

echo "[3/6] ベンチマーク実行"
~/isucon14/bench.sh "$@"

echo "[4/6] ログの停止とホストへの保存"
if [ -n "$SLOW_LOG_FILE" ]; then
  docker exec development-db-1 mysql -uroot -pisucon -e "SET GLOBAL slow_query_log = 0;" 2>/dev/null || true
  docker cp "development-db-1:$SLOW_LOG_FILE" "$SLOW_LOGDIR/slow-$TIMESTAMP.log" 2>/dev/null || true
fi

if [ -f "$NGINX_LOG" ]; then
  cp "$NGINX_LOG" "$ALP_LOGDIR/access-$TIMESTAMP.log"
elif docker ps --format "{{.Names}}" | grep -q "nginx"; then
  docker cp "nginx:/var/log/nginx/access_ltsv.log" "$ALP_LOGDIR/access-$TIMESTAMP.log" 2>/dev/null || true
fi

echo ""
echo "========================================================"
echo " [Nginx Access Log: alp 解析 (Top by Sum Time)]"
echo "========================================================"
MATCH_GROUPS="/api/app/rides/[0-9a-zA-Z]+/evaluation,/api/chair/rides/[0-9a-zA-Z]+/status,/api/app/rides/estimated-fare,/api/app/nearby-chairs.*,/api/owner/sales.*,/assets/.+,/images/.+"
if [ -f "$ALP_LOGDIR/access-$TIMESTAMP.log" ] && [ -s "$ALP_LOGDIR/access-$TIMESTAMP.log" ]; then
  ~/bin/alp ltsv \
    --file="$ALP_LOGDIR/access-$TIMESTAMP.log" \
    --sort=sum -r \
    -m "$MATCH_GROUPS" | tee "$ALP_LOGDIR/alp-summary-$TIMESTAMP.txt"
else
  echo "アクセスログが空または見つかりませんでした: $ALP_LOGDIR/access-$TIMESTAMP.log"
fi

echo ""
echo "========================================================"
echo " [MySQL Slow Query Log: pt-query-digest (Top Queries)]"
echo "========================================================"
if [ -f "$SLOW_LOGDIR/slow-$TIMESTAMP.log" ] && [ -s "$SLOW_LOGDIR/slow-$TIMESTAMP.log" ]; then
  ~/bin/pt-query-digest "$SLOW_LOGDIR/slow-$TIMESTAMP.log" > "$SLOW_LOGDIR/report-$TIMESTAMP.txt"
  head -40 "$SLOW_LOGDIR/report-$TIMESTAMP.txt"
else
  echo "スロークエリログが空または見つかりませんでした"
fi

echo ""
echo "ログ保存先:"
echo "  Nginx Access: $ALP_LOGDIR/access-$TIMESTAMP.log"
echo "  alp 解析結果: $ALP_LOGDIR/alp-summary-$TIMESTAMP.txt"
echo "  MySQL Slow:   $SLOW_LOGDIR/slow-$TIMESTAMP.log"
echo "  pt 解析結果:  $SLOW_LOGDIR/report-$TIMESTAMP.txt"
