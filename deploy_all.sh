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
  chmod +x "$step"
  "$step"
}

run_step "./01_prepare_vm.sh"
run_step "./02_install_victoriametrics.sh"
run_step "./03_install_prometheus.sh"
run_step "./04_install_node_exporter.sh"
run_step "./05_install_grafana.sh"
run_step "./06_install_alertmanager.sh"
run_step "./07_install_oracle_exporter.sh"

echo ""
echo "======================================="
echo "[DONE] All components installed"
echo "======================================="

echo ""
echo "Next steps:"
echo "- Configure Oracle connection"
echo "- Open Grafana: http://VM_IP:3000"
echo "- Check Prometheus: http://VM_IP:9090/targets"
