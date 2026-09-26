# ==============================================================================
# ISUCON14 Operations Makefile
# ==============================================================================

REMOTE_HOST ?= win-note@100.109.170.11
REMOTE_DIR ?= /home/win-note/isucon14
COMPOSE_FILE ?= compose-node.yml

.PHONY: help deploy bench deploy-bench logs ps ssh restart init

help:
	@echo "Available commands:"
	@echo "  make deploy        - Sync code to remote and rebuild/restart containers (default: Node.js)"
	@echo "  make bench         - Run benchmark with slow query & alp access logging on remote"
	@echo "  make deploy-bench  - Deploy and immediately run benchmark"
	@echo "  make alp           - View latest alp analysis sorted by sum time"
	@echo "  make alp-avg       - View latest alp analysis sorted by average time"
	@echo "  make explain-old   - Run EXPLAIN ANALYZE on Old SQL"
	@echo "  make explain-new   - Run EXPLAIN ANALYZE on New CTE SQL"
	@echo "  make logs          - Tail all container logs (or specify service: make logs s=webapp)"
	@echo "  make ps            - Check running container status on remote"
	@echo "  make ssh           - SSH directly into remote host"
	@echo "  make restart       - Restart containers on remote without rebuild"

deploy:
	@REMOTE_HOST=$(REMOTE_HOST) REMOTE_DIR=$(REMOTE_DIR) COMPOSE_FILE=$(COMPOSE_FILE) ./scripts/deploy.sh

bench:
	@REMOTE_HOST=$(REMOTE_HOST) REMOTE_DIR=$(REMOTE_DIR) ./scripts/bench.sh $(ARGS)

deploy-bench: deploy bench

alp:
	@ssh $(REMOTE_HOST) '~/bin/alp ltsv --file=$$(ls -t ~/access-logs/access-*.log 2>/dev/null | head -1) --sort=sum -r -m "/api/app/rides/[0-9a-zA-Z]+/evaluation,/api/chair/rides/[0-9a-zA-Z]+/status,/api/app/rides/estimated-fare,/api/app/nearby-chairs.*,/api/owner/sales.*,/assets/.+,/images/.+"'

alp-avg:
	@ssh $(REMOTE_HOST) '~/bin/alp ltsv --file=$$(ls -t ~/access-logs/access-*.log 2>/dev/null | head -1) --sort=avg -r -m "/api/app/rides/[0-9a-zA-Z]+/evaluation,/api/chair/rides/[0-9a-zA-Z]+/status,/api/app/rides/estimated-fare,/api/app/nearby-chairs.*,/api/owner/sales.*,/assets/.+,/images/.+"'

explain-old:
	@ssh $(REMOTE_HOST) 'docker exec development-db-1 mysql -uisucon -pisucon isuride -e "EXPLAIN ANALYZE SELECT id, owner_id, name, access_token, model, is_active, created_at, updated_at, IFNULL(total_distance, 0) AS total_distance, total_distance_updated_at FROM chairs LEFT JOIN (SELECT chair_id, SUM(IFNULL(distance, 0)) AS total_distance, MAX(created_at) AS total_distance_updated_at FROM (SELECT chair_id, created_at, ABS(latitude - LAG(latitude) OVER (PARTITION BY chair_id ORDER BY created_at)) + ABS(longitude - LAG(longitude) OVER (PARTITION BY chair_id ORDER BY created_at)) AS distance FROM chair_locations) tmp GROUP BY chair_id) distance_table ON distance_table.chair_id = chairs.id WHERE owner_id = '\''01JDFEDF008NTA922W12FS7800'\'';"' | while IFS= read -r line; do printf '%b\n' "$$line"; done

explain-new:
	@ssh $(REMOTE_HOST) 'docker exec development-db-1 mysql -uisucon -pisucon isuride -e "EXPLAIN ANALYZE WITH owned_chairs AS (SELECT * FROM chairs WHERE owner_id = '\''01JDFEDF008NTA922W12FS7800'\''), distance_table AS (SELECT chair_id, SUM(IFNULL(distance, 0)) AS total_distance, MAX(created_at) AS total_distance_updated_at FROM (SELECT cl.chair_id, cl.created_at, ABS(cl.latitude - LAG(cl.latitude) OVER (PARTITION BY cl.chair_id ORDER BY cl.created_at)) + ABS(cl.longitude - LAG(cl.longitude) OVER (PARTITION BY cl.chair_id ORDER BY cl.created_at)) AS distance FROM chair_locations AS cl INNER JOIN owned_chairs AS oc ON oc.id = cl.chair_id) AS locations_with_distance GROUP BY chair_id) SELECT oc.id, oc.owner_id, oc.name, oc.access_token, oc.model, oc.is_active, oc.created_at, oc.updated_at, IFNULL(dt.total_distance, 0) AS total_distance, dt.total_distance_updated_at FROM owned_chairs AS oc LEFT JOIN distance_table AS dt ON dt.chair_id = oc.id;"' | while IFS= read -r line; do printf '%b\n' "$$line"; done

explain-notify:
	@ssh $(REMOTE_HOST) 'docker exec development-db-1 mysql -uisucon -pisucon isuride -e "EXPLAIN SELECT * FROM rides WHERE chair_id = '\''01JDFEDF008NTA922W12FS7800'\'' ORDER BY updated_at DESC LIMIT 1; EXPLAIN SELECT * FROM ride_statuses WHERE ride_id = '\''01M18W0123456789ABCDEFGHJK'\'' AND chair_sent_at IS NULL ORDER BY created_at ASC LIMIT 1;"'

logs:
	@REMOTE_HOST=$(REMOTE_HOST) REMOTE_DIR=$(REMOTE_DIR) COMPOSE_FILE=$(COMPOSE_FILE) ./scripts/logs.sh $(s)

ps:
	@ssh $(REMOTE_HOST) "cd $(REMOTE_DIR)/development && docker compose -f $(COMPOSE_FILE) ps"

ssh:
	@ssh -t $(REMOTE_HOST) "cd $(REMOTE_DIR) && exec bash -l"

restart:
	@ssh $(REMOTE_HOST) "cd $(REMOTE_DIR)/development && docker compose -f $(COMPOSE_FILE) restart webapp nginx matcher"

