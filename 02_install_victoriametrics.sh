#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
SRC_DIR="$BASE_DIR/sources/tar"
BIN_DIR="$BASE_DIR/victoriametrics/bin"
DATA_DIR="$BASE_DIR/data/victoriametrics"
LOG_DIR="$BASE_DIR/logs/victoriametrics"
SERVICE_SRC="./systemd/victoriametrics.service"
SERVICE_DST="/etc/systemd/system/victoriametrics.service"

echo "[INFO] Installing VictoriaMetrics..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

if ! id monitoring >/dev/null 2>&1; then
  echo "[ERROR] User 'monitoring' does not exist. Run 01_prepare_vm.sh first."
  exit 1
fi

VM_TAR=$(ls "$SRC_DIR"/victoria-metrics-linux-amd64-*.tar.gz 2>/dev/null | head -n 1 || true)

if [ -z "$VM_TAR" ]; then
  echo "[ERROR] VictoriaMetrics tar.gz not found in $SRC_DIR"
  echo "[INFO] Expected: victoria-metrics-linux-amd64-*.tar.gz"
  exit 1
fi

mkdir -p "$BIN_DIR" "$DATA_DIR" "$LOG_DIR"

echo "[INFO] Extracting: $VM_TAR"
tar -xzf "$VM_TAR" -C "$BIN_DIR"

if [ ! -f "$BIN_DIR/victoria-metrics-prod" ]; then
  echo "[ERROR] victoria-metrics-prod binary not found after extract"
  exit 1
fi

chmod +x "$BIN_DIR/victoria-metrics-prod"
chown -R monitoring:monitoring "$BASE_DIR/victoriametrics" "$DATA_DIR" "$LOG_DIR"

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

echo "[INFO] Installing systemd service..."
cp "$SERVICE_SRC" "$SERVICE_DST"

systemctl daemon-reload
systemctl enable victoriametrics
systemctl restart victoriametrics

echo "[INFO] Checking service..."
systemctl status victoriametrics --no-pager

echo "[INFO] Testing endpoint..."
curl -s http://localhost:8428/metrics >/dev/null

echo "[DONE] VictoriaMetrics installed successfully"
