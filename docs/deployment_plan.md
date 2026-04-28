# Database Monitoring Platform - Deployment Plan

This is the main deployment runbook for the single-VM installation path.

For 3 VM expansion, use [deployment_plan_expand.md](deployment_plan_expand.md). For DBA grants, firewall details, SELinux notes, VictoriaMetrics tuning, and validation queries, use [operator_handover.md](operator_handover.md).

## 1. Target Architecture

Single VM deployment installs:

| Component | Purpose | Port |
| --- | --- | --- |
| VictoriaMetrics | Long-retention metrics storage | `8428` |
| Alertmanager | Alert routing and email notification | `9093` |
| Prometheus | Scrape, service discovery, rules, remote write | `9090` |
| Node exporter | OS/server metrics | `9100` |
| Oracle exporter | Oracle DB metrics | `9161` |
| MSSQL exporter | SQL Server metrics | `9182` |
| Grafana | Dashboards and visualization | `3000` |

Data flow:

```text
Node/Oracle/MSSQL exporters -> Prometheus -> VictoriaMetrics -> Grafana
                                      |
                                      v
                                Alertmanager
```

## 2. VM Requirement

Recommended starter sizing:

| Resource | Minimum starter value |
| --- | --- |
| OS | Oracle Linux 8 or RHEL-compatible Linux |
| CPU | 4 cores |
| RAM | 8-16 GB |
| Disk | 100 GB minimum, larger for long retention |
| Runtime | `systemd`, `dnf` or `yum`, local root/sudo access |

Expected base packages:

```text
tar gzip unzip curl wget vim net-tools lsof chrony python3 firewalld policycoreutils policycoreutils-python-utils
```

## 3. Prepare Offline Packages

Upload approved packages to:

```text
/monitoring/sources/tar
/monitoring/sources/rpm
/monitoring/sources/checksum
```

Expected file patterns:

| Component | File pattern |
| --- | --- |
| Prometheus | `prometheus-*.linux-amd64.tar.gz` |
| VictoriaMetrics | `victoria-metrics-linux-amd64-*.tar.gz` |
| Alertmanager | `alertmanager-*.linux-amd64.tar.gz` |
| Node exporter | `node_exporter*.tar.gz` |
| Oracle exporter | `oracledb_exporter*.tar.gz` |
| MSSQL exporter | `mssql_exporter*.tar.gz` |
| Grafana | `grafana-*.rpm` |

If `/monitoring` does not exist yet, copy the repo to the VM and run the prepare step first:

```bash
sudo ./01_prepare_vm.sh
```

Then upload the packages and verify checksums:

```bash
cd /monitoring/sources
sha256sum -c checksum/SHA256SUMS
```

For offline VMs where OS packages are already installed:

```bash
sudo INSTALL_PACKAGES=skip ./01_prepare_vm.sh
```

For online VMs or VMs with an approved internal repository:

```bash
sudo INSTALL_PACKAGES=online ./01_prepare_vm.sh
```

## 4. Configure Inventory

Edit the source inventory in the repo:

```bash
vi inventory/targets.csv
```

Required columns:

```text
host,ip,node,oracle,mssql,app,tier,owner
```

Use `yes` or `no` for `node`, `oracle`, and `mssql`.

Generate Prometheus `file_sd` target files:

```bash
python3 scripts/generate_targets.py
```

Generated files:

```text
config/targets/node_targets.yml
config/targets/oracle_targets.yml
config/targets/mssql_targets.yml
```

Review the generated target ports:

| Target type | Port |
| --- | --- |
| Node | `9100` |
| Oracle | `9161` |
| MSSQL | `9182` |

## 5. Deploy All Components

Run from the repository root:

```bash
sudo ./deploy_all.sh
```

The deployment script runs this order:

```text
validate generated targets
01_prepare_vm.sh
02_install_victoriametrics.sh
06_install_alertmanager.sh
03_install_prometheus.sh
04_install_node_exporter.sh
07_install_oracle_exporter.sh
08_install_mssql_exporter.sh
05_install_grafana.sh
09_health_check.sh
```

This order is intentionally dependency-first, so the script numbers are not strictly sequential. Alertmanager is installed before Prometheus so the alerting endpoint is already available when Prometheus starts. Grafana is installed after VictoriaMetrics and Prometheus because its datasource and dashboards depend on them.

## 6. Manual Step-By-Step Deployment

Use this only when you want to troubleshoot or install one component at a time:

```bash
sudo ./01_prepare_vm.sh
sudo ./02_install_victoriametrics.sh
sudo ./06_install_alertmanager.sh
sudo ./03_install_prometheus.sh
sudo ./04_install_node_exporter.sh
sudo ./07_install_oracle_exporter.sh
sudo ./08_install_mssql_exporter.sh
sudo ./05_install_grafana.sh
sudo ./09_health_check.sh
```

Oracle and MSSQL exporter installers create service files and credential templates, but they do not start the exporters until the connection strings are correct.

## 7. Configure Database Exporters

Create DB monitoring users and grants first. Use [operator_handover.md](operator_handover.md) for SQL examples.

Edit Oracle exporter credentials:

```bash
sudo vi /monitoring/exporters/oracle/oracle_exporter.env
sudo systemctl restart oracle_exporter
sudo systemctl status oracle_exporter --no-pager
```

Edit MSSQL exporter credentials:

