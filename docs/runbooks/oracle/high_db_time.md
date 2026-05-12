# Oracle Runbook: High DB Time or DB Time Anomaly

## Signal

Alerts: `OracleHighDBTime`, `OracleDBTimeAnomaly`

## Meaning

Database response-time load is high, either above an absolute threshold or above its historical baseline.

## Check First

- DB Time vs CPU Usage.
- ASH-like wait class and top wait events.
- Wait-to-SQL attribution.
- Top SQL by elapsed and CPU rate.
- Host CPU, memory, disk latency, and iowait.
- DPA Repository advisory queue and recent changes.

## Useful SQL

```sql
SELECT wait_class, event, COUNT(*) active_sessions
FROM gv$session
WHERE status = 'ACTIVE'
AND wait_class <> 'Idle'
GROUP BY wait_class, event
ORDER BY active_sessions DESC;

SELECT sql_id, module, COUNT(*) active_sessions
FROM gv$session
WHERE status = 'ACTIVE'
GROUP BY sql_id, module
ORDER BY active_sessions DESC;
```

## Actions

- If CPU dominates, identify top SQL CPU rate and host CPU saturation.
- If waits dominate, use event-specific runbook.
- If a single SQL dominates, open it in DPA Repository.
- If spike follows a change, review deployment/schema/statistics events.

## Escalation

- DBA: wait event and SQL root cause.
- App owner: module-specific workload surge.
- Infrastructure: host CPU, memory, disk, or network pressure.
