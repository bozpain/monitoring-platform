# MSSQL High Waits

## Tujuan

Pisahkan wait yang normal dari bottleneck aktual, lalu korelasikan ke query, plan, dan resource.

## Cek Cepat

```sql
SELECT TOP (20)
  wait_type,
  waiting_tasks_count,
  wait_time_ms,
  signal_wait_time_ms,
  wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type NOT LIKE 'SLEEP%'
ORDER BY wait_time_ms DESC;
```

## Interpretasi

`LCK%` biasanya blocking. `PAGEIOLATCH%` mengarah ke storage/read path. `WRITELOG` mengarah ke log write latency atau transaksi terlalu besar. `RESOURCE_SEMAPHORE` biasanya memory grant. `CXPACKET/CXCONSUMER` perlu dicek bersama skew plan dan paralelisme.

## Di Dashboard

Gunakan `Query Impact Last Hour` dan `Advisory Queue` untuk melihat query hash yang menyumbang active seconds paling besar.
