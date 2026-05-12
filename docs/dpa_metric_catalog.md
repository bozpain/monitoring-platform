# DPA-Style Metric Catalog

This catalog documents the monitoring coverage expected from the platform. It is inspired by wait-based database performance analysis: start from wait time and top SQL, then correlate to sessions, blocking, capacity, and host resources.

## Design Principles

- Prefer metrics that explain user-visible database response time.
- Keep high-cardinality labels bounded; top SQL and session detail queries intentionally use `TOP` limits.
- Use Prometheus recording rules to expose stable dashboard metric names even when exporter query output uses `_value` suffixes.
- Correlate database symptoms with node resource pressure instead of treating host metrics as separate noise.

## Fleet

| Area | Metric examples | Purpose |
| --- | --- | --- |
| Availability | `up`, `oracle_up`, `mssql_up` | Instance and exporter health |
| Inventory labels | `app`, `tier`, `owner`, `db_type`, `service` | Filter by application, environment, owner |
| Alerts | active Prometheus alerts | Fleet risk view |

## Node / OS

| Area | Metric examples | Purpose |
| --- | --- | --- |
| CPU | `node_cpu_seconds_total`, iowait alert | CPU pressure and storage wait correlation |
| Memory | `node_memory_MemAvailable_bytes`, swap alerts | Memory pressure and paging |
| Disk capacity | `node_filesystem_size_bytes`, `node_filesystem_avail_bytes` | Filesystem fullness and growth |
| Disk latency/IO | `node_disk_read_time_seconds_total`, `node_disk_write_time_seconds_total`, `node_disk_io_time_seconds_total` | Storage bottleneck correlation |
| Network | `node_network_*_bytes_total`, errors, drops | Connectivity and packet loss |
| Load/process churn | `node_load1`, `node_forks_total`, context switches | Saturation symptoms |

## Oracle

| Area | Metric examples | Purpose |
| --- | --- | --- |
| Availability | `oracle_up` | DB connection health from exporter |
| Wait analysis | `oracle_ash_like_wait_class_value`, `oracle_ash_like_wait_event_value`, `oracle:active_sessions_by_sql_wait` | DPA-style wait class/event analysis and wait-to-SQL attribution |
| DB time / CPU | `oracle_db_time_per_sec_value`, `oracle_cpu_usage_per_sec_value` | Response time and CPU demand |
| Sessions | `oracle_sessions_total_value`, `oracle_sessions_active_value`, `oracle_sessions_used_percent` | Session pressure |
| Blocking | `oracle_blocking_tree_value`, `oracle_blocking_sessions`, `oracle:blocking_by_sql` | Root blocker, blocked sessions, and blocker/blocked SQL IDs |
| Long running SQL | `oracle_long_running_sessions_value`, `oracle_long_running_queries` | Slow active requests |
| Top SQL | `oracle:sql_elapsed_seconds_per_sec:rate5m`, `oracle:sql_cpu_seconds_per_sec:rate5m`, `oracle:sql_buffer_gets_per_exec:rate5m`, `oracle:sql_disk_reads_per_exec:rate5m`, `oracle:sql_rows_per_exec:rate5m`, `oracle:sql_parse_calls_per_sec:rate5m` | SQL by recent workload rate and per-execution efficiency |
| Plan stability | `oracle_sql_plan_hash_value`, `oracle:sql_plan_count`, `OraclePlanChangeRegression` | Detect SQL IDs with multiple cached plans and possible regression after plan changes |
| Baselines | `oracle:db_time_per_sec:avg_7d`, `oracle:wait_class_active_sessions:avg_7d` | Compare current load and waits against historical normal behavior |
| Capacity | `oracle_tablespace_usage_*`, `oracle_temp_usage_*`, `oracle_fra_usage_*` | Tablespace, temp, FRA |
| RAC/ASM | `oracle_rac_*`, `oracle_asm_*` | Cluster and storage layer |
| Deadlocks | `oracle_deadlocks_total` | Locking anomalies |

