# Oracle Runbook: Log File Sync Pressure

## Signal

Alert: `OracleLogFileSyncPressure`

Wait event: `log file sync`

## Meaning

Foreground sessions are waiting for commit confirmation. Common causes are excessive commit frequency, redo log write latency, LGWR pressure, or storage latency.

## Check First

- Dashboard `02 - Oracle Performance DPA`: wait-to-SQL attribution.
- Dashboard `07 - Oracle DPA Repository`: SQL impact, module/service, advisory queue.
- Node dashboard: disk write latency and iowait on the database host.
- Recent change correlation for deployments, batch jobs, or schema changes.

## Useful SQL

```sql
SELECT username, module, machine, sql_id, event, COUNT(*) active_sessions
FROM gv$session
WHERE status = 'ACTIVE'
AND event = 'log file sync'
GROUP BY username, module, machine, sql_id, event
ORDER BY active_sessions DESC;

SELECT name, value
FROM v$sysstat
WHERE name IN ('user commits', 'redo writes', 'redo write time');
```

## Actions

- If one module dominates, ask the app owner to check commit batching.
- If storage latency is high, escalate to infrastructure/storage.
- If redo logs share busy disks, review redo placement.
- If the issue started after deployment, correlate with release/change events.

## Escalation

- App owner: commit storm from specific module/service.
- DBA: redo configuration, LGWR pressure, log file sizing.
- Infrastructure: storage latency or saturation.
