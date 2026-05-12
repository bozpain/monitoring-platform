# Oracle Runbook: Blocking Sessions

## Signal

Alerts: `OracleBlockingSession`, `OracleSevereBlocking`

## Meaning

One or more sessions are blocked by another session holding a lock. Severe blocking can cascade into application outage even if CPU and storage look normal.

## Check First

- Dashboard `03 - Oracle Sessions & Blocking`.
- Dashboard `02 - Oracle Performance DPA`: Blocking by SQL.
- DPA Repository: blocking episode history.
- Application module/service for blocker and victim.

## Useful SQL

```sql
SELECT s.inst_id,
       s.sid blocked_sid,
       s.serial# blocked_serial,
       s.username blocked_user,
       s.sql_id blocked_sql_id,
       s.blocking_session blocker_sid,
       b.serial# blocker_serial,
       b.username blocker_user,
       b.sql_id blocker_sql_id,
       s.event,
       s.seconds_in_wait
FROM gv$session s
LEFT JOIN gv$session b
  ON s.inst_id = b.inst_id
 AND s.blocking_session = b.sid
WHERE s.blocking_session IS NOT NULL
ORDER BY s.seconds_in_wait DESC;
```

## Actions

- Identify root blocker before killing sessions.
- Contact app owner if blocker belongs to a known module or batch job.
- Check if blocker is idle in transaction.
- For production, follow DBA kill-session approval policy.

## Escalation

- DBA: root blocker analysis and kill-session decision.
- App owner: long transaction or uncommitted work.
- Incident manager: severe blocking across many sessions.
