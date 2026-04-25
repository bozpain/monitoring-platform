#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
SRC_DIR="$BASE_DIR/sources/tar"

BIN_DIR="$BASE_DIR/alertmanager/bin"
CONF_DIR="$BASE_DIR/alertmanager/conf"
DATA_DIR="$BASE_DIR/data/alertmanager"
LOG_DIR="$BASE_DIR/logs/alertmanager"

SERVICE_SRC="./systemd/alertmanager.service"
SERVICE_DST="/etc/systemd/system/alertmanager.service"

echo "[INFO] Installing Alertmanager..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

AM_TAR=$(ls "$SRC_DIR"/alertmanager-*.linux-amd64.tar.gz 2>/dev/null | head -n 1 || true)

if [ -z "$AM_TAR" ]; then
  echo "[ERROR] Alertmanager tar.gz not found in $SRC_DIR"
  echo "[INFO] Expected: alertmanager-*.linux-amd64.tar.gz"
  exit 1
fi

mkdir -p "$BIN_DIR" "$CONF_DIR" "$DATA_DIR" "$LOG_DIR"

echo "[INFO] Extracting: $AM_TAR"
TMP_DIR=$(mktemp -d)
tar -xzf "$AM_TAR" -C "$TMP_DIR"

cp "$TMP_DIR"/alertmanager-*.linux-amd64/alertmanager "$BIN_DIR/"
cp "$TMP_DIR"/alertmanager-*.linux-amd64/amtool "$BIN_DIR/"
rm -rf "$TMP_DIR"

cp ./config/alertmanager.yml "$CONF_DIR/alertmanager.yml"

chmod +x "$BIN_DIR/alertmanager" "$BIN_DIR/amtool"
chown -R monitoring:monitoring "$BASE_DIR/alertmanager" "$DATA_DIR" "$LOG_DIR"

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

echo "[INFO] Installing systemd service..."
cp "$SERVICE_SRC" "$SERVICE_DST"

systemctl daemon-reload
systemctl enable alertmanager
systemctl restart alertmanager

echo "[INFO] Checking service..."
systemctl status alertmanager --no-pager

echo "[INFO] Testing endpoint..."
curl -s http://localhost:9093/-/ready >/dev/null

echo "[DONE] Alertmanager installed successfully"
