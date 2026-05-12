<div align="center">

<img src="images/platform-architecture.svg" alt="Internal Database Observability Platform architecture" width="100%">

<h1>Deployment Guide</h1>

<p><strong>Runbook teknis premium untuk instalasi, tuning, validasi, dan handover Internal Database Observability Platform.</strong></p>

<img src="https://img.shields.io/badge/Target-Oracle%20Linux%208%20%7C%20RHEL-2563EB?style=for-the-badge&logo=linux&logoColor=white" alt="Target OS">
<img src="https://img.shields.io/badge/Mode-Offline%20Ready-16A34A?style=for-the-badge&logo=files&logoColor=white" alt="Offline ready">
<img src="https://img.shields.io/badge/Install-Single%20VM-F97316?style=for-the-badge&logo=serverfault&logoColor=white" alt="Single VM">
<img src="https://img.shields.io/badge/Expansion-3%20VM-7C3AED?style=for-the-badge&logo=databricks&logoColor=white" alt="3 VM expansion">

</div>

## 1. Peta Cepat

| Bagian | Tujuan |
| --- | --- |
| [2. Target Architecture](#2-target-architecture) | Komponen, port, dan alur data |
| [3. VM Requirement](#3-vm-requirement) | Sizing awal dan package OS |
| [4. Prepare Offline Packages](#4-prepare-offline-packages) | Layout binary, RPM, dan checksum |
| [5. Configure Inventory](#5-configure-inventory) | Inventory target dan generator Prometheus `file_sd` |
| [6. Deploy All Components](#6-deploy-all-components) | Deployment otomatis dari repo root |
| [7. Manual Step-By-Step Deployment](#7-manual-step-by-step-deployment) | Urutan install manual untuk troubleshooting |
| [8. Configure Database Exporters](#8-configure-database-exporters) | Credential Oracle dan MSSQL exporter |
| [9. Runtime Tuning](#9-runtime-tuning) | Tuning Prometheus, VictoriaMetrics, Grafana, Alertmanager, exporters |
| [10. Firewall And SELinux](#10-firewall-and-selinux) | Port, connectivity, dan SELinux checks |
| [11. Validate Deployment](#11-validate-deployment) | Health check, targets, rules, remote-write |
| [12. Troubleshooting](#12-troubleshooting) | Log, config check, endpoint check |
| [13. Final Checklist](#13-final-checklist) | Checklist sebelum handover |

## 2. Target Architecture

Single VM deployment memasang komponen berikut:

| Komponen | Fungsi | Port |
| --- | --- | --- |
| VictoriaMetrics | Long-retention metrics storage | `8428` |
| Alertmanager | Alert routing dan email notification | `9093` |
| Prometheus | Scrape, service discovery, rules, remote write | `9090` |
| Node exporter | OS dan server metrics | `9100` |
| Oracle exporter | Oracle DB metrics | `9161` |
| MSSQL exporter | SQL Server metrics | `9182` |
| PostgreSQL DPA Repository | Historical SQL/plan/mini-ASH drilldown | `5432` local |
| DPA sampler | Oracle diagnostic sampler via systemd timer | n/a |
| Grafana | Dashboard dan visualisasi | `3000` |

Data flow:

```text
Node/Oracle/MSSQL exporters -> Prometheus -> VictoriaMetrics -> Grafana
                                      |
                                      v
                                Alertmanager

Oracle target DB -> DPA sampler -> PostgreSQL DPA Repository -> Grafana
```

Untuk ekspansi 3 VM, gunakan [deployment_guide_expand.md](deployment_guide_expand.md). Untuk handover operasional tambahan, gunakan [operator_handover.md](operator_handover.md).

## 3. VM Requirement

Recommended starter sizing:

| Resource | Minimum starter value |
| --- | --- |
| OS | Oracle Linux 8 atau RHEL-compatible Linux |
| CPU | 4 cores |
| RAM | 8-16 GB |
| Disk | Minimum 100 GB, lebih besar untuk long retention |
| Runtime | `systemd`, `dnf` atau `yum`, local root/sudo access |

Expected base packages:

```text
tar gzip unzip curl wget vim net-tools lsof chrony python3 firewalld policycoreutils policycoreutils-python-utils
```

## 4. Prepare Offline Packages

Upload approved packages ke:

```text
/monitoring/sources/tar
/monitoring/sources/rpm
/monitoring/sources/python
/monitoring/sources/checksum
```

Expected file patterns:

| Komponen | File pattern | Target directory |
| --- | --- | --- |
| Prometheus | `prometheus-*.linux-amd64.tar.gz` | `/monitoring/sources/tar` |
| VictoriaMetrics | `victoria-metrics-linux-amd64-*.tar.gz` | `/monitoring/sources/tar` |
| Alertmanager | `alertmanager-*.linux-amd64.tar.gz` | `/monitoring/sources/tar` |
| Node exporter | `node_exporter*.tar.gz` | `/monitoring/sources/tar` |
| Oracle exporter | `oracledb_exporter*.tar.gz` | `/monitoring/sources/tar` |
| MSSQL exporter | `mssql_exporter*.tar.gz` | `/monitoring/sources/tar` |
| Grafana | `grafana-*.rpm` | `/monitoring/sources/rpm` |
| PostgreSQL server | `postgresql*.rpm` atau OS repo package | `/monitoring/sources/rpm` |
| DPA Python wheels | `oracledb*.whl`, `psycopg2*.whl` | `/monitoring/sources/python` |

Jika `/monitoring` belum ada, copy repo ke VM dan jalankan preparation step:

```bash
sudo ./01_prepare_vm.sh
```

Lalu upload packages dan verify checksums:

```bash
cd /monitoring/sources
sha256sum -c checksum/SHA256SUMS
```

Behavior `01_prepare_vm.sh`:

```bash
# Default: install package hanya jika repo yum/dnf tersedia
sudo ./01_prepare_vm.sh

# Offline VM dengan OS packages sudah disiapkan
sudo INSTALL_PACKAGES=skip ./01_prepare_vm.sh

# Online VM atau internal repository yang sudah approved
sudo INSTALL_PACKAGES=online ./01_prepare_vm.sh
```

Isi manifest package sebelum handover:

```text
docs/offline_package_manifest.example.csv
```

## 5. Configure Inventory

Edit source inventory:

```bash
vi inventory/targets.csv
```

Required columns:

```text
host,ip,node,oracle,oracle_dpa,oracle_service,mssql,app,tier,owner
```

Gunakan `yes` atau `no` untuk kolom `node`, `oracle`, `oracle_dpa`, dan `mssql`.

`oracle_dpa=yes` berarti database itu tetap dimonitor oleh exporter Prometheus, plus dibuatkan template env untuk deep DPA sampler. `oracle_service` dipakai untuk template `DPA_ORACLE_DSN`; isi dengan service name Oracle target.

Generate Prometheus `file_sd` target files:

```bash
python3 scripts/generate_targets.py
```

Generated files:

```text
config/targets/node_targets.yml
config/targets/oracle_targets.yml
config/targets/mssql_targets.yml
config/dpa/targets/*.env.example
```

Review generated target ports:

| Target type | Port |
| --- | --- |
| Node | `9100` |
| Oracle | `9161` |
| MSSQL | `9182` |

Untuk target dengan `oracle_dpa=yes`, copy template env ke VM setelah install DPA repository:

```bash
sudo scripts/install_dpa_target.sh <target>
sudo vi /monitoring/dpa/conf/<target>.env
sudo systemctl enable --now dpa_sampler@<target>.timer
```

## 6. Deploy All Components

Run dari repository root:

```bash
sudo ./deploy_all.sh
```

Deployment script menjalankan urutan:

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
10_install_postgres_dpa.sh
09_health_check.sh
```

Urutan ini dependency-first. Alertmanager diinstall sebelum Prometheus supaya alerting endpoint sudah tersedia ketika Prometheus start. Grafana diinstall setelah VictoriaMetrics dan Prometheus karena datasource dan dashboard provisioning bergantung pada keduanya. PostgreSQL DPA repository diinstall setelah Grafana supaya installer dapat menyuntikkan password `dpa_reader` ke runtime env Grafana dan restart Grafana.

Oracle dan MSSQL exporter installer membuat service file dan credential template, tetapi tidak start exporter selama `DATA_SOURCE_NAME` masih berisi placeholder `CHANGE_ME`.

## 7. Manual Step-By-Step Deployment

Gunakan mode ini untuk troubleshooting atau install komponen satu per satu:

```bash
sudo ./01_prepare_vm.sh
sudo ./02_install_victoriametrics.sh
sudo ./06_install_alertmanager.sh
sudo ./03_install_prometheus.sh
sudo ./04_install_node_exporter.sh
sudo ./07_install_oracle_exporter.sh
sudo ./08_install_mssql_exporter.sh
sudo ./05_install_grafana.sh
sudo ./10_install_postgres_dpa.sh
sudo ./09_health_check.sh
```

Node exporter start langsung karena tidak membutuhkan database credential. Oracle dan MSSQL exporters hanya start otomatis jika connection string sudah benar.

`10_install_postgres_dpa.sh` membuat PostgreSQL local repository, user `dpa_app`, user `dpa_reader`, schema `dpa`, datasource Grafana `DPA Repository`, dan templated systemd timer `dpa_sampler@<target>.timer`. Timer tidak dipaksa start selama file env target di `/monitoring/dpa/conf/<target>.env` masih berisi placeholder Oracle `CHANGE_ME`.

## 8. Configure Database Exporters

Buat DB monitoring users dan grants terlebih dahulu. Sesuaikan password, profile, tablespace, dan login policy dengan standar organisasi.

### Oracle Monitoring User Grants

Run sebagai DBA privileged user.

```sql
CREATE USER monitoring_user IDENTIFIED BY "CHANGE_ME_STRONG_PASSWORD";
GRANT CREATE SESSION TO monitoring_user;

GRANT SELECT ON sys.v_$session TO monitoring_user;
GRANT SELECT ON sys.v_$resource_limit TO monitoring_user;
GRANT SELECT ON sys.v_$sysmetric TO monitoring_user;
GRANT SELECT ON sys.v_$sysstat TO monitoring_user;
GRANT SELECT ON sys.v_$sql TO monitoring_user;
GRANT SELECT ON sys.v_$sqlarea TO monitoring_user;
GRANT SELECT ON sys.v_$sql_plan TO monitoring_user;
GRANT SELECT ON sys.v_$database TO monitoring_user;
GRANT SELECT ON sys.v_$instance TO monitoring_user;
GRANT SELECT ON sys.v_$containers TO monitoring_user;
GRANT SELECT ON sys.v_$segment_statistics TO monitoring_user;
GRANT SELECT ON sys.v_$rman_backup_job_details TO monitoring_user;
GRANT SELECT ON sys.v_$dataguard_stats TO monitoring_user;
GRANT SELECT ON sys.dba_objects TO monitoring_user;
GRANT SELECT ON sys.dba_indexes TO monitoring_user;
GRANT SELECT ON sys.dba_tab_statistics TO monitoring_user;
GRANT SELECT ON sys.dba_scheduler_job_run_details TO monitoring_user;

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

Untuk multitenant deployment, buat user di PDB yang dimonitor kecuali DBA team memang memilih common user. Jika ASM metrics tidak diperlukan atau user tidak boleh membaca ASM views, comment metric block ASM di:

```text
/monitoring/exporters/oracle/oracle-metrics.toml
```

Tambahan `v_$sql_plan`, `v_$segment_statistics`, `v_$rman_backup_job_details`, `v_$dataguard_stats`, `dba_objects`, `dba_indexes`, `dba_tab_statistics`, dan `dba_scheduler_job_run_details` dipakai oleh DPA repository sampler untuk plan history, hot object signals, Data Guard, backup age, failed jobs, invalid objects, stale stats, unusable indexes, dan change correlation. Jika grant tersebut tidak diizinkan, set modul opsional ini ke `false` di file env target.

### Oracle DPA Repository Sampler

Edit credential:

```bash
sudo vi /monitoring/dpa/conf/oracle-default.env
```

Minimum:

```bash
DPA_ORACLE_USER=monitoring_user
DPA_ORACLE_PASSWORD=CHANGE_ME_STRONG_PASSWORD
DPA_ORACLE_DSN=db-host:1521/service_name
DPA_DB_UNIQUE_NAME=oracle-prod-01
```

Optional controls:

```bash
DPA_SQL_TOP_N=50
DPA_PLAN_TOP_N=20
DPA_RETENTION_DAYS=35
DPA_ENABLE_PLAN_SNAPSHOT=true
DPA_ENABLE_OBJECT_STATS=true
DPA_ENABLE_CHANGE_EVENTS=true
DPA_ENABLE_ORACLE_OPS=true
DPA_ENABLE_ADVISORY=true
```

Start and validate:

```bash
sudo systemctl restart dpa_sampler@oracle-default.timer
sudo systemctl start dpa_sampler@oracle-default.service
sudo journalctl -u dpa_sampler@oracle-default.service -n 100 --no-pager
sudo runuser -u postgres -- psql -d dpa_repository -c "SELECT count(*) FROM dpa.ash_sample;"
```

For another Oracle target:

```bash
sudo cp /monitoring/dpa/conf/oracle-default.env /monitoring/dpa/conf/oracle-prod-02.env
sudo vi /monitoring/dpa/conf/oracle-prod-02.env
sudo systemctl enable --now dpa_sampler@oracle-prod-02.timer
```

Grafana dashboard:

```text
Oracle / 07 - Oracle DPA Repository
```

### MSSQL Monitoring User Grants

Run sebagai SQL Server administrator.

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

Untuk environment yang lebih ketat, mulai dari `VIEW SERVER STATE`, test exporter, lalu tambahkan permission hanya untuk query metrik yang gagal.

### Oracle Exporter

Edit credential:

```bash
sudo vi /monitoring/exporters/oracle/oracle_exporter.env
```

Example:

```bash
DATA_SOURCE_NAME=oracle://monitoring_user:CHANGE_ME_STRONG_PASSWORD@db-host:1521/service_name
```

URL-escape karakter khusus di password, terutama `@`, `/`, `:`, `#`, dan `%`.

Restart dan validasi:

```bash
sudo systemctl restart oracle_exporter
sudo systemctl status oracle_exporter --no-pager
curl http://localhost:9161/metrics | grep '^oracle_up'
```

### MSSQL Exporter

Edit credential:

```bash
sudo vi /monitoring/exporters/mssql/mssql_exporter.env
```

Example:

```bash
DATA_SOURCE_NAME=sqlserver://monitoring_user:CHANGE_ME_STRONG_PASSWORD@mssql-host:1433?database=master&encrypt=disable
```

Gunakan `encrypt=true` atau standar organisasi jika SQL Server membutuhkan TLS.

Restart dan validasi:

```bash
sudo systemctl restart mssql_exporter
sudo systemctl status mssql_exporter --no-pager
curl http://localhost:9182/metrics | grep '^mssql_up'
```

## 9. Runtime Tuning

### VictoriaMetrics

Default tuning source:

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

### Prometheus

Prometheus menyimpan short local retention dan mengirim long-term data ke VictoriaMetrics melalui `remote_write`.

Default tuning source:

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

Remote-write queue tuning ada di:

```text
config/prometheus.yml
```

### Grafana

Default tuning source:

```text
config/grafana/grafana.env.example
```

Runtime path:

```text
/monitoring/grafana/conf/grafana.env
```

Common settings:

| Setting | Purpose |
| --- | --- |
| `GF_SERVER_ROOT_URL` | Public URL used in links |
| `GF_USERS_ALLOW_SIGN_UP` | Disable self sign-up |
| `GF_AUTH_ANONYMOUS_ENABLED` | Disable anonymous access |
| `GF_METRICS_ENABLED` | Enable `/metrics` for Prometheus self-monitoring |
| `GF_DASHBOARDS_MIN_REFRESH_INTERVAL` | Prevent overly aggressive dashboard refresh |
| `GF_QUERY_CONCURRENT_QUERY_LIMIT` | Bound concurrent dashboard queries |

Datasource provisioning:

| Field | Value |
| --- | --- |
| Name | `Prometheus` |
| UID | `Prometheus` |
| URL | `http://localhost:8428` |

Validate:

```bash
sudo systemctl restart grafana-server
curl -fsS http://localhost:3000/api/health
curl -fsS http://localhost:3000/metrics
```

Default Grafana login setelah RPM install biasanya:

```text
admin / admin
```

Ganti password pada first login.

### Alertmanager

Edit SMTP dan routing:

```bash
sudo vi /monitoring/alertmanager/conf/alertmanager.yml
```

Runtime tuning source:

```text
config/alertmanager/alertmanager.env.example
```

Runtime path:

```text
/monitoring/alertmanager/conf/alertmanager.env
```

Common settings:

| Setting | Purpose |
| --- | --- |
| `AM_WEB_LISTEN_ADDRESS` | Alertmanager listen address |
| `AM_WEB_EXTERNAL_URL` | URL used in generated links |
| `AM_DATA_RETENTION` | Notification log and silence retention |
| `AM_ALERTS_GC_INTERVAL` | Alert garbage collection interval |
| `AM_CLUSTER_LISTEN_ADDRESS` | Cluster gossip listen address; blank disables clustering for single VM |
| `AM_LOG_LEVEL` | Runtime log level |

Default notification routing:

| Severity | Initial wait | Group interval | Repeat |
| --- | --- | --- | --- |
| `critical` | `10s` | `2m` | `1h` |
| `warning` | `2m` | `10m` | `6h` |

Validate:

```bash
/monitoring/alertmanager/bin/amtool check-config /monitoring/alertmanager/conf/alertmanager.yml
sudo systemctl restart alertmanager
curl -fsS http://localhost:9093/-/ready
curl -fsS http://localhost:9093/api/v2/status
```

Replace semua `CHANGE_ME` value dan placeholder company sebelum mengandalkan email alerts.

### Exporters

Node exporter default tuning source:

```text
config/node_exporter/node_exporter.env.example
```

Runtime path:

```text
/monitoring/exporters/node/node_exporter.env
```

Common node exporter settings:

| Setting | Purpose |
| --- | --- |
| `NODE_EXPORTER_WEB_LISTEN_ADDRESS` | Node exporter listen address |
| `NODE_EXPORTER_WEB_MAX_REQUESTS` | Maximum concurrent scrape requests |
| `NODE_EXPORTER_LOG_LEVEL` | Runtime log level |
| `NODE_EXPORTER_FILESYSTEM_MOUNT_POINTS_EXCLUDE` | Exclude noisy pseudo/container mounts |
| `NODE_EXPORTER_FILESYSTEM_FS_TYPES_EXCLUDE` | Exclude pseudo filesystem types |

Oracle exporter runtime path:

```text
/monitoring/exporters/oracle/oracle_exporter.env
```

MSSQL exporter runtime path:

```text
/monitoring/exporters/mssql/mssql_exporter.env
```

Apply exporter changes:

```bash
sudo systemctl restart node_exporter
sudo systemctl restart oracle_exporter
sudo systemctl restart mssql_exporter
```

## 10. Firewall And SELinux

### Single VM Control Plane Ports

Run pada monitoring VM:

```bash
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=9090/tcp
sudo firewall-cmd --permanent --add-port=9093/tcp
sudo firewall-cmd --permanent --add-port=8428/tcp
sudo firewall-cmd --reload
```

### Exporter Host Ports

Run pada setiap exporter host sesuai kebutuhan:

```bash
sudo firewall-cmd --permanent --add-port=9100/tcp
sudo firewall-cmd --permanent --add-port=9161/tcp
sudo firewall-cmd --permanent --add-port=9182/tcp
sudo firewall-cmd --reload
```

### Database Connectivity

Pastikan exporter host bisa reach database listener:

```bash
nc -vz ORACLE_DB_HOST 1521
nc -vz MSSQL_DB_HOST 1433
```

Jika `nc` tidak tersedia:

```bash
timeout 5 bash -c '</dev/tcp/ORACLE_DB_HOST/1521'
timeout 5 bash -c '</dev/tcp/MSSQL_DB_HOST/1433'
```

### SELinux

Keep SELinux enforcing jika memungkinkan. Check status:

```bash
getenforce
sestatus
```

Jika service gagal dan log menampilkan `permission denied`, check audit logs:

```bash
sudo ausearch -m avc -ts recent
sudo journalctl -u prometheus -n 100 --no-pager
sudo journalctl -u oracle_exporter -n 100 --no-pager
sudo journalctl -u mssql_exporter -n 100 --no-pager
```

Diagnostic sementara:

```bash
sudo setenforce 0
```

Jika issue hilang saat permissive mode, buat policy SELinux yang benar dengan Linux security team, bukan meninggalkan SELinux disabled.

## 11. Validate Deployment

Run health check:

```bash
sudo ./09_health_check.sh
```

Result meaning:

| Result | Meaning |
| --- | --- |
| `PASSED` | Core services, endpoints, rules, dan remote-write checks passed |
| `PASSED WITH WARNINGS` | Core platform running, tetapi optional checks butuh follow-up, biasanya Oracle/MSSQL credentials masih placeholder |
| `FAILED` | Ada required platform service, endpoint, config, atau rule check yang gagal |

Open:

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

Prometheus scrape health:

```bash
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=up'
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=up{job="node"}'
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=up{job="oracle"}'
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=up{job="mssql"}'
```

VictoriaMetrics remote-write validation:

```bash
curl -G 'http://localhost:8428/api/v1/query' --data-urlencode 'query=up'
curl -G 'http://localhost:8428/api/v1/query' --data-urlencode 'query=oracle_up'
curl -G 'http://localhost:8428/api/v1/query' --data-urlencode 'query=mssql_up'
```

Expected: results tersedia di VictoriaMetrics beberapa saat setelah Prometheus start.

## 12. Troubleshooting

Service logs:

```bash
sudo journalctl -u prometheus -n 100 --no-pager
sudo journalctl -u victoriametrics -n 100 --no-pager
sudo journalctl -u grafana-server -n 100 --no-pager
sudo journalctl -u alertmanager -n 100 --no-pager
sudo journalctl -u oracle_exporter -n 100 --no-pager
sudo journalctl -u mssql_exporter -n 100 --no-pager
```

Follow logs:

```bash
sudo journalctl -u prometheus -f
sudo journalctl -u victoriametrics -f
sudo journalctl -u grafana-server -f
sudo journalctl -u alertmanager -f
sudo journalctl -u oracle_exporter -f
sudo journalctl -u mssql_exporter -f
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

Exporter endpoint checks:

```bash
curl http://localhost:9100/metrics
curl http://localhost:9161/metrics
curl http://localhost:9182/metrics
```

Prometheus config:

```bash
sudo /monitoring/prometheus/bin/promtool check config /monitoring/prometheus/conf/prometheus.yml
```

Detailed validation queries ada di [operator_handover.md](operator_handover.md).

## 13. Final Checklist

| Status | Item |
| --- | --- |
| `[ ]` | Offline packages dan SHA256 checksums approved |
| `[ ]` | `inventory/targets.csv` reviewed |
| `[ ]` | `config/targets/*.yml` generated |
| `[ ]` | `deploy_all.sh` completed successfully |
| `[ ]` | DB monitoring users created |
| `[ ]` | Oracle dan MSSQL exporter credentials updated |
| `[ ]` | Exporter targets `UP` di Prometheus |
| `[ ]` | Prometheus config dan rules load tanpa error |
| `[ ]` | VictoriaMetrics contains `up`, `oracle_up`, dan `mssql_up` |
| `[ ]` | Grafana datasource healthy |
| `[ ]` | Alertmanager SMTP settings updated dan tested |
| `[ ]` | Handover docs reviewed dengan operator/DBA/NOC |
