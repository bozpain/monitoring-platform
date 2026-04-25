#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
SRC_DIR="$BASE_DIR/sources/tar"

PROM_DIR="$BASE_DIR/prometheus"
BIN_DIR="$PROM_DIR/bin"
CONF_DIR="$PROM_DIR/conf"
ALERT_DIR="$CONF_DIR/alerts"
DATA_DIR="$BASE_DIR/data/prometheus"
LOG_DIR="$BASE_DIR/logs/prometheus"

SERVICE_SRC="./systemd/prometheus.service"
SERVICE_DST="/etc/systemd/system/prometheus.service"

echo "[INFO] Installing Prometheus..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

if ! id monitoring >/dev/null 2>&1; then
  echo "[ERROR] User 'monitoring' does not exist. Run 01_prepare_vm.sh first."
  exit 1
fi

PROM_TAR=$(ls "$SRC_DIR"/prometheus-*.linux-amd64.tar.gz 2>/dev/null | head -n 1 || true)

if [ -z "$PROM_TAR" ]; then
  echo "[ERROR] Prometheus tar.gz not found in $SRC_DIR"
  echo "[INFO] Expected: prometheus-*.linux-amd64.tar.gz"
  exit 1
fi

mkdir -p "$BIN_DIR" "$CONF_DIR" "$ALERT_DIR" "$DATA_DIR" "$LOG_DIR"

echo "[INFO] Extracting: $PROM_TAR"
TMP_DIR=$(mktemp -d)
tar -xzf "$PROM_TAR" -C "$TMP_DIR"

PROM_EXTRACT_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name "prometheus-*.linux-amd64" | head -n 1 || true)

if [ -z "$PROM_EXTRACT_DIR" ]; then
  echo "[ERROR] Prometheus extracted directory not found"
  rm -rf "$TMP_DIR"
  exit 1
fi

cp "$PROM_EXTRACT_DIR/prometheus" "$BIN_DIR/"
cp "$PROM_EXTRACT_DIR/promtool" "$BIN_DIR/"

rm -rf "$TMP_DIR"

echo "[INFO] Installing Prometheus config..."
cp ./config/prometheus.yml "$CONF_DIR/prometheus.yml"

echo "[INFO] Installing alert rules..."
if [ -d ./config/alerts ]; then
  cp ./config/alerts/*.yml "$ALERT_DIR/" 2>/dev/null || true
else
  echo "[WARN] ./config/alerts not found, skipping alert rules"
fi

chmod +x "$BIN_DIR/prometheus" "$BIN_DIR/promtool"
chown -R monitoring:monitoring "$PROM_DIR" "$DATA_DIR" "$LOG_DIR"

echo "[INFO] Validating Prometheus config..."
"$BIN_DIR/promtool" check config "$CONF_DIR/prometheus.yml"

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

echo "[INFO] Installing systemd service..."
cp "$SERVICE_SRC" "$SERVICE_DST"

systemctl daemon-reload
systemctl enable prometheus
systemctl restart prometheus

echo "[INFO] Checking service..."
systemctl status prometheus --no-pager

echo "[INFO] Testing endpoint..."
curl -s http://localhost:9090/-/ready >/dev/null

echo "[DONE] Prometheus installed successfully"
