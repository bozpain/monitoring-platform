#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
PROMTOOL="$BASE_DIR/prometheus/bin/promtool"
PROM_CONFIG="$BASE_DIR/prometheus/conf/prometheus.yml"
PROM_ALERT_DIR="$BASE_DIR/prometheus/conf/alerts"

WARNINGS=0
FAILURES=0

echo "======================================="
echo "[STEP] Platform Health Check"
echo "======================================="

mark_ok() {
  echo "[OK] $*"
}

mark_warn() {
  WARNINGS=$((WARNINGS + 1))
  echo "[WARN] $*"
}

mark_fail() {
  FAILURES=$((FAILURES + 1))
  echo "[FAIL] $*"
}

check_service_required() {
  local service=$1

  echo ""
  echo "[CHECK] service: $service"

  if systemctl is-active --quiet "$service"; then
    mark_ok "$service is running"
  else
    mark_fail "$service is not running"
    systemctl status "$service" --no-pager || true
  fi
}

check_service_optional() {
  local service=$1
  local env_file=$2
  local placeholder=$3

  echo ""
  echo "[CHECK] optional service: $service"

  if systemctl is-active --quiet "$service"; then
    mark_ok "$service is running"
    return
  fi

  if [ -f "$env_file" ] && grep -q "$placeholder" "$env_file"; then
    mark_warn "$service is not running because credential placeholder is still present in $env_file"
    return
  fi

  mark_warn "$service is not running"
  systemctl status "$service" --no-pager || true
}

check_port() {
  local port=$1
  local name=$2

  echo ""
  echo "[CHECK] port: $name :$port"

  if command -v ss >/dev/null 2>&1; then
    if ss -ltn | awk '{print $4}' | grep -Eq "(:|\\])$port$"; then
      mark_ok "$name listening on port $port"
    else
      mark_fail "$name is not listening on port $port"
    fi
    return
  fi

  if command -v netstat >/dev/null 2>&1; then
    if netstat -tuln | grep -q ":$port"; then
      mark_ok "$name listening on port $port"
    else
      mark_fail "$name is not listening on port $port"
    fi
    return
  fi

  mark_warn "Neither ss nor netstat found; cannot check port $port"
}

check_http_required() {
  local name=$1
  local url=$2

  echo ""
  echo "[CHECK] http: $name"

  if curl -fsS "$url" >/dev/null; then
    mark_ok "$name reachable: $url"
  else
    mark_fail "$name not reachable: $url"
  fi
}

check_http_optional() {
  local name=$1
  local url=$2

  echo ""
  echo "[CHECK] http optional: $name"

  if curl -fsS "$url" >/dev/null; then
    mark_ok "$name reachable: $url"
  else
    mark_warn "$name not reachable yet: $url"
  fi
}

check_prom_query_required() {
  local name=$1
  local query=$2

  echo ""
  echo "[CHECK] Prometheus query: $name"

  if curl -fsS -G "http://localhost:9090/api/v1/query" --data-urlencode "query=$query" | grep -q '"status":"success"'; then
    mark_ok "$name query successful"
  else
    mark_fail "$name query failed: $query"
  fi
}

check_prom_query_optional() {
  local name=$1
  local query=$2

  echo ""
  echo "[CHECK] Prometheus optional query: $name"

  if curl -fsS -G "http://localhost:9090/api/v1/query" --data-urlencode "query=$query" | grep -q '"status":"success"'; then
    mark_ok "$name query successful"
  else
    mark_warn "$name query failed or returned no data yet: $query"
  fi
}

echo ""
echo "[INFO] Checking required services..."

check_service_required victoriametrics
check_service_required alertmanager
check_service_required prometheus
check_service_required node_exporter
check_service_required grafana-server

check_service_optional oracle_exporter "$BASE_DIR/exporters/oracle/oracle_exporter.env" "CHANGE_ME"
check_service_optional mssql_exporter "$BASE_DIR/exporters/mssql/mssql_exporter.env" "CHANGE_ME"

echo ""
echo "[INFO] Checking required ports..."

check_port 8428 "VictoriaMetrics"
check_port 9093 "Alertmanager"
check_port 9090 "Prometheus"
check_port 9100 "Node Exporter"
check_port 3000 "Grafana"

echo ""
echo "[INFO] Checking optional exporter ports..."

