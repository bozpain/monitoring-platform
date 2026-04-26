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

echo "[INFO] Installing Grafana provisioning..."

if [ -d "$GRAFANA_PROVISIONING_SRC/datasources" ]; then
  find /etc/grafana/provisioning/datasources -type f -name "*.yml" -delete
  cp "$GRAFANA_PROVISIONING_SRC"/datasources/*.yml /etc/grafana/provisioning/datasources/
else
  echo "[ERROR] Grafana datasource provisioning directory not found: $GRAFANA_PROVISIONING_SRC/datasources"
  exit 1
fi

if [ -d "$GRAFANA_PROVISIONING_SRC/dashboards" ]; then
  find /etc/grafana/provisioning/dashboards -type f -name "*.yml" -delete
  cp "$GRAFANA_PROVISIONING_SRC"/dashboards/*.yml /etc/grafana/provisioning/dashboards/
else
  echo "[ERROR] Grafana dashboard provisioning directory not found: $GRAFANA_PROVISIONING_SRC/dashboards"
  exit 1
fi

echo "[INFO] Installing Grafana dashboards..."

if [ -d "$GRAFANA_DASHBOARDS_SRC" ]; then
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

echo "[INFO] Reloading systemd..."

systemctl daemon-reload
systemctl enable grafana-server
systemctl restart grafana-server

echo "[INFO] Checking service..."
systemctl status grafana-server --no-pager

echo "[INFO] Testing Grafana endpoint..."

if curl -fsS http://localhost:3000 >/dev/null; then
  echo "[INFO] Grafana endpoint OK"
else
  echo "[WARN] Grafana endpoint test failed. Check: journalctl -u grafana-server -f"
fi

echo "[DONE] Grafana installed successfully"
echo "[INFO] Default login: admin / admin"
echo "[INFO] Grafana URL: http://localhost:3000"
echo "[INFO] Datasource provisioning: /etc/grafana/provisioning/datasources"
echo "[INFO] Dashboard provisioning: /etc/grafana/provisioning/dashboards"
echo "[INFO] Dashboard files: $DASHBOARD_DIR"
