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

NODE_TAR=$(ls "$SRC_DIR"/node_exporter-*.linux-amd64.tar.gz 2>/dev/null | head -n 1 || true)

if [ -z "$NODE_TAR" ]; then
  echo "[ERROR] Node Exporter tar.gz not found in $SRC_DIR"
  echo "[INFO] Expected: node_exporter-*.linux-amd64.tar.gz"
  exit 1
fi

mkdir -p "$NODE_DIR" "$LOG_DIR"

echo "[INFO] Extracting: $NODE_TAR"
TMP_DIR=$(mktemp -d)
tar -xzf "$NODE_TAR" -C "$TMP_DIR"

cp "$TMP_DIR"/node_exporter-*.linux-amd64/node_exporter "$NODE_DIR/"
rm -rf "$TMP_DIR"

chmod +x "$NODE_DIR/node_exporter"
chown -R monitoring:monitoring "$NODE_DIR" "$LOG_DIR"

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

echo "[INFO] Installing systemd service..."
cp "$SERVICE_SRC" "$SERVICE_DST"

systemctl daemon-reload
systemctl enable node_exporter
systemctl restart node_exporter

echo "[INFO] Checking service..."
systemctl status node_exporter --no-pager

echo "[INFO] Testing endpoint..."
curl -s http://localhost:9100/metrics >/dev/null

echo "[DONE] Node Exporter installed successfully"
