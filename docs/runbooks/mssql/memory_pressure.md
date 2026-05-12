# MSSQL Memory Pressure

## Tujuan

Cari apakah tekanan memori berasal dari buffer pool, memory grants, atau konfigurasi max server memory.

## Cek Cepat

```sql
SELECT
  counter_name,
  cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%Memory Manager%'
   OR object_name LIKE '%Buffer Manager%';

SELECT *
FROM sys.dm_exec_query_memory_grants
ORDER BY requested_memory_kb DESC;
```

## Aksi

Jika `RESOURCE_SEMAPHORE` dominan, cek query grant besar, statistik, cardinality estimate, dan concurrency batch. Validasi `max server memory` supaya OS masih punya headroom.
