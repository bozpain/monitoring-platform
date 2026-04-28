# Alert Catalog

This catalog describes the default alert policy. Thresholds are conservative starting points and should be tuned after the first 2-4 weeks of real workload data.

## Alert Philosophy

- Page on availability, severe blocking, full storage, and database not online.
- Warn on symptoms that explain response time: waits, I/O latency, memory pressure, session pressure, and long-running SQL.
- Keep warning and critical thresholds mutually exclusive so the same condition does not create duplicate noise.
- Preserve `app`, `tier`, `owner`, `instance`, `db_type`, and `category` labels whenever possible for Alertmanager routing.

## MSSQL Alerts

| Alert | Severity | Trigger | Why it matters |
| --- | --- | --- | --- |
| `MSSQLExporterDown` | critical | `up{job="mssql"} == 0` for 2m | Prometheus cannot scrape exporter |
| `MSSQLDatabaseDown` | critical | `mssql_up == 0` for 2m | Exporter cannot connect to SQL Server |
| `MSSQLDatabaseNotOnline` | critical | database state is not online for 3m | Database unavailable or degraded |
| `MSSQLDataFileHighUsage` | warning | data usage 85-95% for 5m | Capacity risk |
| `MSSQLDataFileCriticalUsage` | critical | data usage >= 95% for 5m | Immediate capacity risk |
| `MSSQLLogFileHighUsage` | warning | log usage 80-90% for 5m | Transaction log pressure |
| `MSSQLLogFileCriticalUsage` | critical | log usage >= 90% for 5m | Immediate log pressure |
| `MSSQLTempDBHighUsage` | warning | TempDB usage 80-90% for 5m | TempDB pressure |
| `MSSQLTempDBCriticalUsage` | critical | TempDB usage >= 90% for 5m | Immediate TempDB risk |
| `MSSQLBlockingSession` | warning | 1-4 blocked sessions for 3m | Blocking affects response time |
| `MSSQLSevereBlocking` | critical | >= 5 blocked sessions for 3m | Widespread blocking |
| `MSSQLDeadlockDetected` | critical | deadlock increase in 5m | Transaction failures |
| `MSSQLLongRunningQuery` | warning | request running > 5m | Slow SQL / possible blocker |
| `MSSQLHighWaitTimeRate` | warning | total waits > 5000 ms/sec for 10m | DPA-style wait pressure |
| `MSSQLHighSignalWaitRatio` | warning | signal wait ratio > 25% for 10m | CPU runnable queue pressure |
| `MSSQLReadLatencyHigh` | warning | read latency > 20 ms/op for 10m | Storage read bottleneck |
| `MSSQLWriteLatencyHigh` | warning | write latency > 20 ms/op for 10m | Storage write/log bottleneck |
| `MSSQLMemoryPressure` | warning | memory grants pending > 0 for 5m | Query memory pressure |
| `MSSQLLowBufferCacheHitRatio` | warning | buffer cache hit ratio < 90% for 10m | Cache pressure |
| `MSSQLPageLifeExpectancyLow` | warning | PLE < 300s for 10m | Memory churn |
| `MSSQLConnectionHigh` | warning | connections > 500 for 5m | Connection pressure |

## VictoriaMetrics Alerts

| Alert | Severity | Trigger | Why it matters |
| --- | --- | --- | --- |
| `VictoriaMetricsDown` | critical | `up{job="victoriametrics"} == 0` for 2m | Storage is unavailable to Prometheus/Grafana |
| `VictoriaMetricsRowsIgnored` | warning | ignored rows increase in 5m | Data is being dropped or rejected |
| `VictoriaMetricsCacheSaturated` | warning | cache usage > 95% for 10m | Cache pressure may increase CPU/disk I/O |

## Prometheus Alerts

| Alert | Severity | Trigger | Why it matters |
| --- | --- | --- | --- |
| `PrometheusDown` | critical | `up{job="prometheus"} == 0` for 2m | Scrape, rule, and alert engine unavailable |
| `PrometheusConfigReloadFailed` | warning | last config reload unsuccessful for 5m | Prometheus is not running latest valid config |
| `PrometheusRuleEvaluationFailures` | warning | rule failures increase in 5m | Recording or alert rules may be wrong |
| `PrometheusRemoteWriteFailures` | warning | failed remote-write samples for 5m | Data may not reach VictoriaMetrics |
| `PrometheusRemoteWriteBacklogHigh` | warning | pending samples > 100000 for 10m | Remote-write queue is falling behind |
| `PrometheusTSDBHeadSeriesHigh` | warning | active series > 2M for 15m | Cardinality or target count may be too high |

