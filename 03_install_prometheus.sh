#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
SRC_DIR="$BASE_DIR/sources/tar"
BIN_DIR="$BASE_DIR/prometheus/bin"
CONF_DIR="$BASE_DIR/prometheus/conf"
DATA_DIR="$BASE_DIR/data/prometheus"
LOG_DIR="$BASE_DIR/logs/prometheus"

SERVICE_SRC="./systemd/prometheus.service"
SERVICE_DST="/etc/systemd/system/prometheus.service"

echo "[INFO] Installing Prometheus..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

PROM_TAR=$(ls "$SRC_DIR"/prometheus-*.tar.gz 2>/dev/null | head -n 1 || true)

if [ -z "$PROM_TAR" ]; then
  echo "[ERROR] Prometheus tar.gz not found in $SRC_DIR"
  exit 1
fi

mkdir -p "$BIN_DIR" "$CONF_DIR" "$DATA_DIR" "$LOG_DIR"

echo "[INFO] Extracting $PROM_TAR"
tar -xzf "$PROM_TAR" -C "$BASE_DIR/prometheus"

mv "$BASE_DIR"/prometheus-*/prometheus "$BIN_DIR/"
mv "$BASE_DIR"/prometheus-*/promtool "$BIN_DIR/"

cp ./config/prometheus.yml "$CONF_DIR/"

chmod +x "$BIN_DIR/prometheus"
chown -R monitoring:monitoring "$BASE_DIR/prometheus" "$DATA_DIR" "$LOG_DIR"

echo "[INFO] Installing systemd service..."
cp "$SERVICE_SRC" "$SERVICE_DST"

systemctl daemon-reload
systemctl enable prometheus
systemctl restart prometheus

echo "[INFO] Checking service..."
systemctl status prometheus --no-pager

echo "[DONE] Prometheus installed successfully"
