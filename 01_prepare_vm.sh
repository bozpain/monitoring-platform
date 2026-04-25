#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
MON_USER="monitoring"

echo "[INFO] Preparing monitoring VM..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

echo "[INFO] Creating monitoring user if not exists..."
if ! id "$MON_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$MON_USER"
  echo "[INFO] User '$MON_USER' created"
else
  echo "[INFO] User '$MON_USER' already exists"
fi

echo "[INFO] Creating directory structure..."

mkdir -p "$BASE_DIR"/{prometheus/{bin,conf},victoriametrics/{bin,conf},grafana/conf,alertmanager/{bin,conf},exporters/{oracle,mssql,postgres,mongodb,node},data/{prometheus,victoriametrics,alertmanager},logs/{prometheus,victoriametrics,grafana,alertmanager,exporters},sources/{rpm,tar,checksum}}

echo "[INFO] Setting permissions..."

chown -R "$MON_USER:$MON_USER" "$BASE_DIR"

chmod 755 "$BASE_DIR"
chmod 755 "$BASE_DIR/prometheus"
chmod 755 "$BASE_DIR/victoriametrics"
chmod 755 "$BASE_DIR/grafana"
chmod 755 "$BASE_DIR/alertmanager"
chmod 755 "$BASE_DIR/exporters"
chmod 750 "$BASE_DIR/data"
chmod 750 "$BASE_DIR/logs"
chmod 755 "$BASE_DIR/sources"

echo "[INFO] Installing base packages..."

if command -v dnf >/dev/null 2>&1; then
  dnf install -y tar gzip unzip curl wget vim net-tools lsof chrony
elif command -v yum >/dev/null 2>&1; then
  yum install -y tar gzip unzip curl wget vim net-tools lsof chrony
else
  echo "[WARN] dnf/yum not found, skipping package install"
fi

echo "[INFO] Enabling chronyd..."

systemctl enable --now chronyd || true

echo "[INFO] Final directory check:"
find "$BASE_DIR" -maxdepth 3 -type d | sort

echo "[DONE] VM preparation completed"
