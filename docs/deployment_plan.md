# deployment_plan.md

## Database Monitoring Platform Deployment Plan

---

## 1. Overview

Deployment ini membangun platform monitoring database berbasis:

- Prometheus (metrics scraping & alert rules)
- VictoriaMetrics (metrics storage)
- Grafana (visualization)
- Alertmanager (alert notification via SMTP email)
- Exporters:
  - Oracle Exporter
  - MSSQL Exporter
  - Node Exporter

Target:

- Scalable hingga ratusan server / database
- 100% free stack
- Offline-ready (no internet dependency)
- Fokus environment development / non-production
- Clean, modular, enterprise-style observability platform

---

## 2. Directory Structure (Server)

/monitoring/
├── prometheus/
│ ├── bin/
│ └── conf/
│ └── alerts/
├── victoriametrics/
│ ├── bin/
│ └── conf/
├── grafana/
│ ├── conf/
│ └── dashboards/
│ ├── oracle/
│ ├── mssql/
│ └── node/
├── alertmanager/
│ ├── bin/
│ └── conf/
├── exporters/
│ ├── oracle/
│ ├── mssql/
│ └── node/
├── config/
│ └── targets/
├── data/
│ ├── prometheus/
│ ├── victoriametrics/
│ └── alertmanager/
├── logs/
│ ├── prometheus/
│ ├── victoriametrics/
│ ├── grafana/
│ ├── alertmanager/
│ └── exporters/
└── sources/

---

## 3. Deployment Order (MANDATORY)

01_prepare_vm.sh
02_install_victoriametrics.sh
06_install_alertmanager.sh
03_install_prometheus.sh
04_install_node_exporter.sh
07_install_oracle_exporter.sh
08_install_mssql_exporter.sh
05_install_grafana.sh

---

## 4. Standard Label (WAJIB)

labels:
service: "<node|oracle|mssql>"
environment: "development"
site: "development"
team: "dba"
role: "<infrastructure|database>"
db_type: "<oracle|mssql|none>"
app: "<application_name>"
tier: "<vit|sit|uat|pt|shared>"
owner: "<team_or_pic>"

---

## 5. Prometheus Configuration

/monitoring/prometheus/conf/prometheus.yml

global:
scrape_interval: 30s
evaluation_interval: 30s

rule_files:

- /monitoring/prometheus/conf/alerts/\*.yml

alerting:
alertmanagers: - static_configs: - targets: - "localhost:9093"

scrape_configs:

- job_name: "node"
  file_sd_configs:
  - files:
    - /monitoring/config/targets/node_targets.yml

- job_name: "oracle"
  file_sd_configs:
  - files:
    - /monitoring/config/targets/oracle_targets.yml

- job_name: "mssql"
  file_sd_configs:
  - files:
    - /monitoring/config/targets/mssql_targets.yml

---

## 6. Target Management (file_sd)

/monitoring/config/targets/

node_targets.yml
oracle_targets.yml
mssql_targets.yml

---

## 7. Grafana Auto Provisioning

/etc/grafana/provisioning/

datasources:

- prometheus.yml

dashboards:

- dashboards.yml

---

## 8. Dashboards

Oracle:

- oracle_overview.json
- oracle_performance_dpa.json
- oracle_sessions_blocking.json
- oracle_sql_activity.json
- oracle_tablespace_capacity.json

MSSQL:

- mssql_overview.json
- mssql_performance_dpa.json
- mssql_sessions_blocking.json
- mssql_capacity.json

Node:

- node_overview.json
- node_capacity.json
- node_io_deep_dive.json
- node_network.json

---

## 9. Alert Rules

/monitoring/prometheus/conf/alerts/

oracle_rules.yml
mssql_rules.yml
node_rules.yml

---

## 10. Alertmanager (SMTP)

/monitoring/alertmanager/conf/alertmanager.yml

global:
smtp_smarthost: "smtp.company.local:587"
smtp_from: "db-monitoring@company.local"
smtp_auth_username: "db-monitoring@company.local"
smtp_auth_password: "CHANGE_ME"

route:
receiver: "dba-email"

receivers:

- name: "dba-email"
  email_configs:
  - to: "dba-team@company.local"

---

## 11. Service Management

systemctl restart victoriametrics
systemctl restart alertmanager
systemctl restart prometheus
systemctl restart grafana-server
systemctl restart node_exporter
systemctl restart oracle_exporter
systemctl restart mssql_exporter

---

## 12. Health Check

Prometheus:
http://<server>:9090/targets

Alertmanager:
http://<server>:9093

Grafana:
http://<server>:3000

---

## 13. Troubleshooting

journalctl -u prometheus -f
journalctl -u alertmanager -f
journalctl -u grafana-server -f

---

## 14. Scaling Strategy

Manual:
/monitoring/config/targets/

Future:
inventory.csv → generate_targets → targets.yml

---

## END
