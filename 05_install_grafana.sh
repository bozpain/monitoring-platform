#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
RPM_DIR="$BASE_DIR/sources/rpm"

GRAFANA_DIR="$BASE_DIR/grafana"
LOG_DIR="$BASE_DIR/logs/grafana"
CONF_BACKUP_DIR="$GRAFANA_DIR/conf"
DASHBOARD_DIR="$GRAFANA_DIR/dashboards"

GRAFANA_PROVISIONING_SRC="./grafana/provisioning"
GRAFANA_DASHBOARDS_SRC="./grafana/dashboards"
ENV_SRC="./config/grafana/grafana.env.example"
ENV_DST="$CONF_BACKUP_DIR/grafana.env"

SERVICE_SRC="./systemd/grafana.service"
SERVICE_DST="/etc/systemd/system/grafana-server.service"

echo "[INFO] Installing Grafana..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

if ! id monitoring >/dev/null 2>&1; then
  echo "[ERROR] User 'monitoring' does not exist. Run 01_prepare_vm.sh first."
  exit 1
fi

GRAFANA_RPM=$(ls "$RPM_DIR"/grafana-*.rpm 2>/dev/null | head -n 1 || true)

if [ -z "$GRAFANA_RPM" ]; then
  echo "[ERROR] Grafana RPM not found in $RPM_DIR"
  echo "[INFO] Expected: grafana-*.rpm"
  exit 1
fi

echo "[INFO] Preparing directories..."

mkdir -p "$LOG_DIR"
mkdir -p "$CONF_BACKUP_DIR"
mkdir -p "$DASHBOARD_DIR"

mkdir -p /etc/grafana/provisioning/datasources
mkdir -p /etc/grafana/provisioning/dashboards

echo "[INFO] Installing RPM: $GRAFANA_RPM"

if command -v dnf >/dev/null 2>&1; then
  dnf install -y "$GRAFANA_RPM"
elif command -v yum >/dev/null 2>&1; then
  yum localinstall -y "$GRAFANA_RPM"
else
  echo "[ERROR] dnf/yum not found"
  exit 1
fi

echo "[INFO] Backing up Grafana config..."

if [ -f /etc/grafana/grafana.ini ]; then
  cp /etc/grafana/grafana.ini "$CONF_BACKUP_DIR/grafana.ini.bak.$(date +%Y%m%d_%H%M%S)"
else
  echo "[WARN] /etc/grafana/grafana.ini not found, skipping backup"
fi

echo "[INFO] Installing Grafana runtime env..."

if [ -f "$ENV_DST" ]; then
  cp "$ENV_DST" "$ENV_DST.bak.$(date +%Y%m%d_%H%M%S)"
fi

if [ -f "$ENV_SRC" ]; then
  cp "$ENV_SRC" "$ENV_DST"
else
  cat > "$ENV_DST" <<'EOF'
GF_SERVER_HTTP_ADDR=0.0.0.0
GF_SERVER_HTTP_PORT=3000
GF_SERVER_DOMAIN=localhost
GF_SERVER_ROOT_URL=http://localhost:3000/
GF_LOG_LEVEL=info
GF_USERS_ALLOW_SIGN_UP=false
GF_USERS_ALLOW_ORG_CREATE=false
GF_AUTH_ANONYMOUS_ENABLED=false
GF_SECURITY_DISABLE_GRAVATAR=true
GF_ANALYTICS_REPORTING_ENABLED=false
GF_ANALYTICS_CHECK_FOR_UPDATES=false
GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false
GF_SNAPSHOTS_EXTERNAL_ENABLED=false
GF_METRICS_ENABLED=true
GF_DASHBOARDS_MIN_REFRESH_INTERVAL=30s
GF_QUERY_CONCURRENT_QUERY_LIMIT=20
EOF
fi

chmod 640 "$ENV_DST"

echo "[INFO] Installing Grafana provisioning..."

