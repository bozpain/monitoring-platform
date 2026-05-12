# MSSQL I/O Latency

## Tujuan

Pastikan apakah lambatnya berasal dari data file, log file, query read pattern, atau storage layer.

## Cek Cepat

```sql
SELECT
  DB_NAME(vfs.database_id) AS database_name,
  mf.type_desc,
  mf.physical_name,
  vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) AS avg_read_ms,
  vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) AS avg_write_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf
  ON mf.database_id = vfs.database_id
 AND mf.file_id = vfs.file_id
ORDER BY COALESCE(vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0), 0)
       + COALESCE(vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0), 0) DESC;
```

## Aksi

Untuk `PAGEIOLATCH%`, cek query logical reads dan missing/unused index. Untuk `WRITELOG`, cek log disk latency, batch size, autogrowth, dan transaksi panjang.
