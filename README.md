# Internal Database Observability Platform

Centralized monitoring platform for database and infrastructure metrics, built with:

- Exporters: collect metrics from DB and server hosts
- Prometheus: scrape exporters, service discovery, relabeling, alert rules
- VictoriaMetrics: long-retention metrics storage
- Grafana: dashboards and visualization
- Alertmanager: alert routing and notifications

## Architecture

![Architecture](docs/images/architecture.png)

Flow:

1. Node, Oracle, and MSSQL exporters expose metrics.
2. Prometheus scrapes exporter targets from generated `file_sd` YAML files.
3. Prometheus sends metrics to VictoriaMetrics using `remote_write`.
4. Grafana reads metrics from VictoriaMetrics.
5. Prometheus sends alerts to Alertmanager.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `01_prepare_vm.sh` to `09_health_check.sh` | Step-by-step installer scripts |
| `deploy_all.sh` | Runs the full install flow |
| `inventory/targets.csv` | Source inventory for monitored hosts |
| `scripts/generate_targets.py` | Generates Prometheus target files |
| `config/prometheus.yml` | Prometheus scrape, alert, and remote write config |
| `config/targets/*.yml` | Generated Prometheus file service discovery targets |
| `config/alerts/*.yml` | Prometheus alert rules |
| `alertmanager/alertmanager.yml` | Alertmanager email routing template |
| `grafana/provisioning/` | Grafana datasource and dashboard provisioning |
| `systemd/*.service` | Systemd service files installed by the scripts |
| `docs/deployment_plan.md` | Main single-VM deployment runbook |
| `docs/operator_handover.md` | DB grants, offline package manifest process, firewall, SELinux, validation |
| `docs/offline_package_manifest.example.csv` | Template for approved offline package versions and checksums |
| `docs/dpa_metric_catalog.md` | DPA-style metric coverage for node, Oracle, and MSSQL |
| `docs/alert_catalog.md` | Default alert thresholds and operational meaning |

## Deployment From Zero

Target OS used by the scripts: Oracle Linux 8 or another RHEL-compatible Linux with `dnf` or `yum`.

Run all commands from the repository root unless stated otherwise.

Before handover or production deployment, review the detailed operator guide:

```text
docs/deployment_plan.md
docs/operator_handover.md
docs/dpa_metric_catalog.md
docs/alert_catalog.md
```

### 1. Prepare Offline Packages

Put the installer files on the target VM before running `deploy_all.sh`.

Expected location:

```bash
/monitoring/sources/tar/
/monitoring/sources/rpm/
```

Expected file patterns:

```text
/monitoring/sources/tar/prometheus-*.linux-amd64.tar.gz
/monitoring/sources/tar/victoria-metrics-linux-amd64-*.tar.gz
/monitoring/sources/tar/alertmanager-*.linux-amd64.tar.gz
/monitoring/sources/tar/node_exporter*.tar.gz
/monitoring/sources/tar/oracledb_exporter*.tar.gz
/monitoring/sources/tar/mssql_exporter*.tar.gz
/monitoring/sources/rpm/grafana-*.rpm
```

If `/monitoring` does not exist yet, run only the preparation step first, then upload the packages:

```bash
sudo ./01_prepare_vm.sh
```

Package installation behavior for step 01:

```bash
# Default: install packages only when enabled yum/dnf repositories exist
sudo ./01_prepare_vm.sh

# Offline VM with packages already installed
sudo INSTALL_PACKAGES=skip ./01_prepare_vm.sh

# Force yum/dnf package install
sudo INSTALL_PACKAGES=online ./01_prepare_vm.sh
```

### 2. Edit Inventory

Edit:

```bash
inventory/targets.csv
```

Columns:

```text
host,ip,node,oracle,mssql,app,tier,owner
```

Use `yes` or `no` for `node`, `oracle`, and `mssql`.

### 3. Generate Prometheus Targets

Run:

```bash
python3 scripts/generate_targets.py
```

Generated files:

```text
config/targets/node_targets.yml
config/targets/oracle_targets.yml
config/targets/mssql_targets.yml
```

Review the generated ports:

| Service | Port |
| --- | --- |
| Node exporter | `9100` |
| Oracle exporter | `9161` |
| MSSQL exporter | `9182` |

### 4. Run Deployment

Run:

```bash
sudo ./deploy_all.sh
```

The script checks generated target files, installs core services, copies configs and dashboards, enables systemd services, and runs `09_health_check.sh`.

If you need to run the installer step by step, use this order:

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

This order is intentionally dependency-first, so the script numbers are not strictly sequential. Alertmanager is installed before Prometheus so the alerting endpoint is already available when Prometheus starts. Grafana is installed after VictoriaMetrics and Prometheus because its datasource and dashboards depend on them.

Oracle and MSSQL exporter installers only create/enable the services and credential templates. Start them after the database users and `DATA_SOURCE_NAME` values are correct.

VictoriaMetrics tuning defaults are installed from:

```text
config/victoriametrics/victoriametrics.env.example
```

On the server, tune retention, memory budget, disk free-space guardrail, and query limits here:

