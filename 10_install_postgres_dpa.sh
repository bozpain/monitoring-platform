#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
RPM_DIR="$BASE_DIR/sources/rpm"
PYTHON_WHEEL_DIR="$BASE_DIR/sources/python"

DPA_DIR="$BASE_DIR/dpa"
DPA_BIN_DIR="$DPA_DIR/bin"
DPA_CONF_DIR="$DPA_DIR/conf"
DPA_SQL_DIR="$DPA_DIR/sql"
DPA_LOG_DIR="$BASE_DIR/logs/dpa"

SCHEMA_SRC="./config/dpa/dpa_repository.sql"
ENV_SRC="./config/dpa/dpa_sampler.env.example"
REQ_SRC="./config/dpa/python-requirements.txt"
SAMPLER_SRC="./scripts/dpa_sampler.py"
SERVICE_SRC="./systemd/dpa_sampler.service"
TIMER_SRC="./systemd/dpa_sampler.timer"

SERVICE_DST="/etc/systemd/system/dpa_sampler.service"
TIMER_DST="/etc/systemd/system/dpa_sampler.timer"

DB_NAME="dpa_repository"
APP_USER="dpa_app"
READER_USER="dpa_reader"

echo "[INFO] Installing PostgreSQL DPA repository..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

if ! id monitoring >/dev/null 2>&1; then
  echo "[ERROR] User 'monitoring' does not exist. Run 01_prepare_vm.sh first."
  exit 1
fi

require_file() {
  local path=$1
  if [ ! -f "$path" ]; then
    echo "[ERROR] Required file not found: $path"
    exit 1
  fi
}

require_file "$SCHEMA_SRC"
require_file "$ENV_SRC"
require_file "$REQ_SRC"
require_file "$SAMPLER_SRC"
require_file "$SERVICE_SRC"
require_file "$TIMER_SRC"

mkdir -p "$DPA_BIN_DIR" "$DPA_CONF_DIR" "$DPA_SQL_DIR" "$DPA_LOG_DIR" "$PYTHON_WHEEL_DIR"

generate_password() {
  python3 - <<'PY'
import secrets
alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
print("".join(secrets.choice(alphabet) for _ in range(32)))
PY
}

install_postgres_packages() {
  if command -v psql >/dev/null 2>&1 && systemctl list-unit-files postgresql.service >/dev/null 2>&1; then
    echo "[INFO] PostgreSQL packages already available"
    return
  fi

  echo "[INFO] Installing PostgreSQL packages..."

  if command -v dnf >/dev/null 2>&1; then
    if dnf repolist enabled >/dev/null 2>&1; then
      dnf install -y postgresql-server postgresql-contrib python3-pip python3-psycopg2 || true
    fi
    if ! command -v psql >/dev/null 2>&1 && ls "$RPM_DIR"/postgresql*.rpm >/dev/null 2>&1; then
      dnf install -y "$RPM_DIR"/postgresql*.rpm
    fi
  elif command -v yum >/dev/null 2>&1; then
    if yum repolist enabled >/dev/null 2>&1; then
      yum install -y postgresql-server postgresql-contrib python3-pip python3-psycopg2 || true
    fi
    if ! command -v psql >/dev/null 2>&1 && ls "$RPM_DIR"/postgresql*.rpm >/dev/null 2>&1; then
      yum localinstall -y "$RPM_DIR"/postgresql*.rpm
    fi
  else
    echo "[ERROR] dnf/yum not found"
    exit 1
  fi

  if ! command -v psql >/dev/null 2>&1; then
    echo "[ERROR] psql not found after package installation"
    echo "[INFO] Put PostgreSQL RPMs in $RPM_DIR or enable OS repositories, then rerun this step."
    exit 1
  fi
}

