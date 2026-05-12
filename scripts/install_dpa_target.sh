#!/bin/bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/monitoring}"
TARGET_DIR="./config/dpa/targets"
DPA_CONF_DIR="$BASE_DIR/dpa/conf"
REPOSITORY_ENV="$DPA_CONF_DIR/dpa_repository.env"

usage() {
  echo "Usage: $0 <target-name>"
  echo ""
  echo "Example:"
  echo "  $0 db-vm-01"
  echo ""
  echo "Expected template:"
  echo "  $TARGET_DIR/<target-name>.env.example"
}

if [ "${1:-}" = "" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

target=$1
template="$TARGET_DIR/$target.env.example"
destination="$DPA_CONF_DIR/$target.env"

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

if [ ! -f "$template" ]; then
  echo "[ERROR] DPA target template not found: $template"
  echo "[INFO] Set oracle_dpa=yes in inventory/targets.csv and run:"
  echo "       python3 scripts/generate_targets.py"
  exit 1
fi

if [ ! -f "$REPOSITORY_ENV" ]; then
  echo "[ERROR] DPA repository env not found: $REPOSITORY_ENV"
  echo "[INFO] Run ./10_install_postgres_dpa.sh first."
  exit 1
fi

if ! id monitoring >/dev/null 2>&1; then
  echo "[ERROR] User 'monitoring' does not exist. Run 01_prepare_vm.sh first."
  exit 1
fi

# shellcheck disable=SC1090
. "$REPOSITORY_ENV"

if [ -z "${DPA_APP_PASSWORD:-}" ]; then
  echo "[ERROR] DPA_APP_PASSWORD not found in $REPOSITORY_ENV"
  exit 1
fi

mkdir -p "$DPA_CONF_DIR"

if [ -f "$destination" ]; then
  backup="$destination.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$destination" "$backup"
  echo "[INFO] Existing env backed up to $backup"
fi

cp "$template" "$destination"
sed -i "s|DPA_POSTGRES_DSN=.*|DPA_POSTGRES_DSN=\"host=localhost port=5432 dbname=dpa_repository user=dpa_app password=$DPA_APP_PASSWORD\"|" "$destination"

chmod 600 "$destination"
chown monitoring:monitoring "$destination"

echo "[DONE] DPA target env installed: $destination"
echo ""
if grep -q "CHANGE_ME" "$destination"; then
  echo "[NEXT] Edit Oracle credentials before starting sampler:"
  echo "       vi $destination"
  echo ""
fi

echo "[NEXT] Enable and test sampler:"
echo "       systemctl enable --now dpa_sampler@$target.timer"
echo "       systemctl start dpa_sampler@$target.service"
echo "       journalctl -u dpa_sampler@$target.service -n 100 --no-pager"
