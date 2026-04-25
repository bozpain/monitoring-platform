# Monitoring Platform

Lightweight database monitoring platform using Prometheus, VictoriaMetrics, Grafana, Alertmanager, and database exporters.

---

## Architecture

```text
Exporters
  ├── Node Exporter
  ├── Oracle Exporter
  ├── MSSQL Exporter
  ├── PostgreSQL Exporter
  └── MongoDB Exporter
        ↓
Prometheus
        ↓ remote_write
VictoriaMetrics
        ↓
Grafana
        ↓
Alertmanager
```

---

## VM Directory Standard

All monitoring components must follow this structure:

```text
/monitoring/
├── prometheus/        # binary + config
├── victoriametrics/   # metric storage engine
├── grafana/           # config backup
├── alertmanager/      # alert engine
├── exporters/         # all exporters
├── data/              # metric data
├── logs/              # service logs
└── sources/           # offline packages (tar/rpm)
```

---

## Required Offline Files

Place files here:

```text
/monitoring/sources/tar/
/monitoring/sources/rpm/
```

Minimum required:

```text
victoria-metrics-linux-amd64-*.tar.gz
prometheus-*.linux-amd64.tar.gz
node_exporter-*.linux-amd64.tar.gz
alertmanager-*.linux-amd64.tar.gz
oracledb_exporter*.tar.gz
grafana-*.rpm
```

---

## Deployment

### One Command Deployment (Recommended)

Run as root on the monitoring VM:

```bash
./deploy_all.sh
```

---

### Manual Deployment (Advanced / Debug)

```bash
./01_prepare_vm.sh
./02_install_victoriametrics.sh
./03_install_prometheus.sh
./04_install_node_exporter.sh
./05_install_grafana.sh
./06_install_alertmanager.sh
./07_install_oracle_exporter.sh
```

---

## Post Deployment (Required)

### Configure Oracle Exporter

Edit:

```bash
vi /monitoring/exporters/oracle/oracle_exporter.env
```

Example:

```bash
DATA_SOURCE_NAME=username/password@//host:1521/service_name
```

Start exporter:

```bash
systemctl restart oracle_exporter
systemctl status oracle_exporter --no-pager
```

---

## Service Ports

| Component       | Port |
| --------------- | ---- |
| Grafana         | 3000 |
| Prometheus      | 9090 |
| Alertmanager    | 9093 |
| VictoriaMetrics | 8428 |
| Node Exporter   | 9100 |
| Oracle Exporter | 9161 |

---

## Health Check

```bash
systemctl status victoriametrics --no-pager
systemctl status prometheus --no-pager
systemctl status node_exporter --no-pager
systemctl status grafana-server --no-pager
systemctl status alertmanager --no-pager
systemctl status oracle_exporter --no-pager
```

---

## Web URLs

```text
Grafana          http://VM_IP:3000
Prometheus       http://VM_IP:9090
VictoriaMetrics  http://VM_IP:8428
Alertmanager     http://VM_IP:9093
```

---

## Prometheus Target Check

Open:

```text
http://VM_IP:9090/targets
```

Expected targets:

```text
prometheus      UP
node_exporter   UP
oracle_exporter UP
```

---

## Git Notes

Do NOT commit:

```text
real env files
binary tar/rpm files
monitoring data
logs
password files
```

---

## Notes

- Prometheus acts as scraper only
- VictoriaMetrics is the main storage backend
- Grafana reads from VictoriaMetrics
- Alertmanager handles alert routing
- Exporters provide metrics from OS and databases

---
