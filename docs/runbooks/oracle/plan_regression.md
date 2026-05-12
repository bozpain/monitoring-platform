# Oracle Runbook: SQL Plan Regression

## Signal

Alert: `OraclePlanChangeRegression`

## Meaning

A SQL ID has multiple cached plans and its elapsed time rate is higher than baseline. This often points to changed bind values, stale stats, new indexes, dropped indexes, optimizer setting changes, or deployment changes.

## Check First

- DPA Repository: Plan Change Candidates.
- DPA Repository: Plan Diff Signatures.
- DPA Repository: SQL Text Snapshots.
- Recent Change Correlation.
- Hot Objects and stale stats operational signals.

## Useful SQL

```sql
SELECT sql_id, plan_hash_value, child_number, executions, elapsed_time, cpu_time,
       buffer_gets, disk_reads, last_active_time
FROM gv$sql
WHERE sql_id = :sql_id
ORDER BY last_active_time DESC;

SELECT id, parent_id, operation, options, object_owner, object_name,
       cardinality, cost
FROM gv$sql_plan
WHERE sql_id = :sql_id
ORDER BY plan_hash_value, child_number, id;
```

## Actions

- Compare changed operations: full scan vs index access, join method, join order.
- Check whether object stats became stale or changed recently.
- Check recent DDL, index changes, and deployments.
- Consider SQL Plan Baseline only after confirming the previous plan is still safe.

## Escalation

- DBA: optimizer stats, SQL plan baseline, index review.
- App owner: bind values, changed SQL shape, deployment behavior.
