# Operator Handover Guide

This guide fills the operational details needed before handing the platform to a new deployer.

## 1. Deployment Topology

Use one of these supported layouts.

### Option A: Single VM

Use this for first deployment, lab, SIT, or small environments.

| Service | Location |
| --- | --- |
| Prometheus | Monitoring VM |
| VictoriaMetrics | Monitoring VM |
| Grafana | Monitoring VM |
| Alertmanager | Monitoring VM |
| Node exporter | Database/server VM or monitoring VM if only testing locally |
| Oracle exporter | Exporter host that can reach Oracle listener |
| MSSQL exporter | Exporter host that can reach SQL Server listener |

The current `deploy_all.sh` path installs services on one VM. If exporters are installed on the monitoring VM but databases are remote, the exporter `DATA_SOURCE_NAME` must point to the database host, not `localhost`.

### Option B: 3 VM Expansion

Use this when the platform grows or when storage/exporter workload must be separated.

| VM | Role | Services |
| --- | --- | --- |
| VM1 | Control plane | Prometheus, Grafana, Alertmanager |
| VM2 | Metrics storage | VictoriaMetrics |
| VM3 | Exporter node | Oracle, MSSQL, Node exporters |

Follow [deployment_plan_expand.md](deployment_plan_expand.md) for this layout. In this mode, Prometheus `remote_write` must point to VM2 and Prometheus target files must point to exporter ports on VM3.

## 2. Offline Package Manifest

Because this platform is designed to work offline, every binary/RPM should be pinned and checksummed before the deployment window.

Recommended policy:

- Use one approved version set per environment.
- Store package files under `/monitoring/sources/tar` and `/monitoring/sources/rpm`.
- Store SHA256 checksums under `/monitoring/sources/checksum`.
- Do not replace package files during a deployment without updating the manifest and checksum file.
- On offline VMs, install base OS packages from the approved internal repository/media first, or run `INSTALL_PACKAGES=skip ./01_prepare_vm.sh` after verifying prerequisites.

Base OS packages expected by the installer flow:

```text
tar gzip unzip curl wget vim net-tools lsof chrony python3 firewalld policycoreutils policycoreutils-python-utils
```

Expected files:

| Component | Expected file pattern | Target directory |
| --- | --- | --- |
| Prometheus | `prometheus-*.linux-amd64.tar.gz` | `/monitoring/sources/tar` |
| VictoriaMetrics | `victoria-metrics-linux-amd64-*.tar.gz` | `/monitoring/sources/tar` |
| Alertmanager | `alertmanager-*.linux-amd64.tar.gz` | `/monitoring/sources/tar` |
| Node exporter | `node_exporter*.tar.gz` | `/monitoring/sources/tar` |
| Oracle exporter | `oracledb_exporter*.tar.gz` | `/monitoring/sources/tar` |
| MSSQL exporter | `mssql_exporter*.tar.gz` | `/monitoring/sources/tar` |
| Grafana | `grafana-*.rpm` | `/monitoring/sources/rpm` |

Create checksums on the staging machine:

```bash
cd /monitoring/sources
sha256sum tar/*.tar.gz rpm/*.rpm > checksum/SHA256SUMS
```

Verify checksums on the target VM before install:

```bash
cd /monitoring/sources
sha256sum -c checksum/SHA256SUMS
```

Fill the package manifest before handover:

```text
docs/offline_package_manifest.example.csv
```

## 3. VictoriaMetrics Tuning

The installer deploys single-node VictoriaMetrics with conservative defaults from:

```text
config/victoriametrics/victoriametrics.env.example
```

Installed path:

```text
/monitoring/victoriametrics/conf/victoriametrics.env
```

Default tuning:

| Setting | Default | Purpose |
| --- | --- | --- |
| `VM_RETENTION_PERIOD` | `90d` | Long-term metrics retention |
| `VM_MEMORY_ALLOWED_PERCENT` | `60` | Internal cache memory budget |
| `VM_MIN_FREE_DISK_SPACE` | `10GB` | Stop ingestion before disk is full |
| `VM_SEARCH_MAX_QUERY_DURATION` | `2m` | Cancel unexpectedly heavy queries |
| `VM_SEARCH_MAX_CONCURRENT_REQUESTS` | `16` | Bound concurrent query memory usage |
| `VM_SEARCH_MAX_QUEUE_DURATION` | `30s` | Bound queued query wait time |

