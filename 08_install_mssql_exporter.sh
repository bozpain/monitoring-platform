#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
SRC_DIR="$BASE_DIR/sources/tar"

MSSQL_DIR="$BASE_DIR/exporters/mssql"
LOG_DIR="$BASE_DIR/logs/exporters"

SERVICE_SRC="./systemd/mssql_exporter.service"
SERVICE_DST="/etc/systemd/system/mssql_exporter.service"

METRICS_SRC="./config/mssql/mssql-metrics.toml"
METRICS_DST="$MSSQL_DIR/mssql-metrics.toml"

echo "[INFO] Installing MSSQL Exporter..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

if ! id monitoring >/dev/null 2>&1; then
  echo "[ERROR] User 'monitoring' does not exist. Run 01_prepare_vm.sh first."
  exit 1
fi

MSSQL_TAR=$(ls "$SRC_DIR"/mssql_exporter*.tar.gz 2>/dev/null | head -n 1 || true)

if [ -z "$MSSQL_TAR" ]; then
  echo "[ERROR] MSSQL exporter tar.gz not found in $SRC_DIR"
  echo "[INFO] Expected: mssql_exporter*.tar.gz"
  exit 1
fi

if [ ! -f "$METRICS_SRC" ]; then
  echo "[ERROR] MSSQL metrics file not found: $METRICS_SRC"
  exit 1
fi

mkdir -p "$MSSQL_DIR" "$LOG_DIR"

echo "[INFO] Extracting: $MSSQL_TAR"
TMP_DIR=$(mktemp -d)
tar -xzf "$MSSQL_TAR" -C "$TMP_DIR"

MSSQL_BIN=$(find "$TMP_DIR" -type f -name "mssql_exporter" | head -n 1 || true)

if [ -z "$MSSQL_BIN" ]; then
  echo "[ERROR] mssql_exporter binary not found after extract"
  rm -rf "$TMP_DIR"
  exit 1
fi

cp "$MSSQL_BIN" "$MSSQL_DIR/mssql_exporter"
rm -rf "$TMP_DIR"

echo "[INFO] Installing MSSQL metrics..."
cp "$METRICS_SRC" "$METRICS_DST"

if [ ! -f "$MSSQL_DIR/mssql_exporter.env" ]; then
  cat > "$MSSQL_DIR/mssql_exporter.env" <<EOF
# MSSQL exporter connection string
# Format:
# DATA_SOURCE_NAME=sqlserver://username:password@host:1433?database=master&encrypt=disable
DATA_SOURCE_NAME=sqlserver://monitoring_user:CHANGE_ME@mssql-host:1433?database=master&encrypt=disable
EOF
  echo "[WARN] Created template env: $MSSQL_DIR/mssql_exporter.env"
  echo "[WARN] Edit DATA_SOURCE_NAME before starting exporter"
fi

chmod +x "$MSSQL_DIR/mssql_exporter"
chmod 600 "$MSSQL_DIR/mssql_exporter.env"

chown -R monitoring:monitoring "$MSSQL_DIR" "$LOG_DIR"

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

echo "[INFO] Installing systemd service..."
cp "$SERVICE_SRC" "$SERVICE_DST"

systemctl daemon-reload
systemctl enable mssql_exporter

echo "[DONE] MSSQL Exporter installed"
echo "[NEXT] Edit connection file:"
echo "       vi $MSSQL_DIR/mssql_exporter.env"
echo ""
echo "Then start:"
echo "       systemctl restart mssql_exporter"
echo "       systemctl status mssql_exporter --no-pager"
echo ""
echo "Metrics file:"
echo "       $METRICS_DST"
