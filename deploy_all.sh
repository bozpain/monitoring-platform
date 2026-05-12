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

validate_generated_targets() {
  echo ""
  echo "======================================="
  echo "[STEP] Validate Pre-Generated Targets"
  echo "======================================="

  local target_dir="./config/targets"

  if [ ! -d "$target_dir" ]; then
    echo "[ERROR] Target directory not found: $target_dir"
    echo "[INFO] Generate targets from VS Code first:"
    echo "       python scripts/generate_targets.py"
    exit 1
  fi

  for file in node_targets.yml oracle_targets.yml mssql_targets.yml; do
    if [ ! -f "$target_dir/$file" ]; then
      echo "[ERROR] Missing target file: $target_dir/$file"
      echo "[INFO] Generate targets from VS Code first:"
      echo "       python scripts/generate_targets.py"
      exit 1
    fi
  done

  echo "[INFO] Target files found:"
  ls -lah "$target_dir"

  if [ ! -s "$target_dir/node_targets.yml" ]; then
    echo "[WARN] node_targets.yml is empty"
  fi

  if [ ! -s "$target_dir/oracle_targets.yml" ]; then
    echo "[WARN] oracle_targets.yml is empty"
  fi

  if [ ! -s "$target_dir/mssql_targets.yml" ]; then
    echo "[WARN] mssql_targets.yml is empty"
  fi

  echo "[INFO] Using pre-generated targets from repo"
}

validate_generated_targets

run_step "./01_prepare_vm.sh"
run_step "./02_install_victoriametrics.sh"
run_step "./06_install_alertmanager.sh"
run_step "./03_install_prometheus.sh"
run_step "./04_install_node_exporter.sh"
run_step "./07_install_oracle_exporter.sh"
run_step "./08_install_mssql_exporter.sh"
run_step "./05_install_grafana.sh"
run_step "./10_install_postgres_dpa.sh"
run_step "./09_health_check.sh"

echo ""
echo "======================================="
echo "[DONE] All components installed"
echo "======================================="

echo ""
echo "Next steps:"
echo "- For future inventory changes, edit: inventory/targets.csv"
echo "- Then regenerate targets: python scripts/generate_targets.py"
echo "- Commit regenerated targets: config/targets/*.yml"
echo "- Edit DB exporter credentials on the server:"
echo "  /monitoring/exporters/oracle/oracle_exporter.env"
echo "  /monitoring/exporters/mssql/mssql_exporter.env"
echo "- Start DB exporters after credentials are correct:"
echo "  systemctl restart oracle_exporter mssql_exporter"
echo "- Configure SMTP in: /monitoring/alertmanager/conf/alertmanager.yml"
echo "- Edit Oracle DPA repository sampler credentials:"
echo "  /monitoring/dpa/conf/dpa_sampler.env"
echo "- Start DPA sampler after credentials and Python wheels are correct:"
echo "  systemctl restart dpa_sampler.timer"
echo "- Check Prometheus targets: http://VM_IP:9090/targets"
echo "- Check Prometheus alerts: http://VM_IP:9090/alerts"
echo "- Check Alertmanager: http://VM_IP:9093"
echo "- Open Grafana: http://VM_IP:3000"

echo ""
echo "======================================="
echo "[INFO] Final Validation URLs"
echo "======================================="

IP=$(hostname -I | awk '{print $1}')

echo "Prometheus   : http://$IP:9090"
echo "Grafana      : http://$IP:3000"
echo "Alertmanager : http://$IP:9093"
echo "Targets      : http://$IP:9090/targets"
