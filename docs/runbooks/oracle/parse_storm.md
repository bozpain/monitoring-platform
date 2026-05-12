# Oracle Runbook: Parse Storm

## Signal

Alert: `OracleParseStorm`

Related waits: `library cache lock`, `library cache pin`, `cursor: pin S wait on X`

## Meaning

The application is parsing too frequently or creating many cursor versions. Common causes are literal SQL, missing bind variables, frequent hard parses, object invalidation, or deployment activity.

## Check First

- Top SQL by parse calls per second.
- Top SQL version count.
- Cursor/library cache wait alerts.
- Recent deployments or object invalidation.
- DPA Repository SQL text snapshots.

## Useful SQL

```sql
SELECT sql_id, parsing_schema_name, module, parse_calls, executions,
       version_count, loads, invalidations
FROM gv$sqlarea
ORDER BY parse_calls DESC
FETCH FIRST 20 ROWS ONLY;

SELECT event, COUNT(*) active_sessions
FROM gv$session
WHERE status = 'ACTIVE'
AND event IN ('library cache lock', 'library cache pin', 'cursor: pin S wait on X')
GROUP BY event
ORDER BY active_sessions DESC;
```

## Actions

- If SQL text differs only by literals, ask app team to use bind variables.
- If version count is high, inspect bind peeking, adaptive cursor sharing, and session settings.
- If invalidations rose after deployment, review changed objects/packages.
- If parse storm is system-wide, check connection pooling behavior.

## Escalation

- App owner: bind variables, cursor reuse, connection pooling.
- DBA: cursor sharing, shared pool pressure, invalidation source.
