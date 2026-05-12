# MSSQL Runbooks

Runbook ini dipakai sebagai landing page saat alert MSSQL muncul. Mulai dari alert yang aktif, buka dashboard `07 - MSSQL DPA Repository`, lalu filter `instance_name` dan `query_hash` jika tersedia.

## Urutan Investigasi Cepat

1. Cek `Advisory Queue` untuk sinyal paling tinggi.
2. Cek `Query Impact Last Hour` untuk query hash, wait type, dan sample SQL text.
3. Cek `Plan Change Candidates` jika performa berubah mendadak.
4. Cek `Blocking History` untuk masalah lock.
5. Cek `Operational Signals` untuk database state, backup age, dan SQL Agent failure.

## Runbook Detail

| Kondisi | Runbook |
|---|---|
| Blocking atau deadlock | [blocking.md](blocking.md) |
| Wait time tinggi | [high_waits.md](high_waits.md) |
| CPU pressure | [cpu_pressure.md](cpu_pressure.md) |
| I/O latency | [io_latency.md](io_latency.md) |
| Memory pressure | [memory_pressure.md](memory_pressure.md) |
| Koneksi tinggi | [high_connections.md](high_connections.md) |
| Query berjalan lama | [long_running_query.md](long_running_query.md) |
| Plan regression | [plan_regression.md](plan_regression.md) |
| Logical I/O boros | [inefficient_logical_io.md](inefficient_logical_io.md) |
