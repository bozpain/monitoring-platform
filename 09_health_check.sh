#!/bin/bash

set -euo pipefail

echo "======================================="
echo "[STEP] Platform Health Check"
echo "======================================="

check_service() {
  local service=$1

  echo ""
  echo "[CHECK] $service"

  if systemctl is-active --quiet $service; then
    echo "[OK] $service is running"
  else
    echo "[FAIL] $service is NOT running"
    systemctl status $service --no-pager
    exit 1
  fi
}

echo "[INFO] Checking core services..."

check_service victoriametrics
check_service prometheus
check_service alertmanager
check_service grafana-server
check_service node_exporter

echo ""
echo "[INFO] Checking ports..."

check_port() {
  local port=$1
  local name=$2

  if netstat -tulnp | grep -q ":$port"; then
    echo "[OK] $name listening on port $port"
  else
    echo "[FAIL] $name NOT listening on port $port"
    exit 1
  fi
}

check_port 8428 "VictoriaMetrics"
check_port 9090 "Prometheus"
check_port 9093 "Alertmanager"
check_port 3000 "Grafana"
check_port 9100 "Node Exporter"

echo ""
echo "[INFO] Checking Prometheus targets..."

if curl -s http://localhost:9090/-/healthy >/dev/null; then
  echo "[OK] Prometheus API reachable"
else
  echo "[FAIL] Prometheus not reachable"
  exit 1
fi

echo ""
echo "======================================="
echo "[SUCCESS] All checks passed"
echo "======================================="

echo ""
echo "Access URLs:"
echo "Prometheus   : http://$(hostname -I | awk '{print $1}'):9090"
echo "Grafana      : http://$(hostname -I | awk '{print $1}'):3000"
echo "Alertmanager : http://$(hostname -I | awk '{print $1}'):9093"
