#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
RPM_DIR="$BASE_DIR/sources/rpm"

GRAFANA_DIR="$BASE_DIR/grafana"
LOG_DIR="$BASE_DIR/logs/grafana"
CONF_BACKUP_DIR="$GRAFANA_DIR/conf"
DASHBOARD_DIR="$GRAFANA_DIR/dashboards"

SERVICE_SRC="./systemd/grafana.service"
SERVICE_DST="/etc/systemd/system/grafana-server.service"

echo "[INFO] Installing Grafana..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

GRAFANA_RPM=$(ls "$RPM_DIR"/grafana-*.rpm 2>/dev/null | head -n 1 || true)

if [ -z "$GRAFANA_RPM" ]; then
  echo "[ERROR] Grafana RPM not found in $RPM_DIR"
  echo "[INFO] Expected: grafana-*.rpm"
  exit 1
fi

mkdir -p "$LOG_DIR" "$CONF_BACKUP_DIR" "$DASHBOARD_DIR"

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
cp /etc/grafana/grafana.ini "$CONF_BACKUP_DIR/grafana.ini.bak.$(date +%Y%m%d_%H%M%S)" || true

echo "[INFO] Installing Grafana provisioning..."

mkdir -p /etc/grafana/provisioning/datasources
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p "$DASHBOARD_DIR"

if [ -d ./grafana/provisioning/datasources ]; then
  cp ./grafana/provisioning/datasources/*.yml /etc/grafana/provisioning/datasources/ 2>/dev/null || true
else
  echo "[WARN] Grafana datasource provisioning directory not found"
fi

if [ -d ./grafana/provisioning/dashboards ]; then
  cp ./grafana/provisioning/dashboards/*.yml /etc/grafana/provisioning/dashboards/ 2>/dev/null || true
else
  echo "[WARN] Grafana dashboard provisioning directory not found"
fi

if [ -d ./grafana/dashboards ]; then
  cp ./grafana/dashboards/*.json "$DASHBOARD_DIR/" 2>/dev/null || true
else
  echo "[WARN] Grafana dashboards directory not found"
fi

echo "[INFO] Installing custom systemd service..."

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

cp "$SERVICE_SRC" "$SERVICE_DST"

chown -R grafana:grafana "$LOG_DIR"
chown -R grafana:grafana /etc/grafana/provisioning
chown -R grafana:grafana "$DASHBOARD_DIR"
chown -R monitoring:monitoring "$CONF_BACKUP_DIR"

systemctl daemon-reload
systemctl enable grafana-server
systemctl restart grafana-server

echo "[INFO] Checking service..."
systemctl status grafana-server --no-pager

echo "[INFO] Testing endpoint..."
curl -s http://localhost:3000 >/dev/null

echo "[DONE] Grafana installed successfully"
echo "[INFO] Default login: admin / admin"
echo "[INFO] Datasource provisioning: /etc/grafana/provisioning/datasources"
echo "[INFO] Dashboard provisioning: /etc/grafana/provisioning/dashboards"
echo "[INFO] Dashboard files: $DASHBOARD_DIR"
