#!/bin/bash

set -euo pipefail

# GCP online lab deployment helper.
#
# Run from repository root on the monitoring VM:
#
#   sudo ORACLE_DB_HOST=10.128.0.3 ORACLE_DB_SERVICE=ORCL ORACLE_SSH_HOST=ora-primary-01 ./deploy_gcp_lab_online.sh
#
# Optional env:
#   ORACLE_DB_PORT=1521
#   ORACLE_DB_NAME=ORCL
#   ORACLE_MONITOR_USER=monitoring_user
#   ORACLE_MONITOR_PASSWORD=<password>
#   CREATE_ORACLE_USER=yes|no
#   GRAFANA_ADMIN_PASSWORD=admin
#   INSTALL_MSSQL_EXPORTER=yes|no
#   SELINUX_PERMISSIVE=yes|no
#
# This script is intentionally lab-oriented:
# - downloads packages from the internet
# - sets SELinux permissive by default on OL/RHEL lab VMs
# - installs a single Oracle exporter on the monitoring VM
# - labels the Oracle target by exporter instance/IP for dashboard compatibility

BASE_DIR="/monitoring"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAR_DIR="$BASE_DIR/sources/tar"
RPM_DIR="$BASE_DIR/sources/rpm"
PY_DIR="$BASE_DIR/sources/python"

ORACLE_DB_HOST="${ORACLE_DB_HOST:-10.128.0.3}"
ORACLE_DB_PORT="${ORACLE_DB_PORT:-1521}"
ORACLE_DB_SERVICE="${ORACLE_DB_SERVICE:-ORCL}"
ORACLE_DB_NAME="${ORACLE_DB_NAME:-$ORACLE_DB_SERVICE}"
ORACLE_SSH_HOST="${ORACLE_SSH_HOST:-}"
ORACLE_MONITOR_USER="${ORACLE_MONITOR_USER:-monitoring_user}"
ORACLE_MONITOR_PASSWORD="${ORACLE_MONITOR_PASSWORD:-}"
CREATE_ORACLE_USER="${CREATE_ORACLE_USER:-yes}"
INSTALL_MSSQL_EXPORTER="${INSTALL_MSSQL_EXPORTER:-yes}"
SELINUX_PERMISSIVE="${SELINUX_PERMISSIVE:-yes}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"

PROM_VERSION="3.11.3"
ALERTMANAGER_VERSION="0.32.1"
NODE_EXPORTER_VERSION="1.11.1"
VICTORIAMETRICS_VERSION="1.143.0"
GRAFANA_VERSION="13.0.1"
ORACLE_EXPORTER_VERSION="0.5.2"
MSSQL_EXPORTER_VERSION="0.6.0-beta.0"

log() {
  echo ""
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "[INFO] Re-running with sudo..."
    exec sudo -E bash "$0" "$@"
  fi
}

generate_password() {
  python3 - <<'PY'
import secrets
import string
alphabet = string.ascii_letters + string.digits
print("Mon" + "".join(secrets.choice(alphabet) for _ in range(24)) + "9")
PY
}

fetch() {
  local url=$1
  local dest=$2

  if [ -s "$dest" ]; then
    echo "[SKIP] $(basename "$dest")"
    return
  fi

  echo "[GET] $url"
  curl -fL --retry 3 --connect-timeout 20 --speed-time 60 --speed-limit 1024 -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
}

