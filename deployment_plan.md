# Deployment Plan

Step-by-step guide to deploy Monitoring Platform on a new VM.

---

## 1. Prerequisites

### 1.1 VM Requirements

- OS: Oracle Linux 7 / 8
- CPU: Minimum 2 vCPU
- Memory: Minimum 4 GB
- Disk: Minimum 50 GB

---

### 1.2 Access

- SSH access to VM
- Root or sudo access

---

### 1.3 Required Files (Offline)

Prepare from laptop and copy to VM:

```text
victoria-metrics-linux-amd64-*.tar.gz
prometheus-*.linux-amd64.tar.gz
node_exporter-*.linux-amd64.tar.gz
alertmanager-*.linux-amd64.tar.gz
oracledb_exporter*.tar.gz
grafana-*.rpm
```

---

## 2. Copy Files to VM

From laptop:

```bash
scp *.tar.gz monitoring@VM_IP:/monitoring/sources/tar/
scp *.rpm monitoring@VM_IP:/monitoring/sources/rpm/
```

---

## 3. Clone Repository

```bash
cd ~
git clone https://github.com/bozpain/monitoring-platform.git
cd monitoring-platform
```

---

## 4. Run Deployment

### Recommended (One Command)

```bash
sudo su -
cd /home/monitoring/monitoring-platform

./deploy_all.sh
```

---

### Alternative (Manual Step-by-Step)

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

## 5. Configure Oracle Exporter (MANDATORY)

Edit configuration:

```bash
vi /monitoring/exporters/oracle/oracle_exporter.env
```

Example:

```bash
DATA_SOURCE_NAME=username/password@//db-host:1521/service_name
```

Start service:

```bash
systemctl restart oracle_exporter
systemctl status oracle_exporter --no-pager
```

---

## 6. Verify Services

```bash
systemctl status victoriametrics --no-pager
systemctl status prometheus --no-pager
systemctl status node_exporter --no-pager
systemctl status grafana-server --no-pager
systemctl status alertmanager --no-pager
systemctl status oracle_exporter --no-pager
```

All services must be:

```text
active (running)
```

---

## 7. Web Access

```text
Grafana          http://VM_IP:3000
Prometheus       http://VM_IP:9090
VictoriaMetrics  http://VM_IP:8428
Alertmanager     http://VM_IP:9093
```

---

## 8. Prometheus Target Check

Open:

```text
http://VM_IP:9090/targets
```

Expected:

```text
prometheus      UP
node_exporter   UP
oracle_exporter UP
```

---

## 9. Grafana Setup (Auto Provisioned)

### Login

```text
http://VM_IP:3000
```

```text
username: admin
password: admin
```

---

### Data Source

VictoriaMetrics datasource is automatically provisioned.

```text
Name: VictoriaMetrics
URL : http://localhost:8428
```

---

### Dashboard

Dashboard is automatically created.

```text
Folder   : Oracle
Dashboard: Oracle DPA Monitoring
```

---

### Optional Manual Import

If dashboard does not appear:

```text
Dashboards → New → Import → Upload JSON
```

File:

```text
/monitoring/grafana/dashboards/oracle-dpa-dashboard.json
```

---

## 10. Validation Checklist

- [ ] VictoriaMetrics running
- [ ] Prometheus running
- [ ] Node Exporter UP
- [ ] Oracle Exporter UP
- [ ] Grafana accessible
- [ ] Dashboard loaded
- [ ] Metrics visible

---

## 11. Troubleshooting

### Service not running

```bash
systemctl status <service>
journalctl -u <service> -n 50
```

---

### Port not listening

```bash
netstat -tulnp | grep <port>
```

---

### Exporter no data

```bash
curl http://localhost:9100/metrics
curl http://localhost:9161/metrics
```

---

### Prometheus target DOWN

```bash
systemctl restart prometheus
```

---

### Grafana dashboard missing

```bash
systemctl restart grafana-server
```

---

## 12. Notes

- Always run scripts as root
- Ensure files exist in `/monitoring/sources`
- Oracle exporter requires manual configuration
- No internet required after file transfer
- Grafana datasource & dashboard auto-provisioned

---

## Deployment Complete

Monitoring platform is ready for use.
