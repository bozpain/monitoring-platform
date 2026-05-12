# MSSQL CPU Pressure

## Tujuan

Bedakan CPU pressure karena query mahal, plan berubah, compile storm, atau parallelism skew.

## Cek Cepat

```sql
SELECT TOP (20)
  qs.total_worker_time,
  qs.execution_count,
  qs.total_worker_time / NULLIF(qs.execution_count, 0) AS avg_worker_time,
  DB_NAME(st.dbid) AS database_name,
  SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
    ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS sql_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_worker_time DESC;
```

## Aksi

Cek `Plan Change Candidates`, statistik tabel utama, parameter sniffing, dan query dengan `avg_worker_time` tinggi.