### Oracle DPA Enhancements

The Oracle layer now separates three levels of SQL visibility:

| Layer | Where | Purpose |
| --- | --- | --- |
| Prometheus metrics | `oracle_sql_workload_delta_*`, recording rules under `oracle:sql_*` | Recent SQL workload rate, plan hash, schema, module, action, and service |
| Session attribution | `oracle_session_wait_sql`, `oracle_blocking_sql` | Tie active waits and blocking directly to SQL IDs and application context |
| SQL text snapshot | `config/oracle/oracle-sql-text-snapshot.sql` | Optional drilldown store for SQL text without putting SQL text in Prometheus labels |

The old cumulative `oracle_top_sql_*_value` metrics remain available for compatibility, but dashboards should prefer the `rate5m` recording rules because they show what is expensive now instead of what has accumulated in the cursor cache over time.

Advisory alerts approximate tuning guidance:

| Alert | Signal | Suggested investigation |
| --- | --- | --- |
| `OracleDBTimeAnomaly` | DB time exceeds 2x the 7-day baseline | Check dominant waits, top SQL rate, and host pressure |
| `OracleWaitClassAnomaly` | Wait class exceeds 2x the 7-day baseline | Drill into wait event and attributed SQL |
| `OraclePlanChangeRegression` | Multiple plans plus elapsed rate regression | Compare plan hash values and SQL text snapshot |
| `OracleLogFileSyncPressure` | Many sessions on `log file sync` | Check commit frequency and redo I/O latency |
| `OracleSequentialReadPressure` | Many sessions on `db file sequential read` | Check top SQL disk reads per execution and storage latency |
| `OracleCursorContention` | Library cache/cursor waits | Check parse storm, bind usage, version count, and deployments |
| `OracleParseStorm` | High parse calls per second | Check application cursor reuse and bind variables |
| `OracleInefficientLogicalIO` | High buffer gets per execution | Tune predicates, indexes, joins, and plan stability |

## MSSQL

| Area | Metric examples | Purpose |
| --- | --- | --- |
| Availability | `mssql_up` | DB connection health from exporter |
| Wait analysis | `mssql_wait_time_ms_total`, `mssql_signal_wait_time_ms_total` | DPA-style top waits and signal/resource split |
| Throughput | `mssql_batch_requests_total`, `mssql_transactions_total` | Workload rate |
| Sessions | `mssql_active_sessions`, `mssql_sleeping_sessions`, `mssql_session_info` | Session load and detail |
| Blocking | `mssql_blocked_sessions`, `mssql_blocking_session_info`, `mssql_lock_waits_total`, `mssql_deadlocks_total` | Root blocker and lock impact |
| Top SQL | `mssql_query_cpu_time_ms`, `mssql_query_duration_ms`, `mssql_query_logical_reads`, `mssql_query_execution_count` | Expensive cached queries |
| I/O | `mssql_io_reads_total`, `mssql_io_writes_total`, latency counters | Database file latency and IOPS |
| Memory/cache | `mssql_buffer_cache_hit_ratio`, `mssql_page_life_expectancy_seconds`, `mssql_memory_grants_pending` | Cache and memory pressure |
| Capacity | `mssql_database_size_bytes`, data/log usage, file size, TempDB usage | Storage and TempDB pressure |

## SolarWinds DPA Alignment

The platform now covers the practical DPA investigation path:

1. Identify unhealthy database instances from fleet availability.
2. Drill into waits by class/type and find the dominant wait contributors.
3. Check top SQL by elapsed time, CPU, logical reads, and executions.
4. Inspect blocking sessions and long-running requests.
5. Correlate with host CPU, memory, disk latency, and network drops.
6. Validate capacity pressure in tablespace/data/log/TempDB/FRA.

Advanced proprietary advisors are not cloned here. The platform now approximates the practical behavior with Prometheus baselines, plan-change detection, wait-to-SQL attribution, bounded top-SQL metrics, Grafana advisory panels, and optional SQL text snapshots.
