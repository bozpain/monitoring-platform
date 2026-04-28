#!/bin/bash

set -euo pipefail

BASE_DIR="/monitoring"
MON_USER="monitoring"
INSTALL_PACKAGES="${INSTALL_PACKAGES:-auto}"

echo "[INFO] Preparing monitoring VM..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "[INFO] OS detected: ${PRETTY_NAME:-unknown}"
else
  echo "[WARN] /etc/os-release not found, cannot detect OS"
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "[ERROR] systemctl not found. This deployment requires a systemd-based Linux VM."
  exit 1
fi

echo "[INFO] Creating monitoring user if not exists..."
if ! id "$MON_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$MON_USER"
  echo "[INFO] User '$MON_USER' created"
else
  echo "[INFO] User '$MON_USER' already exists"
fi

echo "[INFO] Creating directory structure..."

mkdir -p "$BASE_DIR"/{prometheus/{bin,conf/alerts},victoriametrics/{bin,conf},grafana/{conf,dashboards},alertmanager/{bin,conf},exporters/{oracle,mssql,postgres,mongodb,node},config/targets,data/{prometheus,victoriametrics,alertmanager},logs/{prometheus,victoriametrics,grafana,alertmanager,exporters},sources/{rpm,tar,checksum}}

echo "[INFO] Setting permissions..."

chown -R "$MON_USER:$MON_USER" "$BASE_DIR"

chmod 755 "$BASE_DIR"
chmod 755 "$BASE_DIR/prometheus"
chmod 755 "$BASE_DIR/victoriametrics"
chmod 755 "$BASE_DIR/grafana"
chmod 755 "$BASE_DIR/alertmanager"
chmod 755 "$BASE_DIR/exporters"
chmod 755 "$BASE_DIR/config"
chmod 750 "$BASE_DIR/data"
chmod 750 "$BASE_DIR/logs"
chmod 755 "$BASE_DIR/sources"

echo "[INFO] Installing base packages..."

PACKAGES=(
  tar
  gzip
  unzip
  curl
  wget
  vim
  net-tools
  lsof
  chrony
  python3
  firewalld
  policycoreutils
  policycoreutils-python-utils
)

install_packages() {
  local package_manager=$1

  if [ "$INSTALL_PACKAGES" = "skip" ]; then
    echo "[INFO] INSTALL_PACKAGES=skip, skipping package installation"
    return
  fi

  if [ "$INSTALL_PACKAGES" = "auto" ]; then
    if ! "$package_manager" repolist enabled >/dev/null 2>&1; then
      echo "[WARN] No enabled $package_manager repositories detected. Skipping package installation."
      echo "[WARN] Install required packages manually or rerun with INSTALL_PACKAGES=online."
      return
    fi
  fi

  "$package_manager" install -y "${PACKAGES[@]}"
}

if command -v dnf >/dev/null 2>&1; then
  install_packages dnf
elif command -v yum >/dev/null 2>&1; then
  install_packages yum
else
  echo "[WARN] dnf/yum not found, skipping package install"
fi

echo "[INFO] Enabling chronyd..."

if systemctl list-unit-files chronyd.service >/dev/null 2>&1; then
  systemctl enable --now chronyd || true
else
  echo "[WARN] chronyd service not found, skipping"
fi

echo "[INFO] Checking firewalld..."

if systemctl list-unit-files firewalld.service >/dev/null 2>&1; then
  systemctl enable --now firewalld || true
else
  echo "[WARN] firewalld service not found. Configure firewall manually if required."
fi

echo "[INFO] Checking required commands..."

for cmd in tar gzip curl systemctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Required command not found: $cmd"
    exit 1
  fi
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "[WARN] python3 not found. scripts/generate_targets.py must be run before deployment or installed manually."
fi

if command -v getenforce >/dev/null 2>&1; then
  echo "[INFO] SELinux mode: $(getenforce)"
else
  echo "[WARN] getenforce not found, skipping SELinux status check"
fi

echo "[INFO] Final directory check:"
find "$BASE_DIR" -maxdepth 3 -type d | sort

echo "[DONE] VM preparation completed"