```bash
sudo vi /monitoring/exporters/mssql/mssql_exporter.env
sudo systemctl restart mssql_exporter
sudo systemctl status mssql_exporter --no-pager
```

Quick endpoint checks:

```bash
curl http://localhost:9161/metrics | grep '^oracle_up'
curl http://localhost:9182/metrics | grep '^mssql_up'
```

## 8. Configure Alertmanager

Edit SMTP settings:

```bash
sudo vi /monitoring/alertmanager/conf/alertmanager.yml
sudo systemctl restart alertmanager
```

Replace all `CHANGE_ME` values and company placeholders before relying on alert email.

## 9. Tune VictoriaMetrics

Default tuning is installed from:

```text
config/victoriametrics/victoriametrics.env.example
```

Runtime path:

```text
/monitoring/victoriametrics/conf/victoriametrics.env
```

Common settings:

| Setting | Purpose |
| --- | --- |
| `VM_RETENTION_PERIOD` | Metrics retention period |
| `VM_MEMORY_ALLOWED_PERCENT` | Internal VictoriaMetrics memory budget |
| `VM_MIN_FREE_DISK_SPACE` | Disk free-space guardrail |
| `VM_SEARCH_MAX_QUERY_DURATION` | Query timeout |
| `VM_SEARCH_MAX_CONCURRENT_REQUESTS` | Query concurrency limit |
| `VM_SEARCH_MAX_QUEUE_DURATION` | Query queue wait limit |

Apply changes:

```bash
sudo systemctl restart victoriametrics
curl -fsS http://localhost:8428/health
```

## 10. Tune Prometheus

Prometheus keeps short local retention and sends long-term data to VictoriaMetrics through `remote_write`.

Default tuning is installed from:

```text
config/prometheus/prometheus.env.example
```

Runtime path:

```text
/monitoring/prometheus/conf/prometheus.env
```

Common settings:

| Setting | Purpose |
| --- | --- |
| `PROM_RETENTION_TIME` | Short local TSDB retention |
| `PROM_RETENTION_SIZE` | Local TSDB disk cap |
| `PROM_QUERY_TIMEOUT` | Query timeout |
| `PROM_QUERY_MAX_CONCURRENCY` | Maximum concurrent queries |
| `PROM_QUERY_MAX_SAMPLES` | Maximum samples per query |
| `PROM_REMOTE_FLUSH_DEADLINE` | Grace period for remote-write flush on shutdown |

Apply changes:

```bash
sudo systemctl restart prometheus
curl -fsS http://localhost:9090/-/ready
```

Remote-write queue tuning is defined in:

```text
config/prometheus.yml
```

## 11. Open Firewall Ports

For single VM control plane access:

```bash
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=9090/tcp
sudo firewall-cmd --permanent --add-port=9093/tcp
sudo firewall-cmd --permanent --add-port=8428/tcp
sudo firewall-cmd --reload
```

For exporter hosts:

```bash
sudo firewall-cmd --permanent --add-port=9100/tcp
sudo firewall-cmd --permanent --add-port=9161/tcp
sudo firewall-cmd --permanent --add-port=9182/tcp
sudo firewall-cmd --reload
```

## 12. Validate Deployment

Run the health check:

```bash
sudo ./09_health_check.sh
```

Open these URLs:

```text
http://VM_IP:9090/targets
http://VM_IP:9090/alerts
http://VM_IP:8428
http://VM_IP:3000
http://VM_IP:9093
```

Prometheus config and rules:

```bash
sudo /monitoring/prometheus/bin/promtool check config /monitoring/prometheus/conf/prometheus.yml
sudo /monitoring/prometheus/bin/promtool check rules /monitoring/prometheus/conf/alerts/*.yml
```

VictoriaMetrics remote-write validation:

```bash
curl -G 'http://localhost:8428/api/v1/query' --data-urlencode 'query=up'
curl -G 'http://localhost:8428/api/v1/query' --data-urlencode 'query=oracle_up'
curl -G 'http://localhost:8428/api/v1/query' --data-urlencode 'query=mssql_up'
```

## 13. Troubleshooting

Service logs:

```bash
sudo journalctl -u prometheus -n 100 --no-pager
sudo journalctl -u victoriametrics -n 100 --no-pager
sudo journalctl -u grafana-server -n 100 --no-pager
sudo journalctl -u alertmanager -n 100 --no-pager
sudo journalctl -u oracle_exporter -n 100 --no-pager
sudo journalctl -u mssql_exporter -n 100 --no-pager
```

Service status:

```bash
sudo systemctl status prometheus --no-pager
sudo systemctl status victoriametrics --no-pager
sudo systemctl status grafana-server --no-pager
sudo systemctl status alertmanager --no-pager
sudo systemctl status oracle_exporter --no-pager
sudo systemctl status mssql_exporter --no-pager
```

## 14. Final Checklist

- Offline packages and SHA256 checksums are approved.
- `inventory/targets.csv` is reviewed.
- `config/targets/*.yml` files are generated.
- `deploy_all.sh` completed successfully.
- DB monitoring users are created.
- Oracle and MSSQL exporter credentials are updated.
- Exporter targets are `UP` in Prometheus.
- Prometheus rules load without errors.
- VictoriaMetrics contains `up`, `oracle_up`, and `mssql_up`.
- Grafana datasource is healthy.
- Alertmanager SMTP settings are updated and tested.