After changing tuning:

```bash
sudo systemctl restart victoriametrics
curl -fsS http://localhost:8428/health
curl -fsS http://localhost:8428/metrics | grep '^vm_'
```

Watch these during the first production week:

```bash
df -h /monitoring/data/victoriametrics
journalctl -u victoriametrics -n 100 --no-pager
curl -G 'http://localhost:8428/api/v1/query' --data-urlencode 'query=up'
```

Prometheus also scrapes VictoriaMetrics itself with `job="victoriametrics"` so storage availability, ignored rows, and cache saturation can alert.

## 4. Oracle Monitoring User

Run the following as a privileged DBA user. Adjust password, profile, and tablespace standards to match local policy.

### Non-CDB or PDB User

```sql
CREATE USER monitoring_user IDENTIFIED BY "CHANGE_ME_STRONG_PASSWORD";
GRANT CREATE SESSION TO monitoring_user;

GRANT SELECT ON sys.v_$session TO monitoring_user;
GRANT SELECT ON sys.v_$resource_limit TO monitoring_user;
GRANT SELECT ON sys.v_$sysmetric TO monitoring_user;
GRANT SELECT ON sys.v_$sysstat TO monitoring_user;
GRANT SELECT ON sys.v_$sql TO monitoring_user;
GRANT SELECT ON sys.v_$sqlarea TO monitoring_user;

GRANT SELECT ON sys.dba_data_files TO monitoring_user;
GRANT SELECT ON sys.dba_free_space TO monitoring_user;
GRANT SELECT ON sys.dba_tablespaces TO monitoring_user;
GRANT SELECT ON sys.dba_temp_files TO monitoring_user;
GRANT SELECT ON sys.v_$temp_space_header TO monitoring_user;

GRANT SELECT ON sys.v_$flash_recovery_area_usage TO monitoring_user;
GRANT SELECT ON sys.v_$recovery_file_dest TO monitoring_user;

GRANT SELECT ON sys.gv_$instance TO monitoring_user;
GRANT SELECT ON sys.gv_$session TO monitoring_user;
GRANT SELECT ON sys.gv_$active_services TO monitoring_user;

GRANT SELECT ON sys.v_$asm_diskgroup TO monitoring_user;
GRANT SELECT ON sys.v_$asm_operation TO monitoring_user;
```

### CDB Note

For multitenant deployments, create the user in the PDB that will be monitored unless the DBA team intentionally wants a common user. If using a common user, follow the local naming standard such as `C##MONITORING_USER` and grant privileges in the required containers.

### Oracle Connection String

Edit:

```bash
/monitoring/exporters/oracle/oracle_exporter.env
```

Example:

```bash
DATA_SOURCE_NAME=monitoring_user/CHANGE_ME_STRONG_PASSWORD@//db-host:1521/service_name
```

Validate:

```bash
systemctl restart oracle_exporter
curl http://localhost:9161/metrics | grep '^oracle_up'
```

If ASM metrics are not required or the database user cannot access ASM views, remove or comment the ASM metric blocks in `/monitoring/exporters/oracle/oracle-metrics.toml`.

## 5. MSSQL Monitoring User

Run the following as a SQL Server administrator. Adjust password and login policy to match local standards.

```sql
USE [master];
GO

CREATE LOGIN [monitoring_user]
WITH PASSWORD = 'CHANGE_ME_STRONG_PASSWORD',
CHECK_POLICY = ON,
CHECK_EXPIRATION = OFF;
GO

CREATE USER [monitoring_user] FOR LOGIN [monitoring_user];
GO

GRANT VIEW SERVER STATE TO [monitoring_user];
GRANT VIEW ANY DATABASE TO [monitoring_user];
GO

USE [msdb];
GO

CREATE USER [monitoring_user] FOR LOGIN [monitoring_user];
GRANT SELECT ON dbo.backupset TO [monitoring_user];
GO
```

For stricter environments, start with `VIEW SERVER STATE`, test the exporter, then add only the permissions needed by failed metric queries.

Edit:

```bash
/monitoring/exporters/mssql/mssql_exporter.env
```

Example:

```bash
DATA_SOURCE_NAME=sqlserver://monitoring_user:CHANGE_ME_STRONG_PASSWORD@mssql-host:1433?database=master&encrypt=disable
```

