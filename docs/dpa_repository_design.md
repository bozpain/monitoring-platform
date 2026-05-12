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
| `dpa_sampler.service` | One-shot sampler service |
| `dpa_sampler.timer` | Runs sampler every 60 seconds |

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

## Sampler Configuration

Edit:

```bash
vi /monitoring/dpa/conf/dpa_sampler.env
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
systemctl restart dpa_sampler.timer
systemctl start dpa_sampler.service
journalctl -u dpa_sampler.service -n 100 --no-pager
```

## Repository Tables

| Table or view | Purpose |
| --- | --- |
| `dpa.ash_sample` | Mini-ASH active session samples |
| `dpa.sql_snapshot` | Top SQL counters and SQL text snapshots |
| `dpa.sql_plan_snapshot` | Execution plan rows for top SQL |
| `dpa.blocking_episode` | Blocking history with blocker/victim SQL ID |
| `dpa.change_event` | DDL/object change correlation |
| `dpa.object_stats_snapshot` | Hot segment/object signals |
| `dpa.app_slo` | Application SLO and business weighting |
| `dpa.dpa_advisory` | Generated tuning/advisory queue |
| `dpa.v_sql_impact_1h` | Impact score by SQL/wait/module/service |
| `dpa.v_plan_changes_24h` | SQL IDs with multiple plan hashes |
| `dpa.v_plan_diff_24h` | Text signatures for comparing changed plan operations |
| `dpa.v_wait_seasonal_baseline` | Day/hour wait baseline |

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
- seasonal wait baseline
- application SLO weights

## Validation

```bash
systemctl status postgresql --no-pager
systemctl list-timers dpa_sampler.timer --no-pager
systemctl start dpa_sampler.service
journalctl -u dpa_sampler.service -n 100 --no-pager
runuser -u postgres -- psql -d dpa_repository -c "SELECT count(*) FROM dpa.ash_sample;"
```

Grafana should show data after at least one successful sampler run.
