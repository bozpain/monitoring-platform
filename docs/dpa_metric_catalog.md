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
| Wait analysis | `oracle_ash_like_wait_class_value`, `oracle_ash_like_wait_event_value` | DPA-style wait class/event analysis |
| DB time / CPU | `oracle_db_time_per_sec_value`, `oracle_cpu_usage_per_sec_value` | Response time and CPU demand |
| Sessions | `oracle_sessions_total_value`, `oracle_sessions_active_value`, `oracle_sessions_used_percent` | Session pressure |
| Blocking | `oracle_blocking_tree_value`, `oracle_blocking_sessions` | Root blocker and blocked sessions |
| Long running SQL | `oracle_long_running_sessions_value`, `oracle_long_running_queries` | Slow active requests |
| Top SQL | `oracle_top_sql_*_value`, `oracle_sql_plan_hash_value` | SQL by elapsed, CPU, reads, executions, plan hash |
| Capacity | `oracle_tablespace_usage_*`, `oracle_temp_usage_*`, `oracle_fra_usage_*` | Tablespace, temp, FRA |
| RAC/ASM | `oracle_rac_*`, `oracle_asm_*` | Cluster and storage layer |
| Deadlocks | `oracle_deadlocks_total` | Locking anomalies |

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

Advanced DPA features such as proprietary anomaly detection and tuning advisors are not cloned here. Those can be approximated later with Prometheus rules, Grafana annotations, and scheduled SQL plan/statistics snapshots.
