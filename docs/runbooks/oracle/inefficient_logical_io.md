# Oracle Runbook: Inefficient Logical I/O

## Signal

Alert: `OracleInefficientLogicalIO`

## Meaning

A SQL statement is doing high buffer gets per execution. This usually means inefficient predicates, poor join order, stale stats, missing/unused indexes, or fetching far more rows than expected.

## Check First

- Top SQL by buffer gets per execution.
- DPA Repository SQL text snapshot.
- DPA Repository execution plan rows and plan diff.
- Hot objects and stale stats operational signals.

## Useful SQL

```sql
SELECT sql_id, plan_hash_value, executions, buffer_gets,
       ROUND(buffer_gets / NULLIF(executions, 0), 2) buffer_gets_per_exec,
       rows_processed
FROM gv$sql
WHERE executions > 0
ORDER BY buffer_gets_per_exec DESC
FETCH FIRST 20 ROWS ONLY;
```

## Actions

- Check whether predicates are selective and bind-aware.
- Compare actual rows processed vs expected cardinality.
- Check object stats and index selectivity.
- Review plan changes if the issue is new.

## Escalation

- DBA: plan, index, statistics, SQL baseline.
- App owner: SQL predicate, bind values, excessive result set.
