#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
SRC_DIR="$BASE_DIR/sources/tar"

PROM_DIR="$BASE_DIR/prometheus"
BIN_DIR="$PROM_DIR/bin"
CONF_DIR="$PROM_DIR/conf"
ALERT_DIR="$CONF_DIR/alerts"
TARGETS_DIR="$BASE_DIR/config/targets"
DATA_DIR="$BASE_DIR/data/prometheus"
LOG_DIR="$BASE_DIR/logs/prometheus"

CONFIG_SRC="./config/prometheus.yml"
ENV_SRC="./config/prometheus/prometheus.env.example"
ENV_DST="$CONF_DIR/prometheus.env"
TARGETS_SRC="./config/targets"

SERVICE_SRC="./systemd/prometheus.service"
SERVICE_DST="/etc/systemd/system/prometheus.service"

echo "[INFO] Installing Prometheus..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

if ! id monitoring >/dev/null 2>&1; then
  echo "[ERROR] User 'monitoring' does not exist. Run 01_prepare_vm.sh first."
  exit 1
fi

PROM_TAR=$(ls "$SRC_DIR"/prometheus-*.linux-amd64.tar.gz 2>/dev/null | head -n 1 || true)

if [ -z "$PROM_TAR" ]; then
  echo "[ERROR] Prometheus tar.gz not found in $SRC_DIR"
  echo "[INFO] Expected: prometheus-*.linux-amd64.tar.gz"
  exit 1
fi

if [ ! -f "$CONFIG_SRC" ]; then
  echo "[ERROR] Prometheus config not found: $CONFIG_SRC"
  exit 1
fi

echo "[INFO] Preparing directories..."

mkdir -p "$BIN_DIR"
mkdir -p "$CONF_DIR"
mkdir -p "$ALERT_DIR"
mkdir -p "$TARGETS_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$LOG_DIR"

echo "[INFO] Extracting: $PROM_TAR"

TMP_DIR=$(mktemp -d)
tar -xzf "$PROM_TAR" -C "$TMP_DIR"

PROM_EXTRACT_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name "prometheus-*.linux-amd64" | head -n 1 || true)

if [ -z "$PROM_EXTRACT_DIR" ]; then
  echo "[ERROR] Prometheus extracted directory not found"
  rm -rf "$TMP_DIR"
  exit 1
fi

cp "$PROM_EXTRACT_DIR/prometheus" "$BIN_DIR/"
cp "$PROM_EXTRACT_DIR/promtool" "$BIN_DIR/"

rm -rf "$TMP_DIR"

chmod +x "$BIN_DIR/prometheus" "$BIN_DIR/promtool"

echo "[INFO] Checking Prometheus binary..."
"$BIN_DIR/prometheus" --version || true
"$BIN_DIR/promtool" --version || true

echo "[INFO] Installing Prometheus config..."

if [ -f "$CONF_DIR/prometheus.yml" ]; then
  cp "$CONF_DIR/prometheus.yml" "$CONF_DIR/prometheus.yml.bak.$(date +%Y%m%d_%H%M%S)"
fi

cp "$CONFIG_SRC" "$CONF_DIR/prometheus.yml"

echo "[INFO] Installing Prometheus tuning env..."

if [ -f "$ENV_DST" ]; then
  cp "$ENV_DST" "$ENV_DST.bak.$(date +%Y%m%d_%H%M%S)"
fi

if [ -f "$ENV_SRC" ]; then
  cp "$ENV_SRC" "$ENV_DST"
else
  cat > "$ENV_DST" <<'EOF'
PROM_WEB_LISTEN_ADDRESS=:9090
PROM_RETENTION_TIME=1d
PROM_RETENTION_SIZE=10GB
PROM_QUERY_TIMEOUT=2m
PROM_QUERY_MAX_CONCURRENCY=20
PROM_QUERY_MAX_SAMPLES=50000000
PROM_REMOTE_FLUSH_DEADLINE=1m
EOF
fi

chmod 640 "$ENV_DST"

echo "[INFO] Installing Prometheus file_sd targets..."

if [ -d "$TARGETS_SRC" ]; then
  rm -f "$TARGETS_DIR"/*.yml
  cp "$TARGETS_SRC"/*.yml "$TARGETS_DIR"/
else
  echo "[ERROR] Prometheus targets directory not found: $TARGETS_SRC"
  exit 1
fi

for file in node_targets.yml oracle_targets.yml mssql_targets.yml; do
  if [ ! -f "$TARGETS_DIR/$file" ]; then
    echo "[ERROR] Missing generated target file: $TARGETS_DIR/$file"
    echo "[INFO] Run: python3 scripts/generate_targets.py"
    exit 1
  fi

  if [ ! -s "$TARGETS_DIR/$file" ]; then
    echo "[WARN] Generated target file is empty: $TARGETS_DIR/$file"
  fi
done

echo "[INFO] Installing alert rules..."

if [ -d ./config/alerts ]; then
  rm -f "$ALERT_DIR"/*.yml
  if ls ./config/alerts/*.yml >/dev/null 2>&1; then
    cp ./config/alerts/*.yml "$ALERT_DIR/"
  else
    echo "[WARN] No alert rule files found in ./config/alerts"
  fi
else
  echo "[WARN] ./config/alerts not found, skipping alert rules"
fi

echo "[INFO] Setting ownership..."

chown -R monitoring:monitoring "$PROM_DIR"
chown -R monitoring:monitoring "$BASE_DIR/config"
chown -R monitoring:monitoring "$DATA_DIR"
chown -R monitoring:monitoring "$LOG_DIR"

echo "[INFO] Validating Prometheus config..."

"$BIN_DIR/promtool" check config "$CONF_DIR/prometheus.yml"

if ls "$ALERT_DIR"/*.yml >/dev/null 2>&1; then
  "$BIN_DIR/promtool" check rules "$ALERT_DIR"/*.yml
fi

if [ ! -f "$SERVICE_SRC" ]; then
  echo "[ERROR] Service file not found: $SERVICE_SRC"
  exit 1
fi

echo "[INFO] Installing systemd service..."

cp "$SERVICE_SRC" "$SERVICE_DST"

echo "[INFO] Validating systemd unit..."
systemd-analyze verify "$SERVICE_DST" || true

systemctl daemon-reload
systemctl enable prometheus
systemctl restart prometheus

echo "[INFO] Checking service..."
systemctl status prometheus --no-pager

echo "[INFO] Testing endpoint..."

if curl -fsS http://localhost:9090/-/ready >/dev/null; then
  echo "[INFO] Prometheus endpoint OK"
else
  echo "[WARN] Prometheus endpoint test failed. Check: journalctl -u prometheus -f"
fi

echo "[INFO] Checking Prometheus runtime flags..."
curl -fsS http://localhost:9090/api/v1/status/runtimeinfo >/dev/null || true

echo "[INFO] Checking Prometheus targets API..."
curl -fsS http://localhost:9090/api/v1/targets >/dev/null || true

echo "[INFO] Local TSDB disk usage:"
df -h "$DATA_DIR"

echo "[DONE] Prometheus installed successfully"
echo "[INFO] Prometheus config: $CONF_DIR/prometheus.yml"
echo "[INFO] Prometheus env: $ENV_DST"
echo "[INFO] Prometheus targets: $TARGETS_DIR"
echo "[INFO] Prometheus alerts: $ALERT_DIR"
