# Oracle Runbook: DB File Sequential Read Pressure

## Signal

Alert: `OracleSequentialReadPressure`

Wait event: `db file sequential read`

## Meaning

Sessions are waiting on single-block reads, usually index lookups or table access by rowid. It can be normal for OLTP, but sustained spikes often indicate inefficient SQL access paths or slow storage.

## Check First

- Top SQL by disk reads per execution.
- Wait-to-SQL attribution.
- DPA Repository SQL text and execution plan rows.
- Node disk read latency and iowait.
- Hot objects from DPA Repository.

## Useful SQL

```sql
SELECT sql_id, module, event, COUNT(*) active_sessions
FROM gv$session
WHERE status = 'ACTIVE'
AND event = 'db file sequential read'
GROUP BY sql_id, module, event
ORDER BY active_sessions DESC;

SELECT sql_id, plan_hash_value, disk_reads, executions,
       ROUND(disk_reads / NULLIF(executions, 0), 2) disk_reads_per_exec
FROM gv$sql
WHERE executions > 0
ORDER BY disk_reads_per_exec DESC
FETCH FIRST 20 ROWS ONLY;
```

## Actions

- If one SQL dominates, compare current plan with previous plan.
- Check index selectivity, stale stats, bind variable behavior, and row estimates.
- If many SQLs wait and host read latency is high, escalate storage.
- If a recent schema/statistics change exists, review change correlation.

## Escalation

- DBA: plan/index/statistics review.
- App owner: SQL predicate or bind variable issue.
- Infrastructure: storage read latency.