## Alertmanager Alerts

| Alert | Severity | Trigger | Why it matters |
| --- | --- | --- | --- |
| `AlertmanagerDown` | critical | `up{job="alertmanager"} == 0` for 2m | Alert notifications may not be delivered |
| `AlertmanagerConfigReloadFailed` | warning | last config reload unsuccessful for 5m | Alertmanager is not running latest valid config |
| `AlertmanagerNotificationFailures` | warning | failed notifications for 5m | Email or notification receiver path may be broken |

## Oracle Alerts

| Alert | Severity | Trigger | Why it matters |
| --- | --- | --- | --- |
| `OracleExporterDown` | critical | `up{job="oracle"} == 0` for 2m | Prometheus cannot scrape exporter |
| `OracleDatabaseDown` | critical | `oracle_up == 0` for 2m | Exporter cannot connect to Oracle |
| `OracleTablespaceHighUsage` | warning | tablespace usage 85-95% for 5m | Capacity risk |
| `OracleTablespaceCriticalUsage` | critical | tablespace usage >= 95% for 5m | Immediate capacity risk |
| `OracleArchiveHighUsage` | warning | archived log/FRA usage 85-95% for 5m | Archive pressure |
| `OracleArchiveCriticalUsage` | critical | archived log/FRA usage >= 95% for 5m | Immediate archive risk |
| `OracleTempTablespaceHighUsage` | warning | temp usage 80-90% for 5m | Sort/hash/temp pressure |
| `OracleTempTablespaceCriticalUsage` | critical | temp usage >= 90% for 5m | Immediate temp capacity risk |
| `OracleSessionHigh` | warning | session usage 85-95% for 5m | Session limit pressure |
| `OracleSessionCritical` | critical | session usage >= 95% for 5m | Immediate session limit risk |
| `OracleBlockingSession` | warning | 1-4 blocked sessions for 3m | Blocking affects response time |
| `OracleSevereBlocking` | critical | >= 5 blocked sessions for 3m | Widespread blocking |
| `OracleDeadlockDetected` | critical | deadlock increase in 5m | Transaction failures |
| `OracleLongRunningQuery` | warning | active session > 5m | Slow SQL / possible blocker |
| `OracleHighWaitClassActivity` | warning | wait class active sessions >= 10 for 10m | DPA-style wait pressure |
| `OracleHighDBTime` | warning | DB time/sec >= 60 for 10m | High database response-time load |

## Node Alerts

| Alert | Severity | Trigger | Why it matters |
| --- | --- | --- | --- |
| `NodeExporterDown` | critical | `up{job="node"} == 0` for 2m | Prometheus cannot scrape host metrics |
| `NodeHighCPUUsage` | warning | CPU 85-95% for 5m | Host CPU pressure |
| `NodeCriticalCPUUsage` | critical | CPU > 95% for 5m | Severe host CPU pressure |
| `NodeHighMemoryUsage` | warning | memory 85-95% for 5m | Host memory pressure |
| `NodeCriticalMemoryUsage` | critical | memory > 95% for 5m | Severe host memory pressure |
| `NodeDiskHighUsage` | warning | filesystem 85-95% for 5m | Capacity risk |
| `NodeDiskCriticalUsage` | critical | filesystem > 95% for 5m | Immediate capacity risk |
| `NodeInodeUsageHigh` | warning | inode usage > 85% for 5m | File creation risk |
| `NodeHighLoad` | warning | load1 > CPU count for 5m | Run queue pressure |
| `NodeNetworkHighErrorRate` | warning | errors > 10/sec for 5m | Network reliability issue |
| `NodeHighDiskIOTime` | warning | disk busy > 80% for 5m | I/O saturation |
| `NodeHighIOWait` | warning | CPU iowait > 20% for 5m | Storage wait correlation |
| `NodeDiskReadLatencyHigh` | warning | read latency > 50ms for 5m | Storage read bottleneck |
| `NodeDiskWriteLatencyHigh` | warning | write latency > 50ms for 5m | Storage write bottleneck |
| `NodeSwapUsageHigh` | warning | swap usage > 20% for 5m | Memory pressure |
| `NodeNetworkDropRateHigh` | warning | packet drops > 10/sec for 5m | Network packet loss |

## Validation

Run on the monitoring VM after deployment:

```bash
/monitoring/prometheus/bin/promtool check rules /monitoring/prometheus/conf/alerts/*.yml
curl http://localhost:9090/api/v1/rules
curl http://localhost:9090/api/v1/alerts
```

If an alert does not appear in `/api/v1/rules`, check `journalctl -u prometheus -n 100 --no-pager`.
