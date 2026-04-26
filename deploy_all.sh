#!/bin/bash

set -euo pipefail

echo "======================================="
echo " Monitoring Platform Full Deployment"
echo "======================================="

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

run_step() {
  local step=$1

  echo ""
  echo "---------------------------------------"
  echo "[RUN] $step"
  echo "---------------------------------------"

  if [ ! -f "$step" ]; then
    echo "[ERROR] Step not found: $step"
    exit 1
  fi

  chmod +x "$step"
  "$step"
}

run_step "./01_prepare_vm.sh"
run_step "./02_install_victoriametrics.sh"
run_step "./06_install_alertmanager.sh"
run_step "./03_install_prometheus.sh"
run_step "./04_install_node_exporter.sh"
run_step "./07_install_oracle_exporter.sh"
run_step "./08_install_mssql_exporter.sh"
run_step "./05_install_grafana.sh"

echo ""
echo "======================================="
echo "[DONE] All components installed"
echo "======================================="

echo ""
echo "Next steps:"
echo "- Configure SMTP in: /monitoring/alertmanager/conf/alertmanager.yml"
echo "- Configure targets in: /monitoring/config/targets/"
echo "- Check Prometheus targets: http://VM_IP:9090/targets"
echo "- Check Prometheus alerts: http://VM_IP:9090/alerts"
echo "- Check Alertmanager: http://VM_IP:9093"
echo "- Open Grafana: http://VM_IP:3000"
