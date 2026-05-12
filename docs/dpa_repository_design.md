# Oracle DPA Repository

This component adds a local PostgreSQL repository for historical database diagnostics that do not belong in Prometheus labels: SQL text, plan rows, mini-ASH session samples, blocking episodes, change events, object hot spots, SLO weights, and generated tuning advisories.

## Architecture

```text
Oracle target DB
  -> dpa_sampler.py
  -> local PostgreSQL database: dpa_repository
  -> Grafana datasource: DPA Repository
  -> dashboard: 07 - Oracle DPA Repository

Oracle target DB
  -> oracle_exporter
  -> Prometheus/VictoriaMetrics
  -> existing Oracle dashboards and alerts
```

Prometheus remains the high-speed metric and alert path. PostgreSQL is the drilldown repository.

## Install Step

Run after Grafana is installed:

```bash
./10_install_postgres_dpa.sh
```

The script installs or initializes PostgreSQL, creates:

| Item | Purpose |
| --- | --- |
| `dpa_repository` | Local PostgreSQL diagnostic database |
| `dpa_app` | Write user for the sampler |
| `dpa_reader` | Read user for Grafana |
| `/monitoring/dpa/conf/dpa_sampler.env` | Oracle and PostgreSQL sampler configuration |
| `dpa_sampler@.service` | One-shot sampler service template per Oracle target |
| `dpa_sampler@.timer` | Runs each target sampler every 60 seconds |

If the VM is offline, put PostgreSQL RPMs in:

```bash
/monitoring/sources/rpm
```

For Python dependencies, put wheels in:

```bash
/monitoring/sources/python
```

Required Python packages:

```text
oracledb
psycopg2-binary
```

The repository file `config/dpa/python-requirements.txt` documents the expected packages.

## Oracle Grants

The sampler reads from dynamic performance views and a few dictionary views. A practical starting point for a dedicated monitoring user:

```sql
CREATE USER monitoring_user IDENTIFIED BY "CHANGE_ME";
GRANT CREATE SESSION TO monitoring_user;
GRANT SELECT_CATALOG_ROLE TO monitoring_user;
GRANT SELECT ON v_$database TO monitoring_user;
GRANT SELECT ON v_$instance TO monitoring_user;
GRANT SELECT ON v_$session TO monitoring_user;
GRANT SELECT ON v_$sql TO monitoring_user;
GRANT SELECT ON v_$sql_plan TO monitoring_user;
GRANT SELECT ON v_$segment_statistics TO monitoring_user;
GRANT SELECT ON dba_objects TO monitoring_user;
```

If security policy does not allow `SELECT_CATALOG_ROLE`, grant only the listed views. Optional sampler modules fail soft for object stats, plan snapshots, and change events when privileges are missing.

## SQL Text Security

The DPA repository stores SQL text in `dpa.sql_snapshot`. In well-bound applications this is usually structural SQL, but applications that concatenate literals can expose sensitive values such as customer IDs, account numbers, email addresses, tokens, or free-form search text.

Before enabling `oracle_dpa=yes` for a database:

| Check | Required action |
| --- | --- |
| SQL text collection approved | Confirm DBA/app/security owner approval |
| Sensitive literal risk reviewed | Check whether the application uses bind variables |
| Repository access restricted | Keep `dpa_reader` limited to Grafana and approved operators |
| Retention approved | Align `DPA_RETENTION_DAYS` with data handling policy |
| Incident export policy defined | Do not paste SQL text with sensitive literals into tickets unless allowed |

If SQL text is not approved, keep the database exporter-only or disable DPA for that target.

Least-privilege split:

| Module | Required grants |
| --- | --- |
| Core mini-ASH | `v_$database`, `gv_$instance`, `gv_$session`, `gv_$sql`, `v_$containers` |
| SQL text and counters | `gv_$sql` |
| Plan history | `gv_$sql_plan`, `gv_$sql` |
| Blocking history | `gv_$session`, `gv_$sql`, `v_$containers` |
| Change correlation | `dba_objects` |
| Hot objects | `v_$segment_statistics` |
| Operational signals | `v_$rman_backup_job_details`, `v_$dataguard_stats`, `dba_indexes`, `dba_tab_statistics`, `dba_scheduler_job_run_details`, `dba_objects` |

Disable optional modules when grants are not approved:

```bash
DPA_ENABLE_PLAN_SNAPSHOT=false
DPA_ENABLE_OBJECT_STATS=false
DPA_ENABLE_CHANGE_EVENTS=false
DPA_ENABLE_ORACLE_OPS=false
```

## Sampler Configuration

Edit the default target env:

```bash
vi /monitoring/dpa/conf/oracle-default.env
```

Minimum required values:

```bash
DPA_ORACLE_USER=monitoring_user
DPA_ORACLE_PASSWORD=your_password
DPA_ORACLE_DSN=db-host:1521/service_name
DPA_DB_UNIQUE_NAME=oracle-prod-01
```