if systemctl is-active --quiet oracle_exporter; then
  check_port 9161 "Oracle Exporter"
else
  mark_warn "Oracle Exporter port skipped because service is not running"
fi

if systemctl is-active --quiet mssql_exporter; then
  check_port 9182 "MSSQL Exporter"
else
  mark_warn "MSSQL Exporter port skipped because service is not running"
fi

echo ""
echo "[INFO] Checking HTTP endpoints..."

check_http_required "VictoriaMetrics health" "http://localhost:8428/health"
check_http_required "Alertmanager readiness" "http://localhost:9093/-/ready"
check_http_required "Prometheus readiness" "http://localhost:9090/-/ready"
check_http_required "Node exporter metrics" "http://localhost:9100/metrics"
check_http_required "Grafana health" "http://localhost:3000/api/health"

check_http_optional "Grafana metrics" "http://localhost:3000/metrics"
check_http_optional "Alertmanager status API" "http://localhost:9093/api/v2/status"

if systemctl is-active --quiet oracle_exporter; then
  check_http_optional "Oracle exporter metrics" "http://localhost:9161/metrics"
fi

if systemctl is-active --quiet mssql_exporter; then
  check_http_optional "MSSQL exporter metrics" "http://localhost:9182/metrics"
fi

echo ""
echo "[INFO] Checking Prometheus config and rules..."

if [ -x "$PROMTOOL" ]; then
  if "$PROMTOOL" check config "$PROM_CONFIG"; then
    mark_ok "Prometheus config is valid"
  else
    mark_fail "Prometheus config validation failed"
  fi

  if ls "$PROM_ALERT_DIR"/*.yml >/dev/null 2>&1; then
    if "$PROMTOOL" check rules "$PROM_ALERT_DIR"/*.yml; then
      mark_ok "Prometheus rules are valid"
    else
      mark_fail "Prometheus rule validation failed"
    fi
  else
    mark_warn "No Prometheus alert/rule files found in $PROM_ALERT_DIR"
  fi
else
  mark_warn "promtool not found or not executable: $PROMTOOL"
fi

echo ""
echo "[INFO] Checking scrape and storage path..."

check_prom_query_required "Prometheus self scrape" 'up{job="prometheus"}'
check_prom_query_required "VictoriaMetrics scrape" 'up{job="victoriametrics"}'
check_prom_query_required "Alertmanager scrape" 'up{job="alertmanager"}'
check_prom_query_required "Grafana scrape" 'up{job="grafana"}'
check_prom_query_optional "Node scrape" 'up{job="node"}'
check_prom_query_optional "Oracle scrape" 'up{job="oracle"}'
check_prom_query_optional "MSSQL scrape" 'up{job="mssql"}'

echo ""
echo "[INFO] Checking VictoriaMetrics remote-write data..."

if curl -fsS -G "http://localhost:8428/api/v1/query" --data-urlencode "query=up" | grep -q '"status":"success"'; then
  mark_ok "VictoriaMetrics query API returns data"
else
  mark_warn "VictoriaMetrics query API did not return expected data yet"
fi

echo ""
echo "[INFO] Checking disk usage..."
df -h "$BASE_DIR/data/prometheus" "$BASE_DIR/data/victoriametrics" "$BASE_DIR/data/alertmanager" 2>/dev/null || true

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "${IP:-}" ]; then
  IP="VM_IP"
fi

echo ""
echo "======================================="
echo "[SUMMARY] Health Check Result"
echo "======================================="
echo "Failures : $FAILURES"
echo "Warnings : $WARNINGS"

echo ""
echo "Access URLs:"
echo "Prometheus   : http://$IP:9090"
echo "Grafana      : http://$IP:3000"
echo "Alertmanager : http://$IP:9093"
echo "VictoriaMetrics: http://$IP:8428"

if [ "$FAILURES" -gt 0 ]; then
  echo ""
  echo "[RESULT] FAILED"
  echo "[NEXT] Check failed services with: journalctl -u <service> -n 100 --no-pager"
  exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
  echo ""
  echo "[RESULT] PASSED WITH WARNINGS"
  echo "[NEXT] Warnings are expected if Oracle/MSSQL credentials are not configured yet."
  exit 0
fi

echo ""
echo "[RESULT] PASSED"
