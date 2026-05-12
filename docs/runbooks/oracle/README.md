# Oracle Runbooks

Use these runbooks during incidents. They map Oracle alerts and DPA advisories to the first checks, useful SQL, likely owners, and escalation path.

| Alert or signal | Runbook |
| --- | --- |
| `OracleBlockingSession`, `OracleSevereBlocking` | [Blocking Sessions](blocking.md) |
| `OracleLogFileSyncPressure` | [Log File Sync Pressure](log_file_sync.md) |
| `OracleSequentialReadPressure` | [DB File Sequential Read Pressure](db_file_sequential_read.md) |
| `OraclePlanChangeRegression` | [SQL Plan Regression](plan_regression.md) |
| `OracleParseStorm`, `OracleCursorContention` | [Parse Storm](parse_storm.md) |
| `OracleHighDBTime`, `OracleDBTimeAnomaly`, `OracleWaitClassAnomaly`, `OracleHighWaitClassActivity` | [High DB Time or DB Time Anomaly](high_db_time.md) |
| `OracleInefficientLogicalIO` | [Inefficient Logical I/O](inefficient_logical_io.md) |

## How To Use

1. Start from the alert summary and affected `instance`, `app`, `tier`, and `owner`.
2. Open the matching dashboard panel.
3. Use the runbook checks to decide whether the likely owner is DBA, application, or infrastructure.
4. Use DPA Repository detail when the database is enabled for deep DPA monitoring.
5. Record the final root cause and remediation in the incident ticket.

## Dashboards

| Dashboard | Purpose |
| --- | --- |
| `02 - Oracle Performance DPA` | Live wait, SQL rate, blocking, and advisory signals |
| `03 - Oracle Sessions & Blocking` | Session and blocker/victim relationships |
| `04 - Oracle SQL Activity` | SQL rate, per-execution efficiency, plan candidates |
| `07 - Oracle DPA Repository` | Historical mini-ASH, SQL text, plan diff, operational signals |

## DPA Requirement

Some runbook sections reference DPA Repository data. If a database is exporter-only, use live exporter panels and manual SQL instead.