if [ -d "$GRAFANA_PROVISIONING_SRC/datasources" ]; then
  if ! ls "$GRAFANA_PROVISIONING_SRC"/datasources/*.yml >/dev/null 2>&1; then
    echo "[ERROR] No Grafana datasource provisioning files found"
    exit 1
  fi
  find /etc/grafana/provisioning/datasources -type f -name "*.yml" -delete
  cp "$GRAFANA_PROVISIONING_SRC"/datasources/*.yml /etc/grafana/provisioning/datasources/
else
  echo "[ERROR] Grafana datasource provisioning directory not found: $GRAFANA_PROVISIONING_SRC/datasources"
  exit 1
fi

if [ -d "$GRAFANA_PROVISIONING_SRC/dashboards" ]; then
  if ! ls "$GRAFANA_PROVISIONING_SRC"/dashboards/*.yml >/dev/null 2>&1; then
    echo "[ERROR] No Grafana dashboard provisioning files found"
    exit 1
  fi
  find /etc/grafana/provisioning/dashboards -type f -name "*.yml" -delete
  cp "$GRAFANA_PROVISIONING_SRC"/dashboards/*.yml /etc/grafana/provisioning/dashboards/
else
  echo "[ERROR] Grafana dashboard provisioning directory not found: $GRAFANA_PROVISIONING_SRC/dashboards"
  exit 1
fi

echo "[INFO] Installing Grafana dashboards..."

if [ -d "$GRAFANA_DASHBOARDS_SRC" ]; then
  if ! find "$GRAFANA_DASHBOARDS_SRC" -type f -name "*.json" | grep -q .; then
    echo "[ERROR] No Grafana dashboard JSON files found"
    exit 1
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$GRAFANA_DASHBOARDS_SRC" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for path in root.rglob("*.json"):
    with path.open(encoding="utf-8") as handle:
        json.load(handle)
print("[INFO] Grafana dashboard JSON validation OK")
PY
  else
    echo "[WARN] python3 not found, skipping dashboard JSON validation"
  fi

  rm -rf "$DASHBOARD_DIR"
  mkdir -p "$DASHBOARD_DIR"

  cp -r "$GRAFANA_DASHBOARDS_SRC"/* "$DASHBOARD_DIR"/
else
  echo "[ERROR] Grafana dashboards directory not found: $GRAFANA_DASHBOARDS_SRC"
  exit 1
fi

echo "[INFO] Installing custom systemd service..."

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

cp "$SERVICE_SRC" "$SERVICE_DST"

echo "[INFO] Setting ownership..."

chown -R grafana:grafana "$LOG_DIR"
chown -R grafana:grafana /etc/grafana/provisioning
chown -R grafana:grafana "$DASHBOARD_DIR"
chown -R monitoring:monitoring "$CONF_BACKUP_DIR"
chown root:grafana "$ENV_DST"

echo "[INFO] Reloading systemd..."

echo "[INFO] Validating systemd unit..."
systemd-analyze verify "$SERVICE_DST" || true

systemctl daemon-reload
systemctl enable grafana-server
systemctl restart grafana-server

echo "[INFO] Checking service..."
systemctl status grafana-server --no-pager

echo "[INFO] Testing Grafana endpoint..."

GRAFANA_READY=false
for _ in $(seq 1 30); do
  if curl -fsS http://localhost:3000/api/health >/dev/null; then
    GRAFANA_READY=true
    break
  fi
  sleep 2
done

if [ "$GRAFANA_READY" = true ]; then
  echo "[INFO] Grafana endpoint OK"
else
  echo "[WARN] Grafana endpoint test failed. Check: journalctl -u grafana-server -f"
fi

echo "[INFO] Checking Grafana metrics endpoint..."
curl -fsS http://localhost:3000/metrics >/dev/null || true

echo "[INFO] Installed dashboard files:"
find "$DASHBOARD_DIR" -type f -name "*.json" | wc -l

echo "[DONE] Grafana installed successfully"
echo "[INFO] Default login: admin / admin"
echo "[INFO] Grafana URL: http://localhost:3000"
echo "[INFO] Grafana env: $ENV_DST"
echo "[INFO] Datasource provisioning: /etc/grafana/provisioning/datasources"
echo "[INFO] Dashboard provisioning: /etc/grafana/provisioning/dashboards"
echo "[INFO] Dashboard files: $DASHBOARD_DIR"