```bash
sudo vi /monitoring/victoriametrics/conf/victoriametrics.env
sudo systemctl restart victoriametrics
```

Prometheus runtime tuning defaults are installed from:

```text
config/prometheus/prometheus.env.example
```

On the server, tune local retention, local disk cap, query limits, and remote-write flush deadline here:

```bash
sudo vi /monitoring/prometheus/conf/prometheus.env
sudo systemctl restart prometheus
```

Alertmanager runtime tuning defaults are installed from:

```text
config/alertmanager/alertmanager.env.example
```

On the server, tune listen address, external URL, notification retention, and single-node cluster behavior here:

```bash
sudo vi /monitoring/alertmanager/conf/alertmanager.env
sudo systemctl restart alertmanager
```

Node exporter runtime tuning defaults are installed from:

```text
config/node_exporter/node_exporter.env.example
```

On the server, tune listen address, max scrape requests, log level, and filesystem exclude patterns here:

```bash
sudo vi /monitoring/exporters/node/node_exporter.env
sudo systemctl restart node_exporter
```

Grafana runtime tuning defaults are installed from:

```text
config/grafana/grafana.env.example
```

On the server, tune public URL, sign-up policy, metrics endpoint, and query concurrency here:

```bash
sudo vi /monitoring/grafana/conf/grafana.env
sudo systemctl restart grafana-server
```

### 5. Configure Database Exporter Credentials

The Oracle and MSSQL exporter installers create template credential files on the server. Edit them before starting the DB exporters:

```bash
sudo vi /monitoring/exporters/oracle/oracle_exporter.env
sudo vi /monitoring/exporters/mssql/mssql_exporter.env
```

Then start:

```bash
sudo systemctl restart oracle_exporter
sudo systemctl restart mssql_exporter
```

Oracle and MSSQL exporter env files also include listen-address tuning values. Keep the default ports unless the Prometheus target files are updated too.

### 6. Configure Alert Email

Edit SMTP settings:

```bash
sudo vi /monitoring/alertmanager/conf/alertmanager.yml
sudo systemctl restart alertmanager
```

Replace the `CHANGE_ME` SMTP password and company placeholders before relying on email alerts.

Default routing sends critical alerts faster and repeats them more often than warnings. Tune `group_wait`, `group_interval`, `repeat_interval`, receivers, and inhibition rules in `/monitoring/alertmanager/conf/alertmanager.yml`.

### 7. Open Required Firewall Ports

Allow access from operators or from Prometheus to exporter nodes:

| Component | Port |
| --- | --- |
| Grafana | `3000` |
| Prometheus | `9090` |
| Alertmanager | `9093` |
| VictoriaMetrics | `8428` |
| Node exporter | `9100` |
| Oracle exporter | `9161` |
| MSSQL exporter | `9182` |

For Oracle Linux 8 `firewalld`, SELinux checks, and single VM vs 3 VM placement, see:

```text
docs/operator_handover.md
docs/deployment_plan_expand.md
```

### 8. Validate

Check services:

```bash
sudo ./09_health_check.sh
```

Result meaning:

| Result | Meaning |
| --- | --- |
| `PASSED` | Core services, endpoints, rules, and remote-write checks passed |
| `PASSED WITH WARNINGS` | Core platform is running, but optional checks need follow-up, usually Oracle/MSSQL credentials are still placeholders |
| `FAILED` | At least one required platform service, endpoint, config, or rule check failed |

Open:

```text
http://VM_IP:9090/targets
http://VM_IP:9090/alerts
http://VM_IP:8428
http://VM_IP:3000
http://VM_IP:9093
```

Default Grafana login after RPM install is usually:

```text
admin / admin
```

Change the password on first login.

## Common Troubleshooting

Prometheus config:

```bash
sudo /monitoring/prometheus/bin/promtool check config /monitoring/prometheus/conf/prometheus.yml
```

Service logs:

```bash
sudo journalctl -u prometheus -f
sudo journalctl -u victoriametrics -f
sudo journalctl -u grafana-server -f
sudo journalctl -u alertmanager -f
sudo journalctl -u oracle_exporter -f
sudo journalctl -u mssql_exporter -f
```

Exporter endpoint checks:

```bash
curl http://localhost:9100/metrics
curl http://localhost:9161/metrics
curl http://localhost:9182/metrics
```

Detailed Prometheus and VictoriaMetrics validation queries are in:

```text
docs/operator_handover.md
```

## Notes For Operators

- Run the repository scripts from the repo root because they copy relative paths such as `./config`, `./grafana`, and `./systemd`.
- Prometheus keeps only short local retention (`1d`) and writes long-term data to VictoriaMetrics.
- Grafana datasource is provisioned to `http://localhost:8428`, so Prometheus `remote_write` must stay enabled.
- Grafana datasource UID is provisioned as `Prometheus` for dashboard compatibility.
- Database exporters are installed with template credentials. They should only be started after `DATA_SOURCE_NAME` is correct.
- DB user grants, offline checksum process, firewall commands, and metric validation are documented in `docs/operator_handover.md`.
