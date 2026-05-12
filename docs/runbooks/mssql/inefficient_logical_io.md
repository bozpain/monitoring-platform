# MSSQL Inefficient Logical I/O

## Tujuan

Cari query yang membaca terlalu banyak page per eksekusi, bahkan ketika CPU atau wait belum terlihat ekstrem.

## Cek Cepat

```sql
SELECT TOP (20)
  qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS logical_reads_per_exec,
  qs.execution_count,
  DB_NAME(st.dbid) AS database_name,
  SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
    ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS sql_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.execution_count > 0
ORDER BY logical_reads_per_exec DESC;
```

## Aksi

Review predicate, join order, covering index, key lookup, scan besar, dan statistik. Prioritaskan query dengan eksekusi tinggi dan impact score besar.
