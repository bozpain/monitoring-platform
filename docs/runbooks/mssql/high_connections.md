# MSSQL High Connections

## Tujuan

Identifikasi aplikasi, host, dan login yang membuat koneksi terlalu banyak.

## Cek Cepat

```sql
SELECT
  login_name,
  host_name,
  program_name,
  COUNT(*) AS sessions,
  SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) AS running_sessions,
  SUM(CASE WHEN status = 'sleeping' THEN 1 ELSE 0 END) AS sleeping_sessions
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY login_name, host_name, program_name
ORDER BY sessions DESC;
```

## Aksi

Cek connection pool, retry storm, job paralel, dan session sleeping dengan open transaction.
