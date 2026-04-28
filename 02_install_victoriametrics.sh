#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
SRC_DIR="$BASE_DIR/sources/tar"
BIN_DIR="$BASE_DIR/victoriametrics/bin"
CONF_DIR="$BASE_DIR/victoriametrics/conf"
DATA_DIR="$BASE_DIR/data/victoriametrics"
LOG_DIR="$BASE_DIR/logs/victoriametrics"
SERVICE_SRC="./systemd/victoriametrics.service"
SERVICE_DST="/etc/systemd/system/victoriametrics.service"
ENV_SRC="./config/victoriametrics/victoriametrics.env.example"
ENV_DST="$CONF_DIR/victoriametrics.env"

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

mkdir -p "$BIN_DIR" "$CONF_DIR" "$DATA_DIR" "$LOG_DIR"

echo "[INFO] Extracting: $VM_TAR"
tar -xzf "$VM_TAR" -C "$BIN_DIR"

if [ ! -f "$BIN_DIR/victoria-metrics-prod" ]; then
  echo "[ERROR] victoria-metrics-prod binary not found after extract"
  exit 1
fi

chmod +x "$BIN_DIR/victoria-metrics-prod"

echo "[INFO] Checking VictoriaMetrics binary..."
"$BIN_DIR/victoria-metrics-prod" -version || true

echo "[INFO] Installing VictoriaMetrics tuning env..."

if [ -f "$ENV_DST" ]; then
  cp "$ENV_DST" "$ENV_DST.bak.$(date +%Y%m%d_%H%M%S)"
fi

if [ -f "$ENV_SRC" ]; then
  cp "$ENV_SRC" "$ENV_DST"
else
  cat > "$ENV_DST" <<'EOF'
VM_RETENTION_PERIOD=90d
VM_MEMORY_ALLOWED_PERCENT=60
VM_MIN_FREE_DISK_SPACE=10GB
VM_SEARCH_MAX_QUERY_DURATION=2m
VM_SEARCH_MAX_CONCURRENT_REQUESTS=16
VM_SEARCH_MAX_QUEUE_DURATION=30s
VM_LOGGER_LEVEL=INFO
EOF
fi

chmod 640 "$ENV_DST"
chown -R monitoring:monitoring "$BASE_DIR/victoriametrics" "$DATA_DIR" "$LOG_DIR"

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

echo "[INFO] Installing systemd service..."
cp "$SERVICE_SRC" "$SERVICE_DST"

echo "[INFO] Validating systemd unit..."
systemd-analyze verify "$SERVICE_DST" || true

systemctl daemon-reload
systemctl enable victoriametrics
systemctl restart victoriametrics

echo "[INFO] Checking service..."
systemctl status victoriametrics --no-pager

echo "[INFO] Testing endpoint..."
if curl -fsS http://localhost:8428/health >/dev/null; then
  echo "[INFO] VictoriaMetrics health endpoint OK"
else
  echo "[WARN] VictoriaMetrics health endpoint failed. Checking /metrics..."
  curl -fsS http://localhost:8428/metrics >/dev/null
fi

echo "[INFO] Checking active flags..."
curl -fsS http://localhost:8428/flags >/dev/null || true

echo "[INFO] Storage disk usage:"
df -h "$DATA_DIR"

echo "[DONE] VictoriaMetrics installed successfully"
echo "[INFO] Config env: $ENV_DST"
echo "[INFO] Data path : $DATA_DIR"
echo "[INFO] Logs      : $LOG_DIR"
