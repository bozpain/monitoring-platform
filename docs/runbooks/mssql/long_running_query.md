# MSSQL Long Running Query

## Tujuan

Tentukan apakah query memang batch panjang yang valid, atau query stuck karena lock, I/O, memory grant, atau plan buruk.

## Cek Cepat

```sql
SELECT
  r.session_id,
  r.status,
  r.command,
  r.wait_type,
  r.wait_time,
  r.blocking_session_id,
  r.cpu_time,
  r.total_elapsed_time,
  DB_NAME(r.database_id) AS database_name,
  t.text AS sql_text
FROM sys.dm_exec_requests r
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID
ORDER BY r.total_elapsed_time DESC;
```

## Di Dashboard

Filter `query_hash` di dashboard DPA repository, lalu bandingkan SQL text, plan hash, wait type, dan impact score.
