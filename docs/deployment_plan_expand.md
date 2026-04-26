# Deployment Plan Expand - 3 VM Architecture

## 1. Overview

This document describes the expansion of an existing single-node monitoring platform into a 3 VM architecture.

Important principle:

- VM1 (existing) remains as Control Plane
- No reinstallation on VM1
- Only configuration updates and workload separation are performed

---

## 2. Target Architecture

| VM  | Role                     | Services                          |
| --- | ------------------------ | --------------------------------- |
| VM1 | Control Plane (existing) | Prometheus, Grafana, Alertmanager |
| VM2 | Metrics Storage          | VictoriaMetrics                   |
| VM3 | Exporter Node            | All exporters                     |

Flow:

Database → Exporters (VM3) → Prometheus (VM1) → VictoriaMetrics (VM2)

Prometheus → Alertmanager (VM1)

Grafana → Prometheus (VM1)

---

## 3. Key Design Decision

- Prometheus becomes scrape + alert engine only
- VictoriaMetrics becomes long-term storage
- Exporters are moved out of Control Plane
- Alertmanager remains primary alert system

---

## 4. Pre-Check

Ensure:

[ ] Existing VM1 monitoring is working
[ ] Prometheus targets are UP
[ ] Grafana dashboards are working
[ ] Alertmanager is running
[ ] Systemd services already exist
[ ] Internal network between VM1, VM2, VM3 is reachable

---

## 5. DO NOT MODIFY VM1 STRUCTURE

Do NOT:

- Reinstall Prometheus
- Move Grafana
- Move Alertmanager
- Change directory structure

VM1 is **kept as-is**

---

## 6. Prepare VM2 (VictoriaMetrics)

Create directory:

```bash
mkdir -p /monitoring/victoriametrics/{bin,conf}
mkdir -p /monitoring/data/victoriametrics
mkdir -p /monitoring/logs/victoriametrics
```

Run VictoriaMetrics:

```bash
/monitoring/victoriametrics/bin/victoria-metrics-prod \
  -storageDataPath=/monitoring/data/victoriametrics \
  -retentionPeriod=90d \
  -httpListenAddr=:8428
```

Enable service:

```bash
systemctl enable victoria-metrics
systemctl start victoria-metrics
```

Validate:

```bash
curl http://VM2_IP:8428/metrics
```

---

## 7. Prepare VM3 (Exporter Node)

Create directory:

```bash
mkdir -p /monitoring/exporters
mkdir -p /monitoring/logs/exporters
```

Move exporters from VM1 → VM3:

- oracle exporter
- mssql exporter
- postgres exporter
- mongodb exporter
- node exporter

Enable services:

```bash
systemctl enable oracle-exporter
systemctl enable mssql-exporter
systemctl enable postgres-exporter
systemctl enable mongodb-exporter
systemctl enable node-exporter
```

Start:

```bash
systemctl start oracle-exporter
systemctl start mssql-exporter
systemctl start postgres-exporter
systemctl start mongodb-exporter
systemctl start node-exporter
```

---

## 8. Update Prometheus (VM1)

File:

```text
/monitoring/prometheus/conf/prometheus.yml
```

### 8.1 Remote Write → VM2

```yaml
remote_write:
  - url: "http://VM2_IP:8428/api/v1/write"
```

---

### 8.2 Update Scrape Targets → VM3

```yaml
scrape_configs:
  - job_name: "oracle"
    static_configs:
      - targets: ["VM3_IP:9161"]

  - job_name: "mssql"
    static_configs:
      - targets: ["VM3_IP:9182"]

  - job_name: "postgres"
    static_configs:
      - targets: ["VM3_IP:9187"]

  - job_name: "mongodb"
    static_configs:
      - targets: ["VM3_IP:9216"]

  - job_name: "node"
    static_configs:
      - targets: ["VM3_IP:9100"]
```

---

### 8.3 Alertmanager (NO CHANGE)

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - "localhost:9093"
```

---

### 8.4 Validate Config

```bash
/monitoring/prometheus/bin/promtool check config /monitoring/prometheus/conf/prometheus.yml
```

Restart Prometheus:

```bash
systemctl restart prometheus
```

---

## 9. Update Grafana (VM1)

NO CHANGE REQUIRED

Datasource tetap:

```text
http://localhost:9090
```

---

## 10. Update Exporter Connection (VM3)

IMPORTANT:

Do NOT use localhost unless DB is on same VM.

Example:

### Oracle

```bash
oracle://user:pass@DB_HOST:1521/SERVICE
```

### MSSQL

```bash
sqlserver://user:pass@DB_HOST:1433
```

---

## 11. Firewall Rules

Allow:

VM1 → VM2:

```text
8428
```

VM1 → VM3:

```text
9100
9161
9182
9187
9216
```

VM3 → DB:

```text
DB ports (Oracle, MSSQL, etc)
```

---

## 12. Startup Order

1. VM2 → VictoriaMetrics
2. VM3 → Exporters
3. VM1 → Prometheus
4. VM1 → Alertmanager
5. VM1 → Grafana

---

## 13. Validation

### Prometheus

```text
http://VM1:9090/targets
```

All must be:

```text
UP
```

---

### Alertmanager

```text
http://VM1:9093
```

---

### VictoriaMetrics

```bash
curl http://VM2:8428/metrics
```

---

### Grafana

```text
http://VM1:3000
```

Dashboard shows data

---

## 14. Final State

VM1:

- Prometheus RUNNING
- Grafana RUNNING
- Alertmanager RUNNING

VM2:

- VictoriaMetrics RUNNING

VM3:

- All exporters RUNNING

---

## 15. Important Notes

- VM1 remains unchanged (existing)
- Only Prometheus config is updated
- Exporters are moved to VM3
- Storage is moved to VM2
- Alertmanager stays primary alert system

---

## 16. Next Step

After expansion:

1. Add alert rules (DB level)
2. Add labels (env, app, db)
3. Add dashboard (DPA level)
4. Add auto-discovery (optional)

---
