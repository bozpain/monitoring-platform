#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
SRC_DIR="$BASE_DIR/sources/tar"

AM_DIR="$BASE_DIR/alertmanager"
BIN_DIR="$AM_DIR/bin"
CONF_DIR="$AM_DIR/conf"
DATA_DIR="$BASE_DIR/data/alertmanager"
LOG_DIR="$BASE_DIR/logs/alertmanager"

CONFIG_SRC="./alertmanager/alertmanager.yml"
ENV_SRC="./config/alertmanager/alertmanager.env.example"
ENV_DST="$CONF_DIR/alertmanager.env"

SERVICE_SRC="./systemd/alertmanager.service"
SERVICE_DST="/etc/systemd/system/alertmanager.service"

echo "[INFO] Installing Alertmanager..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

if ! id monitoring >/dev/null 2>&1; then
  echo "[ERROR] User 'monitoring' does not exist. Run 01_prepare_vm.sh first."
  exit 1
fi

AM_TAR=$(ls "$SRC_DIR"/alertmanager-*.linux-amd64.tar.gz 2>/dev/null | head -n 1 || true)

if [ -z "$AM_TAR" ]; then
  echo "[ERROR] Alertmanager tar.gz not found in $SRC_DIR"
  echo "[INFO] Expected: alertmanager-*.linux-amd64.tar.gz"
  exit 1
fi

if [ ! -f "$CONFIG_SRC" ]; then
  echo "[ERROR] Alertmanager config not found: $CONFIG_SRC"
  exit 1
fi

mkdir -p "$BIN_DIR" "$CONF_DIR" "$DATA_DIR" "$LOG_DIR"

echo "[INFO] Extracting: $AM_TAR"

TMP_DIR=$(mktemp -d)
tar -xzf "$AM_TAR" -C "$TMP_DIR"

AM_EXTRACT_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name "alertmanager-*.linux-amd64" | head -n 1 || true)

if [ -z "$AM_EXTRACT_DIR" ]; then
  echo "[ERROR] Alertmanager extracted directory not found"
  rm -rf "$TMP_DIR"
  exit 1
fi

cp "$AM_EXTRACT_DIR/alertmanager" "$BIN_DIR/"
cp "$AM_EXTRACT_DIR/amtool" "$BIN_DIR/"

rm -rf "$TMP_DIR"

chmod +x "$BIN_DIR/alertmanager" "$BIN_DIR/amtool"

echo "[INFO] Checking Alertmanager binary..."
"$BIN_DIR/alertmanager" --version || true
"$BIN_DIR/amtool" --version || true

echo "[INFO] Installing Alertmanager config..."

if [ -f "$CONF_DIR/alertmanager.yml" ]; then
  cp "$CONF_DIR/alertmanager.yml" "$CONF_DIR/alertmanager.yml.bak.$(date +%Y%m%d_%H%M%S)"
fi

cp "$CONFIG_SRC" "$CONF_DIR/alertmanager.yml"

echo "[INFO] Installing Alertmanager tuning env..."

if [ -f "$ENV_DST" ]; then
  cp "$ENV_DST" "$ENV_DST.bak.$(date +%Y%m%d_%H%M%S)"
fi

if [ -f "$ENV_SRC" ]; then
  cp "$ENV_SRC" "$ENV_DST"
else
  cat > "$ENV_DST" <<'EOF'
AM_WEB_LISTEN_ADDRESS=:9093
AM_WEB_EXTERNAL_URL=http://localhost:9093
AM_WEB_ROUTE_PREFIX=/
AM_DATA_RETENTION=120h
AM_ALERTS_GC_INTERVAL=30m
AM_CLUSTER_LISTEN_ADDRESS=
AM_LOG_LEVEL=info
EOF
fi

chmod 640 "$ENV_DST"

if grep -q "CHANGE_ME" "$CONF_DIR/alertmanager.yml"; then
  echo "[WARN] Alertmanager config still contains CHANGE_ME placeholders"
  echo "[WARN] Edit SMTP settings before relying on email notifications"
fi

echo "[INFO] Setting ownership..."

chown -R monitoring:monitoring "$AM_DIR"
chown -R monitoring:monitoring "$DATA_DIR"
chown -R monitoring:monitoring "$LOG_DIR"

echo "[INFO] Validating Alertmanager config..."

"$BIN_DIR/amtool" check-config "$CONF_DIR/alertmanager.yml"

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

echo "[INFO] Installing systemd service..."

cp "$SERVICE_SRC" "$SERVICE_DST"

echo "[INFO] Validating systemd unit..."
systemd-analyze verify "$SERVICE_DST" || true

systemctl daemon-reload
systemctl enable alertmanager
systemctl restart alertmanager

echo "[INFO] Checking service..."
systemctl status alertmanager --no-pager

echo "[INFO] Testing endpoint..."

if curl -fsS http://localhost:9093/-/ready >/dev/null; then
  echo "[INFO] Alertmanager endpoint OK"
else
  echo "[WARN] Alertmanager endpoint test failed. Check: journalctl -u alertmanager -f"
fi

echo "[INFO] Checking Alertmanager API..."
curl -fsS http://localhost:9093/api/v2/status >/dev/null || true
curl -fsS http://localhost:9093/api/v2/receivers >/dev/null || true

echo "[INFO] Checking Alertmanager status with amtool..."
"$BIN_DIR/amtool" --alertmanager.url=http://localhost:9093 status || true

echo "[INFO] Alertmanager data disk usage:"
df -h "$DATA_DIR"

echo "[DONE] Alertmanager installed successfully"
echo "[INFO] Alertmanager URL: http://localhost:9093"
echo "[INFO] Alertmanager config: $CONF_DIR/alertmanager.yml"
echo "[INFO] Alertmanager env: $ENV_DST"
