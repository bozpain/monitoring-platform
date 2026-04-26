#!/bin/bash
set -euo pipefail

BASE_DIR="/monitoring"
EXPORTER_NAME="mssql_exporter"
EXPORTER_DIR="${BASE_DIR}/exporters/mssql"
CONFIG_DIR="${BASE_DIR}/config/mssql"
LOG_DIR="${BASE_DIR}/logs/exporters/mssql"
SOURCE_DIR="${BASE_DIR}/sources/tar"

EXPORTER_BINARY="${EXPORTER_DIR}/mssql_exporter"
METRICS_CONFIG="${CONFIG_DIR}/mssql-metrics.toml"
SERVICE_FILE="/etc/systemd/system/mssql_exporter.service"
LISTEN_ADDRESS="0.0.0.0:9182"

echo "==> Installing MSSQL Exporter"

mkdir -p "${EXPORTER_DIR}"
mkdir -p "${CONFIG_DIR}"
mkdir -p "${LOG_DIR}"

if [ ! -f "${EXPORTER_BINARY}" ]; then
  echo "ERROR: ${EXPORTER_BINARY} not found"
  echo "Please place mssql_exporter binary in ${EXPORTER_DIR}/"
  exit 1
fi

if [ ! -f "${METRICS_CONFIG}" ]; then
  echo "ERROR: ${METRICS_CONFIG} not found"
  exit 1
fi

chmod +x "${EXPORTER_BINARY}"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=MSSQL Exporter
After=network.target

[Service]
Type=simple
User=root
Group=root
Environment="MSSQL_EXPORTER_CONFIG_FILE=${METRICS_CONFIG}"
Environment="DATA_SOURCE_NAME=sqlserver://MONITOR_USER:MONITOR_PASSWORD@MSSQL_HOST:1433?database=master&encrypt=disable"
ExecStart=${EXPORTER_BINARY} \\
  --web.listen-address=${LISTEN_ADDRESS} \\
  --config.file=${METRICS_CONFIG}
Restart=always
RestartSec=5
StandardOutput=append:${LOG_DIR}/mssql_exporter.log
StandardError=append:${LOG_DIR}/mssql_exporter.err

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mssql_exporter
systemctl restart mssql_exporter

echo "==> MSSQL Exporter installed"
echo "==> Check:"
echo "curl http://localhost:9182/metrics"
