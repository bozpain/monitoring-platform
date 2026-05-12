# MSSQL Plan Regression

## Tujuan

Cari query hash yang tiba-tiba punya plan hash berbeda dan performanya memburuk.

## Cek Cepat

```sql
SELECT TOP (50)
  CONVERT(varchar(34), query_hash, 1) AS query_hash,
  COUNT(DISTINCT query_plan_hash) AS plan_count,
  MIN(last_execution_time) AS first_seen,
  MAX(last_execution_time) AS last_seen
FROM sys.dm_exec_query_stats
GROUP BY query_hash
HAVING COUNT(DISTINCT query_plan_hash) > 1
ORDER BY last_seen DESC;
```

## Aksi

Cek perubahan statistik, parameter sniffing, index change, compatibility level, dan Query Store jika aktif. Gunakan forced plan hanya setelah plan sehat terkonfirmasi.
