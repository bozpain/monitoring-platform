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

```text
- Scalable (ratusan DB)
- 100% free
- No internet dependency (offline ready)
- Enterprise-style observability
```

---

## 2. Directory Structure (Target Server)

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

## 3. Deployment Sequence (MANDATORY ORDER)

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

## 4. Step-by-Step Execution

---

### STEP 1 — Prepare VM

```bash
bash 01_prepare_vm.sh
```

Ensure:

- Time sync OK
- Firewall configured
- Required packages installed

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

### STEP 6 — (Optional) Alertmanager

```bash
bash 06_install_alertmanager.sh
```

---

### STEP 7 — Install Oracle Exporter

```bash
bash 07_install_oracle_exporter.sh
```

Ensure config:

```bash
/monitoring/config/oracle/oracle-metrics.toml
```

Verify:

```bash
curl http://localhost:9161/metrics
```

---

### STEP 8 — Install MSSQL Exporter

```bash
bash 08_install_mssql_exporter.sh
```

Ensure config:

```bash
/monitoring/config/mssql/mssql-metrics.toml
```

Verify:

```bash
curl http://localhost:9182/metrics
```

---

## 5. Prometheus Configuration

File:

```bash
/monitoring/config/prometheus.yml
```

Example jobs:

```yaml
scrape_configs:
  - job_name: oracle_exporter
    static_configs:
      - targets:
          - localhost:9161

  - job_name: mssql_exporter
    static_configs:
      - targets:
          - localhost:9182

  - job_name: node_exporter
    static_configs:
      - targets:
          - localhost:9100
```

---

## 6. Grafana Auto Provisioning

Dashboard path:

```bash
/monitoring/grafana/dashboards/
```

Structure:

```bash
oracle/
mssql/
```

Provisioning config:

```bash
/monitoring/grafana/provisioning/dashboards/
```

Auto load dashboards on startup.

---

## 7. Dashboards Included

### Oracle

```text
01 - Oracle Fleet Overview
02 - Oracle Performance DPA
03 - Oracle Sessions & Blocking
04 - Oracle SQL Activity
05 - Oracle Tablespace & Capacity
06 - Oracle RAC / ASM
```

---

### MSSQL

```text
01 - MSSQL Overview
02 - MSSQL Performance
03 - MSSQL Sessions & Blocking
04 - MSSQL Capacity
```

---

## 8. Service Management

Restart all:

```bash
systemctl daemon-reexec
systemctl restart victoriametrics
systemctl restart prometheus
systemctl restart grafana-server
systemctl restart oracle_exporter
systemctl restart mssql_exporter
systemctl restart node_exporter
```

---

## 9. Health Check

### Prometheus targets

```text
http://<server-ip>:9090/targets
```

All must be:

```text
UP
```

---

### Exporter check

```bash
curl localhost:9161/metrics
curl localhost:9182/metrics
```

---

### Grafana

- Dashboards visible
- Data populated

---

## 10. Troubleshooting

### Exporter not working

```bash
journalctl -u oracle_exporter -f
journalctl -u mssql_exporter -f
```

---

### No data in Grafana

Check:

```text
Prometheus → targets
Metric exists
Datasource configured
```

---

### Config file error

```bash
cat /monitoring/config/oracle/oracle-metrics.toml
cat /monitoring/config/mssql/mssql-metrics.toml
```

---

## 11. Scaling Strategy

```text
- Add exporter per DB host
- Central Prometheus scrape
- VictoriaMetrics for long retention
- Grafana for visualization
```

---

## 12. Final Notes

```text
- No internet dependency
- Fully scriptable deployment
- Operator friendly
- Extendable to PostgreSQL / MongoDB
```

---

## END OF DOCUMENT
