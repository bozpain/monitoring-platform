# deployment_plan.md

## Database Monitoring Platform Deployment Plan

---

## 1. Overview

Deployment ini membangun platform monitoring database berbasis:

- Prometheus (scraper)
- VictoriaMetrics (storage)
- Grafana (visualization)
- Exporters:
  - Oracle Exporter (custom metrics)
  - MSSQL Exporter (custom metrics)
  - Node Exporter (OS metrics)

Target:

- Scalable (ratusan DB)
- 100% free
- No internet dependency (offline ready)
- Enterprise-style observability

---

## 2. Prerequisite (Download)

Semua binary dan dependency harus disiapkan sebelum deployment.

---

### 2.1 Core Components

Download:

- VictoriaMetrics (single binary)
- Prometheus (tar.gz)
- Grafana (rpm / tar.gz)
- Alertmanager (optional)
- Node Exporter (tar.gz)

---

### 2.2 Database Exporters

#### Oracle Exporter

- oracle_exporter binary
- Oracle Instant Client (basic + sqlplus)

---

#### MSSQL Exporter

- mssql_exporter binary
- ODBC Driver (Microsoft)
- sqlcmd tools (optional)

---

### 2.3 OS Dependencies (Oracle Linux)

Download dari yum.oracle.com:

- libaio
- libnsl
- glibc
- libstdc++
- unixODBC

---

### 2.4 Grafana Plugins (Optional)

- grafana plugins (offline package)

---

### 2.5 File Repository Structure

```bash
sources/
├── tar/
│   ├── prometheus.tar.gz
│   ├── victoriametrics.tar.gz
│   ├── node_exporter.tar.gz
│   ├── oracle_exporter.tar.gz
│   └── mssql_exporter.tar.gz
├── rpm/
│   ├── grafana.rpm
│   └── dependencies.rpm
└── checksum/
```

---

### 2.6 Transfer ke Server

```bash
scp -r sources/ user@server:/monitoring/sources/
```

---

### 2.7 Validation

```bash
ls /monitoring/sources/tar
ls /monitoring/sources/rpm
```

---

### 2.8 Notes

- Tidak ada download langsung dari server
- Semua dependency harus tersedia sebelum deployment
- Pastikan versi kompatibel (Oracle, MSSQL, OS)

---

## 3. Directory Structure (Target Server)

```bash
/monitoring/
├── prometheus/
├── victoriametrics/
├── grafana/
├── exporters/
│   ├── oracle/
│   ├── mssql/
│   └── node/
├── config/
│   ├── prometheus.yml
│   ├── oracle/
│   │   └── oracle-metrics.toml
│   └── mssql/
│       └── mssql-metrics.toml
├── data/
├── logs/
└── systemd/
```

---

## 4. Deployment Sequence (MANDATORY ORDER)

```text
01_prepare_vm.sh
02_install_victoriametrics.sh
03_install_prometheus.sh
04_install_node_exporter.sh
05_install_grafana.sh
06_install_alertmanager.sh (optional)
07_install_oracle_exporter.sh
08_install_mssql_exporter.sh
```

---

## 5. Step-by-Step Execution

---

### STEP 1 — Prepare VM

```bash
bash 01_prepare_vm.sh
```

---

### STEP 2 — Install VictoriaMetrics

```bash
bash 02_install_victoriametrics.sh
```

Verify:

```bash
curl http://localhost:8428/metrics
```

---

### STEP 3 — Install Prometheus

```bash
bash 03_install_prometheus.sh
```

Verify:

```bash
curl http://localhost:9090
```

---

### STEP 4 — Install Node Exporter

```bash
bash 04_install_node_exporter.sh
```

Verify:

```bash
curl http://localhost:9100/metrics
```

---

### STEP 5 — Install Grafana

```bash
bash 05_install_grafana.sh
```

Access:

```text
http://<server-ip>:3000
```

Default login:

- admin / admin

---

### STEP 6 — Alertmanager (Optional)

```bash
bash 06_install_alertmanager.sh
```

---

### STEP 7 — Oracle Exporter

```bash
bash 07_install_oracle_exporter.sh
```

Verify:

```bash
curl http://localhost:9161/metrics
```

---

### STEP 8 — MSSQL Exporter

```bash
bash 08_install_mssql_exporter.sh
```

Verify:

```bash
curl http://localhost:9182/metrics
```

---

## 6. Prometheus Configuration

File:

```bash
/monitoring/config/prometheus.yml
```

```yaml
scrape_configs:
  - job_name: oracle_exporter
    static_configs:
      - targets: ["localhost:9161"]

  - job_name: mssql_exporter
    static_configs:
      - targets: ["localhost:9182"]

  - job_name: node_exporter
    static_configs:
      - targets: ["localhost:9100"]
```

---

## 7. Grafana Auto Provisioning

```bash
/monitoring/grafana/dashboards/
```

```text
oracle/
mssql/
```

---

## 8. Dashboards Included

### Oracle

- 01 - Oracle Fleet Overview
- 02 - Oracle Performance DPA
- 03 - Oracle Sessions & Blocking
- 04 - Oracle SQL Activity
- 05 - Oracle Tablespace & Capacity
- 06 - Oracle RAC / ASM

---

### MSSQL

- 01 - MSSQL Overview
- 02 - MSSQL Performance
- 03 - MSSQL Sessions & Blocking
- 04 - MSSQL Capacity

---

## 9. Service Management

```bash
systemctl restart victoriametrics
systemctl restart prometheus
systemctl restart grafana-server
systemctl restart oracle_exporter
systemctl restart mssql_exporter
systemctl restart node_exporter
```

---

## 10. Health Check

Prometheus:

```text
http://<server-ip>:9090/targets
```

All status:

```text
UP
```

---

## 11. Troubleshooting

```bash
journalctl -u oracle_exporter -f
journalctl -u mssql_exporter -f
```

---

## 12. Scaling Strategy

- Add exporter per DB host
- Central Prometheus scrape
- VictoriaMetrics for long retention
- Grafana for visualization

---

## END OF DOCUMENT
