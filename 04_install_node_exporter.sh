#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
SRC_DIR="$BASE_DIR/sources/tar"

NODE_DIR="$BASE_DIR/exporters/node"
LOG_DIR="$BASE_DIR/logs/exporters"

SERVICE_SRC="./systemd/node_exporter.service"
SERVICE_DST="/etc/systemd/system/node_exporter.service"

echo "[INFO] Installing Node Exporter..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

if ! id monitoring >/dev/null 2>&1; then
  echo "[ERROR] User 'monitoring' does not exist. Run 01_prepare_vm.sh first."
  exit 1
fi

NODE_TAR=$(ls "$SRC_DIR"/node_exporter*.tar.gz 2>/dev/null | head -n 1 || true)

if [ -z "$NODE_TAR" ]; then
  echo "[ERROR] Node Exporter tar.gz not found in $SRC_DIR"
  echo "[INFO] Expected: node_exporter*.tar.gz"
  exit 1
fi

mkdir -p "$NODE_DIR" "$LOG_DIR"

echo "[INFO] Extracting: $NODE_TAR"
tar -xzf "$NODE_TAR" -C "$NODE_DIR" --strip-components=1

if [ ! -f "$NODE_DIR/node_exporter" ]; then
  echo "[ERROR] node_exporter binary not found after extraction"
  exit 1
fi

chmod +x "$NODE_DIR/node_exporter"

echo "[INFO] Installing systemd service..."

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

cp "$SERVICE_SRC" "$SERVICE_DST"

chown -R monitoring:monitoring "$NODE_DIR"
chown -R monitoring:monitoring "$LOG_DIR"

systemctl daemon-reload
systemctl enable node_exporter
systemctl restart node_exporter

echo "[INFO] Checking service..."
systemctl status node_exporter --no-pager

echo "[INFO] Testing endpoint..."
curl -fsS http://localhost:9100/metrics >/dev/null

echo "[DONE] Node Exporter installed successfully"
echo "[INFO] Metrics endpoint: http://localhost:9100/metrics"