Then start:

```bash
systemctl restart dpa_sampler@oracle-default.timer
systemctl start dpa_sampler@oracle-default.service
journalctl -u dpa_sampler@oracle-default.service -n 100 --no-pager
```

For multiple Oracle targets, create one env file and one timer instance per database:

```bash
cp /monitoring/dpa/conf/oracle-default.env /monitoring/dpa/conf/oracle-prod-02.env
vi /monitoring/dpa/conf/oracle-prod-02.env
systemctl enable --now dpa_sampler@oracle-prod-02.timer
```

Each env must use a unique:

```bash
DPA_DB_UNIQUE_NAME=oracle-prod-02
```

## Repository Tables

| Table or view | Purpose |
| --- | --- |
| `dpa.ash_sample` | Mini-ASH active session samples with `inst_id`, `con_id`, and `pdb_name` |
| `dpa.sql_snapshot` | Top SQL counters and SQL text snapshots with RAC/PDB context |
| `dpa.sql_plan_snapshot` | Execution plan rows for top SQL with RAC/PDB context |
| `dpa.blocking_episode` | Blocking history with blocker/victim SQL ID and RAC/PDB context |
| `dpa.change_event` | DDL/object change correlation |
| `dpa.object_stats_snapshot` | Hot segment/object signals |
| `dpa.oracle_ops_snapshot` | Data Guard, RMAN, scheduler, invalid object, stale stats, unusable index signals |
| `dpa.app_slo` | Application SLO and business weighting |
| `dpa.dpa_advisory` | Generated tuning/advisory queue |
| `dpa.v_sql_impact_1h` | Impact score by SQL/wait/module/service |
| `dpa.v_plan_changes_24h` | SQL IDs with multiple plan hashes |
| `dpa.v_plan_diff_24h` | Text signatures for comparing changed plan operations |
| `dpa.v_wait_seasonal_baseline` | Day/hour wait baseline |
| `dpa.v_repository_table_size` | Repository table size and estimated rows |
| `dpa.v_repository_ingest_rate` | Recent ingest rate by table and database |

## Retention

Default retention is 35 days:

```bash
DPA_RETENTION_DAYS=35
```

The sampler calls:

```sql
SELECT dpa.purge_old_data(35);
```

Increase retention only after sizing PostgreSQL disk usage.

Starter sizing rule of thumb:

| Workload | Suggested starter disk for DPA repository |
| --- | --- |
| 1-3 Oracle DBs, light activity | 20-50 GB |
| 3-10 Oracle DBs, moderate activity | 100-250 GB |
| 10+ Oracle DBs or high active sessions | Start 500 GB and review after 7 days |

Use the dashboard panel **Repository Size and Ingest Rate** or query:

```sql
SELECT * FROM dpa.v_repository_table_size;
SELECT * FROM dpa.v_repository_ingest_rate;
```

If `ash_sample`, `sql_snapshot`, or `sql_plan_snapshot` grows too fast, reduce:

```bash
DPA_RETENTION_DAYS
DPA_SQL_TOP_N
DPA_PLAN_TOP_N
```

For very large deployments, convert the high-volume tables to daily partitions before production cutover:

```text
dpa.ash_sample
dpa.sql_snapshot
dpa.sql_plan_snapshot
dpa.blocking_episode
dpa.oracle_ops_snapshot
```

## SLO and Impact Weighting

Populate `dpa.app_slo` to make impact scoring business-aware:

```sql
INSERT INTO dpa.app_slo (
  app, tier, db_unique_name, target_db_time_ms_per_call, business_weight, owner, notes
)
VALUES (
  'payment-api', 'prod', 'oracle-prod-01', 100, 5, 'payments-team', 'Critical revenue path'
);
```

The `dpa.v_sql_impact_1h` view multiplies active session seconds by `business_weight`.

## Grafana

The installer creates PostgreSQL user `dpa_reader` and injects the generated password into:

```bash
/monitoring/grafana/conf/grafana.env
```

Grafana datasource provisioning:

```text
Name: DPA Repository
UID : DPARepository
Type: PostgreSQL
```

Dashboard:

```text
Oracle / 07 - Oracle DPA Repository
```

Use it for:

- SQL impact ranking
- Advisory queue
- SQL text drilldown
- plan change candidates
- execution plan rows
- recent DDL/change correlation
- hot object signals
- Oracle operational signals: Data Guard lag, RMAN backup age, failed scheduler jobs, invalid objects, stale stats, unusable indexes
- seasonal wait baseline
- application SLO weights

## Validation

```bash
systemctl status postgresql --no-pager
systemctl list-timers 'dpa_sampler@*.timer' --no-pager
systemctl start dpa_sampler@oracle-default.service
journalctl -u dpa_sampler@oracle-default.service -n 100 --no-pager
runuser -u postgres -- psql -d dpa_repository -c "SELECT count(*) FROM dpa.ash_sample;"
```

Grafana should show data after at least one successful sampler run.
