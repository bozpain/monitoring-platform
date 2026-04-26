# Database Monitoring Platform - Deployment Plan

---

## Overview

Platform monitoring database berbasis:

- Prometheus (metrics collection)
- VictoriaMetrics (metrics storage)
- Grafana (dashboard visualization)
- Alertmanager (alerting)
- Exporters: Oracle, MSSQL, Node

Target:
- 100% free
- Offline-ready
- Scalable (100–1000 DB)
- Fokus non-production (VIT / SIT / UAT / PT)

---

## Architecture

Simpan gambar di:
docs/images/architecture.png

---

## VM Requirement

Start Small:
CPU: 4 Core  
RAM: 8–16 GB  
Disk: 100 GB  
OS: Oracle Linux 8  

---

## STEP 1 — Prepare VM

sudo -i  
yum install -y wget tar unzip curl vim net-tools  
useradd -m monitoring  

---

## STEP 2 — Create Directory

mkdir -p /monitoring && cd /monitoring

mkdir -p prometheus/bin prometheus/conf/alerts victoriametrics/bin victoriametrics/conf grafana/conf grafana/dashboards/oracle grafana/dashboards/mssql grafana/dashboards/node alertmanager/bin alertmanager/conf exporters/oracle exporters/mssql exporters/node config/targets data/prometheus data/victoriametrics data/alertmanager logs/prometheus logs/victoriametrics logs/grafana logs/alertmanager logs/exporters sources/tar sources/rpm sources/checksum

chown -R monitoring:monitoring /monitoring  
chmod -R 755 /monitoring  

---

## STEP 3 — Upload Binary

Upload ke:
/monitoring/sources/

Required:
prometheus.tar.gz  
victoriametrics.tar.gz  
alertmanager.tar.gz  
grafana.rpm  
node_exporter.tar.gz  
oracle_exporter.tar.gz  
mssql_exporter.tar.gz  

---

## STEP 4 — Install VictoriaMetrics

cd /monitoring/sources/tar  
tar -xvf victoriametrics*.tar.gz  

cp victoria-metrics-prod /monitoring/victoriametrics/bin/  
chmod +x /monitoring/victoriametrics/bin/*  

Buat service:
vi /etc/systemd/system/victoriametrics.service

Isi:

[Unit]
Description=VictoriaMetrics
After=network.target

[Service]
User=monitoring
ExecStart=/monitoring/victoriametrics/bin/victoria-metrics-prod -storageDataPath=/monitoring/data/victoriametrics -httpListenAddr=:8428
Restart=always

[Install]
WantedBy=multi-user.target

systemctl daemon-reload  
systemctl enable --now victoriametrics  

---

## STEP 5 — Install Prometheus

cd /monitoring/sources/tar  
tar -xvf prometheus*.tar.gz  

cp prometheus promtool /monitoring/prometheus/bin/  
chmod +x /monitoring/prometheus/bin/*  

Config:
vi /monitoring/prometheus/conf/prometheus.yml

Isi:

global:
  scrape_interval: 30s

scrape_configs:
- job_name: node
  file_sd_configs:
  - files:
    - /monitoring/config/targets/node_targets.yml

- job_name: oracle
  file_sd_configs:
  - files:
    - /monitoring/config/targets/oracle_targets.yml

- job_name: mssql
  file_sd_configs:
  - files:
    - /monitoring/config/targets/mssql_targets.yml

Service:
vi /etc/systemd/system/prometheus.service

systemctl enable --now prometheus  

---

## STEP 6 — Install Alertmanager

cd /monitoring/sources/tar  
tar -xvf alertmanager*.tar.gz  

cp alertmanager /monitoring/alertmanager/bin/  
chmod +x /monitoring/alertmanager/bin/*  

systemctl enable --now alertmanager  

---

## STEP 7 — Install Grafana

cd /monitoring/sources/rpm  
yum install -y grafana*.rpm  

systemctl enable --now grafana-server  

---

## STEP 8 — Install Node Exporter

cd /monitoring/sources/tar  
tar -xvf node_exporter*.tar.gz  

cp node_exporter /monitoring/exporters/node/  
chmod +x /monitoring/exporters/node/node_exporter  

systemctl enable --now node_exporter  

---

## STEP 9 — Install Oracle Exporter

cd /monitoring/sources/tar  
tar -xvf oracle_exporter*.tar.gz  

cp exporter /monitoring/exporters/oracle/  

systemctl enable --now oracle_exporter  

---

## STEP 10 — Install MSSQL Exporter

cd /monitoring/sources/tar  
tar -xvf mssql_exporter*.tar.gz  

cp exporter /monitoring/exporters/mssql/  

systemctl enable --now mssql_exporter  

---

## STEP 11 — Register Targets

vi /monitoring/config/targets/node_targets.yml

- targets:
  - "10.10.10.10:9100"
  labels:
    service: "node"
    environment: "sit"

systemctl restart prometheus  

---

## STEP 12 — Validation

Prometheus: http://IP:9090  
Grafana: http://IP:3000  
Alertmanager: http://IP:9093  

Check:
http://IP:9090/targets

---

## Troubleshooting

journalctl -u prometheus -f  
journalctl -u grafana-server -f  
journalctl -u alertmanager -f  

---

## Scaling

Edit:
/monitoring/config/targets/*.yml  

Restart:
systemctl restart prometheus  

---

## Final Checklist

- Prometheus running  
- Grafana login OK  
- Targets UP  
- Exporter running  
- Dashboard tampil  
- Alertmanager aktif  

---

END
