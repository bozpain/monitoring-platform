# MSSQL Monitoring Tiers

Tidak semua SQL Server harus masuk DPA repository. Gunakan tier agar overhead, storage, dan effort tuning tetap terkontrol.

| Tier | Cara Monitor | Cocok Untuk | Data Yang Disimpan |
|---|---|---|---|
| Standard | MSSQL exporter ke Prometheus | Instance non-kritis, dev/test, atau server yang hanya butuh health dan kapasitas | Time-series agregat tanpa SQL text |
| DPA | Exporter + MSSQL DPA sampler ke PostgreSQL local | Produksi kritis, performa sering dipertanyakan, atau sistem dengan SLA ketat | Request sample, SQL text, query hash, plan XML, blocking episode, ops signal, advisory |

## Kapan Pakai `mssql_dpa=yes`

Pakai DPA jika salah satu benar:

- Aplikasi punya SLA atau window batch penting.
- Query regression sering muncul setelah deployment atau statistik berubah.
- Blocking/deadlock perlu RCA, bukan hanya alert.
- Tim butuh history SQL text dan plan tanpa memasukkan text ke label Prometheus.
- Database owner setuju monitoring user diberi permission DMV tambahan.

## Kapan Cukup Exporter

Cukup exporter jika:

- Server hanya perlu availability, capacity, dan alert dasar.
- SQL text tidak boleh dikumpulkan.
- Target belum punya approval untuk `VIEW SERVER STATE`.
- Instance ephemeral atau non-kritis.

## Permission Minimum DPA

```sql
GRANT VIEW SERVER STATE TO [monitoring_user];
GRANT VIEW ANY DATABASE TO [monitoring_user];

USE msdb;
CREATE USER [monitoring_user] FOR LOGIN [monitoring_user];
GRANT SELECT ON dbo.backupset TO [monitoring_user];
GRANT SELECT ON dbo.sysjobs TO [monitoring_user];
GRANT SELECT ON dbo.sysjobhistory TO [monitoring_user];
```

Jika policy SQL Server 2022 memakai permission granular, gunakan `VIEW SERVER PERFORMANCE STATE` sesuai standar organisasi.

## Jalur Onboarding

1. Set `mssql=yes` untuk exporter.
2. Set `mssql_dpa=yes` hanya untuk instance yang butuh drilldown.
3. Isi `mssql_database` dan `mssql_port`.
4. Jalankan `python3 scripts/generate_targets.py`.
5. Jalankan `sudo bash scripts/install_mssql_dpa_target.sh <target>` di monitoring server.
6. Edit `/monitoring/dpa/conf/mssql-<target>.env`.
7. Start `sudo systemctl enable --now mssql_dpa_sampler@<target>.timer`.