init_postgres() {
  echo "[INFO] Initializing PostgreSQL if needed..."

  if [ -f /var/lib/pgsql/data/PG_VERSION ]; then
    echo "[INFO] PostgreSQL data directory already initialized"
  elif command -v postgresql-setup >/dev/null 2>&1; then
    postgresql-setup --initdb
  elif command -v initdb >/dev/null 2>&1; then
    runuser -u postgres -- initdb -D /var/lib/pgsql/data
  else
    echo "[ERROR] Could not find postgresql-setup or initdb"
    exit 1
  fi

  systemctl enable --now postgresql
}

psql_postgres() {
  runuser -u postgres -- psql "$@"
}

create_repository() {
  echo "[INFO] Creating DPA database and users..."

  local app_password
  local reader_password
  app_password=$(generate_password)
  reader_password=$(generate_password)

  if [ -f "$DPA_CONF_DIR/dpa_repository.env" ]; then
    # shellcheck disable=SC1090
    . "$DPA_CONF_DIR/dpa_repository.env"
    app_password="${DPA_APP_PASSWORD:-$app_password}"
    reader_password="${DPA_READER_PASSWORD:-$reader_password}"
  fi

  psql_postgres -v ON_ERROR_STOP=1 \
    -v db_name="$DB_NAME" \
    -v app_user="$APP_USER" \
    -v reader_user="$READER_USER" \
    -v app_password="$app_password" \
    -v reader_password="$reader_password" <<'SQL'
SELECT format('CREATE DATABASE %I', :'db_name')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name')\gexec

SELECT format('CREATE ROLE %I LOGIN', :'app_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')\gexec

SELECT format('CREATE ROLE %I LOGIN', :'reader_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'reader_user')\gexec

ALTER ROLE :"app_user" WITH PASSWORD :'app_password';
ALTER ROLE :"reader_user" WITH PASSWORD :'reader_password';
SQL

  cat > "$DPA_CONF_DIR/dpa_repository.env" <<EOF
DPA_DB_NAME=$DB_NAME
DPA_APP_USER=$APP_USER
DPA_APP_PASSWORD=$app_password
DPA_READER_USER=$READER_USER
DPA_READER_PASSWORD=$reader_password
EOF
  chmod 600 "$DPA_CONF_DIR/dpa_repository.env"

  echo "[INFO] Loading DPA schema..."
  cp "$SCHEMA_SRC" "$DPA_SQL_DIR/dpa_repository.sql"
  psql_postgres -v ON_ERROR_STOP=1 -d "$DB_NAME" -f "$DPA_SQL_DIR/dpa_repository.sql"
}

install_python_dependencies() {
  echo "[INFO] Checking Python sampler dependencies..."

  if python3 - <<'PY' >/dev/null 2>&1
import oracledb
import psycopg2
PY
  then
    echo "[INFO] Python dependencies already installed"
    return
  fi

  if command -v pip3 >/dev/null 2>&1 && find "$PYTHON_WHEEL_DIR" -maxdepth 1 -type f -name "*.whl" | grep -q .; then
    echo "[INFO] Installing Python dependencies from $PYTHON_WHEEL_DIR"
    pip3 install --no-index --find-links "$PYTHON_WHEEL_DIR" -r "$REQ_SRC"
    return
  fi

  echo "[WARN] Python dependencies are not installed."
  echo "[WARN] Required: oracledb and psycopg2."
  echo "[WARN] Put wheels in $PYTHON_WHEEL_DIR and rerun, or install OS packages manually."
}

install_sampler() {
  echo "[INFO] Installing DPA sampler..."

  cp "$SAMPLER_SRC" "$DPA_BIN_DIR/dpa_sampler.py"
  chmod 750 "$DPA_BIN_DIR/dpa_sampler.py"

  local app_password
  app_password=$(grep '^DPA_APP_PASSWORD=' "$DPA_CONF_DIR/dpa_repository.env" | cut -d= -f2-)

  if [ ! -f "$DPA_CONF_DIR/dpa_sampler.env" ]; then
    cp "$ENV_SRC" "$DPA_CONF_DIR/dpa_sampler.env"
    sed -i "s|DPA_POSTGRES_DSN=.*|DPA_POSTGRES_DSN=\"host=localhost port=5432 dbname=$DB_NAME user=$APP_USER password=$app_password\"|" "$DPA_CONF_DIR/dpa_sampler.env"
    echo "[WARN] Created sampler env with Oracle credential placeholders: $DPA_CONF_DIR/dpa_sampler.env"
  elif grep -q "password=CHANGE_ME" "$DPA_CONF_DIR/dpa_sampler.env"; then
    sed -i "s|DPA_POSTGRES_DSN=.*|DPA_POSTGRES_DSN=\"host=localhost port=5432 dbname=$DB_NAME user=$APP_USER password=$app_password\"|" "$DPA_CONF_DIR/dpa_sampler.env"
  fi

  chmod 600 "$DPA_CONF_DIR/dpa_sampler.env"
  chown -R monitoring:monitoring "$DPA_DIR" "$DPA_LOG_DIR"
}

install_systemd_units() {
  echo "[INFO] Installing DPA sampler systemd units..."

  cp "$SERVICE_SRC" "$SERVICE_DST"
  cp "$TIMER_SRC" "$TIMER_DST"

  systemd-analyze verify "$SERVICE_DST" "$TIMER_DST" || true
  systemctl daemon-reload
  systemctl enable dpa_sampler.timer

  if grep -q "CHANGE_ME" "$DPA_CONF_DIR/dpa_sampler.env"; then
    echo "[WARN] Oracle DPA sampler credential placeholders still exist."
    echo "[WARN] Timer enabled but not started. Edit $DPA_CONF_DIR/dpa_sampler.env first."
  elif python3 - <<'PY' >/dev/null 2>&1
import oracledb
import psycopg2
PY
  then
    systemctl restart dpa_sampler.timer
    systemctl start dpa_sampler.service || true
  else
    echo "[WARN] Timer enabled but not started because Python dependencies are missing."
  fi
}

update_grafana_env() {
  local grafana_env="$BASE_DIR/grafana/conf/grafana.env"
  local reader_password
  reader_password=$(grep '^DPA_READER_PASSWORD=' "$DPA_CONF_DIR/dpa_repository.env" | cut -d= -f2-)

  if [ -f "$grafana_env" ]; then
    if grep -q '^DPA_POSTGRES_PASSWORD=' "$grafana_env"; then
      sed -i "s|^DPA_POSTGRES_PASSWORD=.*|DPA_POSTGRES_PASSWORD=$reader_password|" "$grafana_env"
    else
      echo "DPA_POSTGRES_PASSWORD=$reader_password" >> "$grafana_env"
    fi
    chown root:grafana "$grafana_env" || true
    chmod 640 "$grafana_env"

    if systemctl is-active --quiet grafana-server; then
      echo "[INFO] Restarting Grafana to pick up DPA PostgreSQL datasource password..."
      systemctl restart grafana-server
    fi
  else
    echo "[WARN] Grafana env not found yet: $grafana_env"
    echo "[WARN] 05_install_grafana.sh will install it; rerun this step after Grafana install to inject DPA_POSTGRES_PASSWORD."
  fi
}

install_postgres_packages
init_postgres
create_repository
install_python_dependencies
install_sampler
install_systemd_units
update_grafana_env

echo "[DONE] PostgreSQL DPA repository installed"
echo "[NEXT] Edit Oracle sampler credentials:"
echo "       vi $DPA_CONF_DIR/dpa_sampler.env"
echo ""
echo "Then install Python wheels if needed:"
echo "       cp oracledb*.whl psycopg2*.whl $PYTHON_WHEEL_DIR/"
echo "       ./10_install_postgres_dpa.sh"
echo ""
echo "Start sampler:"
echo "       systemctl restart dpa_sampler.timer"
echo "       systemctl start dpa_sampler.service"
echo "       journalctl -u dpa_sampler.service -n 100 --no-pager"