Validate:

```bash
systemctl restart mssql_exporter
curl http://localhost:9182/metrics | grep '^mssql_up'
```

Use `encrypt=true` or the organization standard if SQL Server requires TLS.

## 6. Oracle Linux 8 Firewall And SELinux

### Single VM Control Plane Ports

Run on the monitoring VM:

```bash
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=9090/tcp
sudo firewall-cmd --permanent --add-port=9093/tcp
sudo firewall-cmd --permanent --add-port=8428/tcp
sudo firewall-cmd --reload
```

### Exporter Host Ports

Run on each exporter host as needed:

```bash
sudo firewall-cmd --permanent --add-port=9100/tcp
sudo firewall-cmd --permanent --add-port=9161/tcp
sudo firewall-cmd --permanent --add-port=9182/tcp
sudo firewall-cmd --reload
```

### Database Connectivity

Ensure the exporter host can reach the database listener:

```bash
nc -vz ORACLE_DB_HOST 1521
nc -vz MSSQL_DB_HOST 1433
```

If `nc` is not installed:

```bash
timeout 5 bash -c '</dev/tcp/ORACLE_DB_HOST/1521'
timeout 5 bash -c '</dev/tcp/MSSQL_DB_HOST/1433'
```

### SELinux

Keep SELinux enforcing when possible. Check status:

```bash
getenforce
sestatus
```

If a service fails and logs show `permission denied`, check audit logs:

```bash
sudo ausearch -m avc -ts recent
sudo journalctl -u prometheus -n 100 --no-pager
sudo journalctl -u oracle_exporter -n 100 --no-pager
sudo journalctl -u mssql_exporter -n 100 --no-pager
```

For a temporary diagnostic only:

```bash
sudo setenforce 0
```

If the issue disappears in permissive mode, create a proper SELinux policy with the Linux security team instead of leaving SELinux disabled.

## 7. Metric Validation

Run these after deployment and after every inventory change.

### Service Discovery

Prometheus target page:

```text
http://VM_IP:9090/targets
```

Prometheus API:

```bash
curl -s 'http://localhost:9090/api/v1/targets?state=active'
```

Expected: node, oracle, and mssql targets show `health: up` for hosts that are enabled in `inventory/targets.csv`.

### Prometheus Scrape Health

```bash
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=up'
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=up{job="node"}'
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=up{job="oracle"}'
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=up{job="mssql"}'
```

Expected: value `1` means Prometheus can scrape the exporter.

### Rule Validation

```bash
/monitoring/prometheus/bin/promtool check rules /monitoring/prometheus/conf/alerts/*.yml
curl http://localhost:9090/api/v1/rules
curl http://localhost:9090/api/v1/alerts
```

Expected: Prometheus loads all recording rules and alert rules without errors.

### Exporter Database Health

```bash
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=oracle_up'
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=mssql_up'
```

Expected: value `1` means the exporter can connect to the database and run the basic query.

### VictoriaMetrics Remote Write

Because Grafana reads VictoriaMetrics, verify the same data exists there:

```bash
curl -G 'http://localhost:8428/api/v1/query' --data-urlencode 'query=up'
curl -G 'http://localhost:8428/api/v1/query' --data-urlencode 'query=oracle_up'
curl -G 'http://localhost:8428/api/v1/query' --data-urlencode 'query=mssql_up'
```

Expected: results are present in VictoriaMetrics a short time after Prometheus starts.

### Useful Capacity Queries

```text
node_filesystem_avail_bytes{job="node"}
oracle_tablespace_usage_used_percent{job="oracle"}
mssql_database_size_value{job="mssql"}
```

Metric names can differ if exporter versions or custom query naming rules change. If a dashboard panel is empty, confirm the exact metric name from the exporter `/metrics` endpoint first.

## 8. Handover Checklist

- Offline package manifest completed.
- SHA256 checksums verified.
- Inventory file reviewed.
- Target files generated and committed.
- Oracle and MSSQL monitoring users created.
- Exporter `DATA_SOURCE_NAME` files updated.
- Firewall ports opened on monitoring and exporter hosts.
- Prometheus targets are `UP`.
- VictoriaMetrics contains `up`, `oracle_up`, and `mssql_up`.
- Grafana datasource is healthy.
- Alertmanager SMTP settings updated and tested.
