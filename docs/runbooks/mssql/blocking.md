# MSSQL Blocking

## Tujuan

Temukan blocker utama, transaksi yang menahan lock, dan query yang terdampak sebelum melakukan kill session.

## Cek Cepat

```sql
SELECT
  r.session_id AS blocked_session_id,
  r.blocking_session_id,
  r.wait_type,
  r.wait_time,
  r.wait_resource,
  s.login_name,
  s.host_name,
  s.program_name,
  t.text AS sql_text
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id <> 0
ORDER BY r.wait_time DESC;
```

## Di Dashboard

Buka `07 - MSSQL DPA Repository` lalu cek `Blocking History` dan `Query Impact Last Hour`. Jika blocker berulang dengan query hash yang sama, lanjutkan ke plan dan index review.

## Aksi Aman

Pastikan owner aplikasi setuju sebelum `KILL <session_id>`. Jika blocking berasal dari transaksi idle, cek aplikasi, job batch, dan retry behavior.
