#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
SRC_DIR="$BASE_DIR/sources/tar"

ORACLE_DIR="$BASE_DIR/exporters/oracle"
LOG_DIR="$BASE_DIR/logs/exporters"

SERVICE_SRC="./systemd/oracle_exporter.service"
SERVICE_DST="/etc/systemd/system/oracle_exporter.service"

METRICS_SRC="./config/oracle/oracle-metrics.toml"
METRICS_DST="$ORACLE_DIR/oracle-metrics.toml"

echo "[INFO] Installing Oracle Exporter..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

if ! id monitoring >/dev/null 2>&1; then
  echo "[ERROR] User 'monitoring' does not exist. Run 01_prepare_vm.sh first."
  exit 1
fi

OE_TAR=$(ls "$SRC_DIR"/oracledb_exporter*.tar.gz 2>/dev/null | head -n 1 || true)

if [ -z "$OE_TAR" ]; then
  echo "[ERROR] Oracle exporter tar.gz not found in $SRC_DIR"
  echo "[INFO] Expected: oracledb_exporter*.tar.gz"
  exit 1
fi

if [ ! -f "$METRICS_SRC" ]; then
  echo "[ERROR] DPA metrics file not found: $METRICS_SRC"
  exit 1
fi

mkdir -p "$ORACLE_DIR" "$LOG_DIR"

echo "[INFO] Extracting: $OE_TAR"
TMP_DIR=$(mktemp -d)
tar -xzf "$OE_TAR" -C "$TMP_DIR"

OE_BIN=$(find "$TMP_DIR" -type f -name "oracledb_exporter" | head -n 1 || true)

if [ -z "$OE_BIN" ]; then
  echo "[ERROR] oracledb_exporter binary not found after extract"
  rm -rf "$TMP_DIR"
  exit 1
fi

cp "$OE_BIN" "$ORACLE_DIR/oracledb_exporter"
rm -rf "$TMP_DIR"

echo "[INFO] Installing DPA metrics..."
cp "$METRICS_SRC" "$METRICS_DST"

if [ ! -f "$ORACLE_DIR/oracle_exporter.env" ]; then
  cat > "$ORACLE_DIR/oracle_exporter.env" <<EOF
# Oracle exporter connection string
# Format:
# DATA_SOURCE_NAME=username/password@//host:port/service_name
DATA_SOURCE_NAME=monitoring_user/CHANGE_ME@//db-host:1521/service_name
EOF
  echo "[WARN] Created template env: $ORACLE_DIR/oracle_exporter.env"
  echo "[WARN] Edit DATA_SOURCE_NAME before starting exporter"
fi

chmod +x "$ORACLE_DIR/oracledb_exporter"
chmod 600 "$ORACLE_DIR/oracle_exporter.env"

chown -R monitoring:monitoring "$ORACLE_DIR" "$LOG_DIR"

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

echo "[INFO] Installing systemd service..."
cp "$SERVICE_SRC" "$SERVICE_DST"

systemctl daemon-reload
systemctl enable oracle_exporter

echo "[DONE] Oracle Exporter installed"
echo "[NEXT] Edit connection file:"
echo "       vi $ORACLE_DIR/oracle_exporter.env"
echo ""
echo "Then start:"
echo "       systemctl restart oracle_exporter"
echo "       systemctl status oracle_exporter --no-pager"
echo ""
echo "Metrics file:"
echo "       $METRICS_DST"