wait_http() {
  local name=$1
  local url=$2
  local max_tries=${3:-30}

  for _ in $(seq 1 "$max_tries"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      echo "[OK] $name: $url"
      return 0
    fi
    sleep 2
  done

  echo "[ERROR] $name did not become ready: $url"
  return 1
}

monitoring_ip() {
  hostname -I | awk '{print $1}'
}

prepare_vm() {
  log "Preparing VM"
  cd "$REPO_DIR"
  INSTALL_PACKAGES=online bash ./01_prepare_vm.sh

  if [ "$SELINUX_PERMISSIVE" = "yes" ] && command -v setenforce >/dev/null 2>&1; then
    log "Setting SELinux permissive for GCP lab"
    setenforce 0 || true
  fi
}

download_assets() {
  log "Downloading online packages"
  mkdir -p "$TAR_DIR" "$RPM_DIR" "$PY_DIR"
  chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$BASE_DIR/sources" || true

  fetch "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz" \
    "$TAR_DIR/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
  fetch "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz" \
    "$TAR_DIR/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
  fetch "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" \
    "$TAR_DIR/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
  fetch "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${VICTORIAMETRICS_VERSION}/victoria-metrics-linux-amd64-v${VICTORIAMETRICS_VERSION}.tar.gz" \
    "$TAR_DIR/victoria-metrics-linux-amd64-v${VICTORIAMETRICS_VERSION}.tar.gz"

  # oracledb_exporter 0.6.0 currently requires newer GLIBC than Oracle Linux 8.
  fetch "https://github.com/iamseth/oracledb_exporter/releases/download/${ORACLE_EXPORTER_VERSION}/oracledb_exporter.tar.gz" \
    "$TAR_DIR/oracledb_exporter-${ORACLE_EXPORTER_VERSION}.linux-amd64.tar.gz"

  if [ "$INSTALL_MSSQL_EXPORTER" = "yes" ]; then
    fetch "https://github.com/severalnines/mssql_exporter/releases/download/0.6.0b/mssql_exporter-${MSSQL_EXPORTER_VERSION}.linux-amd64.tar.gz" \
      "$TAR_DIR/mssql_exporter-${MSSQL_EXPORTER_VERSION}.linux-amd64.tar.gz"
  fi

  fetch "https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}-1.x86_64.rpm" \
    "$RPM_DIR/grafana-${GRAFANA_VERSION}-1.x86_64.rpm"

  find "$BASE_DIR/sources" -maxdepth 2 -type f -printf "%p %s bytes\n" | sort
}

configure_lab_targets() {
  log "Configuring GCP lab Prometheus targets"
  local ip
  ip="$(monitoring_ip)"

  mkdir -p "$REPO_DIR/config/targets"

  cat > "$REPO_DIR/config/targets/node_targets.yml" <<EOF
- targets:
    - "${ip}:9100"
  labels:
    service: "node"
    environment: "gcp-lab"
    site: "gcp"
    team: "dba"
    role: "monitoring-platform"
    db_type: "none"
    app: "monitoring-platform"
    tier: "lab"
    owner: "dba"
EOF

  cat > "$REPO_DIR/config/targets/oracle_targets.yml" <<EOF
- targets:
    - "${ip}:9161"
  labels:
    service: "oracle"
    environment: "gcp-lab"
    site: "gcp"
    team: "dba"
    role: "database"
    db_type: "oracle"
    app: "oracle-lab"
    tier: "lab"
    owner: "dba"
    db_host: "${ORACLE_SSH_HOST:-$ORACLE_DB_HOST}"
    db_name: "${ORACLE_DB_NAME}"
EOF

  cat > "$REPO_DIR/config/targets/mssql_targets.yml" <<'EOF'
[]
EOF
}

install_core_stack() {
  log "Installing VictoriaMetrics"
  cd "$REPO_DIR"
  bash ./02_install_victoriametrics.sh || true
  systemctl stop victoriametrics || true
  pkill -f victoria-metrics-prod || true
  systemctl reset-failed victoriametrics || true
  systemctl restart victoriametrics
  wait_http "VictoriaMetrics" "http://localhost:8428/health"

  log "Installing Alertmanager"
  bash ./06_install_alertmanager.sh
  wait_http "Alertmanager" "http://localhost:9093/-/ready"

  log "Installing Prometheus"
  bash ./03_install_prometheus.sh
  wait_http "Prometheus" "http://localhost:9090/-/ready"

  log "Installing Node Exporter"
  bash ./04_install_node_exporter.sh
  wait_http "Node Exporter" "http://localhost:9100/metrics"

  log "Installing Grafana"
  bash ./05_install_grafana.sh
  wait_http "Grafana" "http://localhost:3000/api/health"
}

install_exporters() {
  log "Installing Oracle Exporter"
  cd "$REPO_DIR"
  bash ./07_install_oracle_exporter.sh

  if [ "$INSTALL_MSSQL_EXPORTER" = "yes" ]; then
    log "Installing MSSQL Exporter template"
    bash ./08_install_mssql_exporter.sh
  fi
}

install_postgres_dpa() {
  log "Installing PostgreSQL DPA repository"
  cd "$REPO_DIR"
  bash ./10_install_postgres_dpa.sh

  log "Installing Python 3.9 DPA dependencies"
  dnf install -y python39 python39-pip python39-devel gcc postgresql-devel
  python3.9 -m pip install --upgrade pip setuptools wheel
  python3.9 -m pip install -r "$REPO_DIR/config/dpa/python-requirements.txt"

  log "Pointing DPA systemd units to python3.9"
  sed -i "s#/usr/bin/python3 #/usr/bin/python3.9 #" \
    /etc/systemd/system/dpa_sampler.service \
    /etc/systemd/system/dpa_sampler@.service \
    /etc/systemd/system/mssql_dpa_sampler@.service
  systemctl daemon-reload

  log "Allowing local password auth for DPA PostgreSQL users"
  cp /var/lib/pgsql/data/pg_hba.conf "/var/lib/pgsql/data/pg_hba.conf.bak.gcp-lab.$(date +%Y%m%d_%H%M%S)"
  sed -i -E \
    -e 's/^(host[[:space:]]+all[[:space:]]+all[[:space:]]+127\.0\.0\.1\/32[[:space:]]+).*/\1md5/' \
    -e 's/^(host[[:space:]]+all[[:space:]]+all[[:space:]]+::1\/128[[:space:]]+).*/\1md5/' \
    /var/lib/pgsql/data/pg_hba.conf
  systemctl reload postgresql
}

create_oracle_user() {
  if [ "$CREATE_ORACLE_USER" != "yes" ]; then
    log "Skipping Oracle user creation because CREATE_ORACLE_USER=$CREATE_ORACLE_USER"
    return
  fi

  if [ -z "$ORACLE_SSH_HOST" ]; then
    log "Skipping Oracle user creation because ORACLE_SSH_HOST is empty"
    return
  fi

  log "Creating or updating Oracle monitoring user on $ORACLE_SSH_HOST"

  ssh "$ORACLE_SSH_HOST" "cat > /tmp/create_monitoring_user.sql" <<SQL
set serveroutput on size unlimited
whenever sqlerror exit failure rollback
DECLARE
  v_count NUMBER;
  v_password VARCHAR2(128) := '${ORACLE_MONITOR_PASSWORD}';
  PROCEDURE try_exec(p_sql VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    DBMS_OUTPUT.PUT_LINE('OK: ' || p_sql);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('WARN: ' || p_sql || ' -> ' || SQLERRM);
  END;
BEGIN
  SELECT COUNT(*) INTO v_count FROM dba_users WHERE username = UPPER('${ORACLE_MONITOR_USER}');
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER ${ORACLE_MONITOR_USER} IDENTIFIED BY "${ORACLE_MONITOR_PASSWORD}"';
    DBMS_OUTPUT.PUT_LINE('OK: created ${ORACLE_MONITOR_USER}');
  ELSE
    EXECUTE IMMEDIATE 'ALTER USER ${ORACLE_MONITOR_USER} IDENTIFIED BY "${ORACLE_MONITOR_PASSWORD}" ACCOUNT UNLOCK';
    DBMS_OUTPUT.PUT_LINE('OK: reset/unlocked ${ORACLE_MONITOR_USER}');
  END IF;

  try_exec('GRANT CREATE SESSION TO ${ORACLE_MONITOR_USER}');
  try_exec('GRANT SELECT_CATALOG_ROLE TO ${ORACLE_MONITOR_USER}');

  FOR r IN (
    SELECT column_value AS obj FROM TABLE(sys.odcivarchar2list(
      'V_\$SESSION','V_\$RESOURCE_LIMIT','V_\$SYSMETRIC','V_\$SYSSTAT','V_\$SYSTEM_EVENT',
      'V_\$SQL','V_\$SQLAREA','V_\$SQL_PLAN','V_\$DATABASE','V_\$INSTANCE','V_\$CONTAINERS',
      'V_\$SEGMENT_STATISTICS','V_\$RMAN_BACKUP_JOB_DETAILS','V_\$DATAGUARD_STATS',
      'V_\$TEMP_SPACE_HEADER','V_\$FLASH_RECOVERY_AREA_USAGE','V_\$RECOVERY_FILE_DEST',
      'V_\$ASM_DISKGROUP','V_\$ASM_OPERATION','GV_\$INSTANCE','GV_\$SESSION','GV_\$ACTIVE_SERVICES',
      'DBA_OBJECTS','DBA_INDEXES','DBA_TAB_STATISTICS','DBA_SCHEDULER_JOB_RUN_DETAILS',
      'DBA_DATA_FILES','DBA_FREE_SPACE','DBA_TABLESPACES','DBA_TEMP_FILES'
    ))
  ) LOOP
    try_exec('GRANT SELECT ON SYS.' || r.obj || ' TO ${ORACLE_MONITOR_USER}');
  END LOOP;
END;
/
select username, account_status from dba_users where username=UPPER('${ORACLE_MONITOR_USER}');
exit
SQL

  ssh "$ORACLE_SSH_HOST" "sudo -iu oracle bash -lc 'sqlplus -s \"/ as sysdba\" @/tmp/create_monitoring_user.sql'"
}

configure_oracle_runtime() {
  log "Configuring Oracle exporter and DPA runtime"

  local dsn="${ORACLE_DB_HOST}:${ORACLE_DB_PORT}/${ORACLE_DB_SERVICE}"
  local exporter_dsn="oracle://${ORACLE_MONITOR_USER}:${ORACLE_MONITOR_PASSWORD}@${dsn}"
  local app_password
  app_password="$(awk -F= '/^DPA_APP_PASSWORD=/{print $2}' "$BASE_DIR/dpa/conf/dpa_repository.env")"

  sed -i "s#^DATA_SOURCE_NAME=.*#DATA_SOURCE_NAME=${exporter_dsn}#" "$BASE_DIR/exporters/oracle/oracle_exporter.env"
  chmod 600 "$BASE_DIR/exporters/oracle/oracle_exporter.env"
  chown monitoring:monitoring "$BASE_DIR/exporters/oracle/oracle_exporter.env"

  for file in "$BASE_DIR/dpa/conf/oracle-default.env" "$BASE_DIR/dpa/conf/dpa_sampler.env"; do
    sed -i "s#^DPA_ORACLE_USER=.*#DPA_ORACLE_USER=${ORACLE_MONITOR_USER}#" "$file"
    sed -i "s#^DPA_ORACLE_PASSWORD=.*#DPA_ORACLE_PASSWORD=${ORACLE_MONITOR_PASSWORD}#" "$file"
    sed -i "s#^DPA_ORACLE_DSN=.*#DPA_ORACLE_DSN=${dsn}#" "$file"
    sed -i "s#^DPA_DB_UNIQUE_NAME=.*#DPA_DB_UNIQUE_NAME=${ORACLE_DB_NAME}#" "$file"
    sed -i "s#^DPA_APP=.*#DPA_APP=oracle-lab#" "$file"
    sed -i "s#^DPA_TIER=.*#DPA_TIER=lab#" "$file"
    sed -i "s#^DPA_OWNER=.*#DPA_OWNER=dba#" "$file"
    sed -i "s#^DPA_POSTGRES_DSN=.*#DPA_POSTGRES_DSN=\"host=127.0.0.1 port=5432 dbname=dpa_repository user=dpa_app password=${app_password}\"#" "$file"
  done
  chmod 600 "$BASE_DIR/dpa/conf"/*.env
  chown -R monitoring:monitoring "$BASE_DIR/dpa"

  systemctl restart oracle_exporter
  wait_http "Oracle Exporter" "http://localhost:9161/metrics"

  if curl -fsS http://localhost:9161/metrics | grep -q '^oracledb_up 1\|^oracledb_oracle_up_value'; then
    echo "[OK] Oracle exporter reports UP"
  else
    echo "[WARN] Oracle exporter is reachable, but Oracle UP metric was not found"
  fi

  systemctl enable --now dpa_sampler@oracle-default.timer
  systemctl reset-failed dpa_sampler@oracle-default.service || true
  systemctl start dpa_sampler@oracle-default.service || true
}

reset_grafana_admin() {
  log "Resetting Grafana admin password"
  grafana cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini admin reset-admin-password "$GRAFANA_ADMIN_PASSWORD"
  systemctl restart grafana-server
  wait_http "Grafana" "http://localhost:3000/api/health"
}

final_validation() {
  log "Final health check"
  cd "$REPO_DIR"
  bash ./09_health_check.sh || true

  echo ""
  echo "[INFO] Prometheus Oracle target labels:"
  curl -fsS -G http://localhost:9090/api/v1/series --data-urlencode 'match[]=oracledb_oracle_up_value' || true
  echo ""

  echo "[INFO] DPA row counts:"
  runuser -u postgres -- psql -d dpa_repository \
    -c "select count(*) as ash_count from dpa.ash_sample;" \
    -c "select count(*) as sql_count from dpa.sql_snapshot;" \
    -c "select count(*) as ops_count from dpa.oracle_ops_snapshot;" || true

  local ip
  ip="$(monitoring_ip)"
  echo ""
  echo "Access URLs:"
  echo "Grafana      : http://${ip}:3000"
  echo "Prometheus   : http://${ip}:9090"
  echo "Alertmanager : http://${ip}:9093"
  echo "Victoria     : http://${ip}:8428"
  echo ""
  echo "Grafana login:"
  echo "admin / ${GRAFANA_ADMIN_PASSWORD}"
}

main() {
  require_root "$@"

  if [ -z "$ORACLE_MONITOR_PASSWORD" ]; then
    ORACLE_MONITOR_PASSWORD="$(generate_password)"
    export ORACLE_MONITOR_PASSWORD
    echo "[INFO] Generated ORACLE_MONITOR_PASSWORD for this lab run"
  fi

  prepare_vm
  download_assets
  configure_lab_targets
  install_core_stack
  install_exporters
  install_postgres_dpa
  create_oracle_user
  configure_oracle_runtime
  reset_grafana_admin
  final_validation
}

main "$@"
