<div align="center">

<img src="images/platform-architecture.svg" alt="Internal Database Observability Platform architecture" width="100%">

<h1>Deployment Guide Expand</h1>

<p><strong>Runbook teknis untuk ekspansi dari single VM menjadi 3 VM: control plane, metrics storage, dan exporter node.</strong></p>

<img src="https://img.shields.io/badge/Mode-3%20VM%20Expansion-7C3AED?style=for-the-badge&logo=databricks&logoColor=white" alt="3 VM expansion">
<img src="https://img.shields.io/badge/VM1-Control%20Plane-2563EB?style=for-the-badge&logo=prometheus&logoColor=white" alt="VM1 control plane">
<img src="https://img.shields.io/badge/VM2-Metrics%20Storage-16A34A?style=for-the-badge&logo=victoriametrics&logoColor=white" alt="VM2 metrics storage">
<img src="https://img.shields.io/badge/VM3-Exporter%20Node-F97316?style=for-the-badge&logo=linux&logoColor=white" alt="VM3 exporter node">

</div>

## 1. Kapan Dipakai

Gunakan guide ini ketika single-VM platform sudah berjalan dan workload perlu dipisah:

| Kondisi | Alasan expand |
| --- | --- |
| Storage metrics mulai besar | VictoriaMetrics dipindah ke VM khusus |
| Exporter workload makin ramai | Exporter DB dipindah ke node terpisah |
| Akses jaringan perlu dipisah | VM3 bisa ditempatkan dekat subnet database |
| Control plane perlu lebih stabil | VM1 fokus Prometheus, Grafana, Alertmanager |

Untuk instalasi awal single VM, gunakan [deployment_guide.md](deployment_guide.md).

## 2. Target Topology

| VM | Role | Services |
| --- | --- | --- |
| VM1 | Control plane | Prometheus, Grafana, Alertmanager |
| VM2 | Metrics storage | VictoriaMetrics |
| VM3 | Exporter node | Node exporter, Oracle exporter, MSSQL exporter |

Data flow:

```text
Database hosts -> Exporters on VM3 -> Prometheus on VM1 -> VictoriaMetrics on VM2
                                           |
                                           v
                                  Alertmanager on VM1

Grafana on VM1 -> VictoriaMetrics on VM2
```

## 3. Prinsip Perubahan

| Area | Keputusan |
| --- | --- |
| VM1 | Tetap menjadi control plane. Tidak reinstall Prometheus, Grafana, atau Alertmanager. |
| VM2 | Menjadi storage long-retention. Prometheus `remote_write` diarahkan ke VM2. |
| VM3 | Menjadi exporter node. Prometheus target file diarahkan ke VM3. |
| Grafana | Datasource diarahkan ke VictoriaMetrics di VM2. |
| Alertmanager | Tetap di VM1 dan tetap menerima alert dari Prometheus VM1. |

## 4. Pre-Check

Pastikan kondisi ini terpenuhi sebelum expand:

| Status | Item |
| --- | --- |
| `[ ]` | Single-VM deployment sudah sehat |
| `[ ]` | `sudo ./09_health_check.sh` di VM1 minimal `PASSED WITH WARNINGS` |
| `[ ]` | Prometheus targets yang aktif sudah `UP` |
| `[ ]` | Grafana dashboards bisa membaca data |
| `[ ]` | Alertmanager running dan config valid |
| `[ ]` | Internal network VM1, VM2, VM3 reachable |
| `[ ]` | Firewall change sudah approved |
| `[ ]` | Package offline tersedia untuk VM2 dan VM3 |

## 5. Network Matrix

| Source | Destination | Port | Purpose |
| --- | --- | --- | --- |
| VM1 Prometheus | VM2 VictoriaMetrics | `8428` | Remote write dan query datasource |
| VM1 Prometheus | VM3 Node exporter | `9100` | Server metrics scrape |
| VM1 Prometheus | VM3 Oracle exporter | `9161` | Oracle metrics scrape |
| VM1 Prometheus | VM3 MSSQL exporter | `9182` | MSSQL metrics scrape |
| VM3 Oracle exporter | Oracle listener | `1521` atau standar lokal | DB metrics query |
| VM3 MSSQL exporter | SQL Server listener | `1433` atau standar lokal | DB metrics query |
| Operator browser | VM1 Grafana | `3000` | Dashboard access |
| Operator browser | VM1 Prometheus | `9090` | Target, alert, and rule checks |
| Operator browser | VM1 Alertmanager | `9093` | Alert and silence management |

Firewall contoh:

```bash
# VM2
sudo firewall-cmd --permanent --add-port=8428/tcp
sudo firewall-cmd --reload

# VM3
sudo firewall-cmd --permanent --add-port=9100/tcp
sudo firewall-cmd --permanent --add-port=9161/tcp
sudo firewall-cmd --permanent --add-port=9182/tcp
sudo firewall-cmd --reload
```

## 6. Prepare VM2 Metrics Storage

Copy repository dan offline package ke VM2. Pastikan package VictoriaMetrics tersedia di:

```text
/monitoring/sources/tar/victoria-metrics-linux-amd64-*.tar.gz
```

Jalankan preparation step:

```bash
sudo ./01_prepare_vm.sh
```

Install VictoriaMetrics:

```bash
sudo ./02_install_victoriametrics.sh
```

Tuning runtime:

```bash
sudo vi /monitoring/victoriametrics/conf/victoriametrics.env
sudo systemctl restart victoriametrics
```

Validasi:

```bash
sudo systemctl status victoriametrics --no-pager
curl -fsS http://localhost:8428/health
curl -fsS http://VM2_IP:8428/health
```

## 7. Prepare VM3 Exporter Node

Copy repository dan offline package exporter ke VM3. Jalankan preparation step:

```bash
sudo ./01_prepare_vm.sh
```

Install exporter yang dibutuhkan:

```bash
sudo ./04_install_node_exporter.sh
sudo ./07_install_oracle_exporter.sh
sudo ./08_install_mssql_exporter.sh
```

Edit DB exporter credentials:

```bash
sudo vi /monitoring/exporters/oracle/oracle_exporter.env
sudo vi /monitoring/exporters/mssql/mssql_exporter.env
```

Penting: jangan gunakan `localhost` pada connection string kecuali database memang berada di VM3.

Oracle example:

```bash
DATA_SOURCE_NAME=oracle://monitoring_user:CHANGE_ME_STRONG_PASSWORD@ORACLE_DB_HOST:1521/service_name
```

MSSQL example:

```bash
DATA_SOURCE_NAME=sqlserver://monitoring_user:CHANGE_ME_STRONG_PASSWORD@MSSQL_DB_HOST:1433?database=master&encrypt=disable
```

Restart dan validasi exporter:

```bash
sudo systemctl restart node_exporter
sudo systemctl restart oracle_exporter
sudo systemctl restart mssql_exporter

curl -fsS http://localhost:9100/metrics
curl -fsS http://localhost:9161/metrics | grep '^oracle_up'
curl -fsS http://localhost:9182/metrics | grep '^mssql_up'
```

## 8. Update VM1 Inventory And Targets

Di VM1, update `inventory/targets.csv` supaya IP target untuk exporter mengarah ke VM3.

Contoh jika semua exporter berada di VM3:

```csv
host,ip,node,oracle,mssql,app,tier,owner
exporter-node-01,VM3_IP,yes,yes,yes,shared,prod,platform
```

Generate target files:

```bash
python3 scripts/generate_targets.py
```

Review generated files:

```text
config/targets/node_targets.yml
config/targets/oracle_targets.yml
config/targets/mssql_targets.yml
```

Expected target ports:

| File | Expected target |
| --- | --- |
| `node_targets.yml` | `VM3_IP:9100` |
| `oracle_targets.yml` | `VM3_IP:9161` |
| `mssql_targets.yml` | `VM3_IP:9182` |

Copy updated config ke Prometheus runtime path sesuai prosedur lokal, atau jalankan step Prometheus installer jika memang ingin refresh config dari repo:

```bash
sudo ./03_install_prometheus.sh
```

## 9. Update VM1 Prometheus Remote Write

Edit Prometheus config:

```bash
sudo vi /monitoring/prometheus/conf/prometheus.yml
```

Set `remote_write` ke VM2:

```yaml
remote_write:
  - url: "http://VM2_IP:8428/api/v1/write"
```

Pastikan Alertmanager tetap ke VM1:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - "localhost:9093"
```

Validate dan restart:

```bash
sudo /monitoring/prometheus/bin/promtool check config /monitoring/prometheus/conf/prometheus.yml
sudo /monitoring/prometheus/bin/promtool check rules /monitoring/prometheus/conf/alerts/*.yml
sudo systemctl restart prometheus
curl -fsS http://localhost:9090/-/ready
```

## 10. Update VM1 Grafana Datasource

Jika datasource provisioning mengikuti repo ini, Grafana membaca VictoriaMetrics sebagai Prometheus-compatible datasource. Untuk 3 VM, URL datasource harus mengarah ke VM2:

```yaml
url: http://VM2_IP:8428
```

File provisioning runtime biasanya berada di:

```text
/monitoring/grafana/provisioning/datasources/prometheus.yml
```

Restart dan validate:

```bash
sudo systemctl restart grafana-server
curl -fsS http://localhost:3000/api/health
```

## 11. Startup Order

Gunakan urutan ini saat maintenance atau restart total:

1. VM2: VictoriaMetrics
2. VM3: Node exporter, Oracle exporter, MSSQL exporter
3. VM1: Prometheus
4. VM1: Alertmanager
5. VM1: Grafana

## 12. Validation

### VM2 Storage

```bash
curl -fsS http://VM2_IP:8428/health
curl -G 'http://VM2_IP:8428/api/v1/query' --data-urlencode 'query=up'
curl -G 'http://VM2_IP:8428/api/v1/query' --data-urlencode 'query=oracle_up'
curl -G 'http://VM2_IP:8428/api/v1/query' --data-urlencode 'query=mssql_up'
```

### VM3 Exporters

```bash
curl -fsS http://VM3_IP:9100/metrics
curl -fsS http://VM3_IP:9161/metrics | grep '^oracle_up'
curl -fsS http://VM3_IP:9182/metrics | grep '^mssql_up'
```

### VM1 Prometheus

```bash
curl -fsS http://localhost:9090/-/ready
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=up'
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=prometheus_remote_storage_samples_pending'
```

Open:

```text
http://VM1_IP:9090/targets
http://VM1_IP:9090/alerts
http://VM1_IP:9093
http://VM1_IP:3000
```

Expected final state:

| VM | Expected state |
| --- | --- |
| VM1 | Prometheus, Grafana, Alertmanager running |
| VM2 | VictoriaMetrics running and receiving samples |
| VM3 | Node, Oracle, MSSQL exporters running |

## 13. Rollback Notes

Jika expand perlu dibatalkan:

1. Set Prometheus `remote_write` kembali ke local VictoriaMetrics endpoint lama.
2. Set Grafana datasource kembali ke local storage endpoint lama.
3. Restore target files ke target exporter lama.
4. Restart Prometheus dan Grafana.
5. Validasi `up`, `oracle_up`, `mssql_up`, dan dashboard.

Jangan stop service lama sebelum data path, datasource, dan target health sudah tervalidasi.

## 14. Final Checklist

| Status | Item |
| --- | --- |
| `[ ]` | VM2 VictoriaMetrics reachable dari VM1 |
| `[ ]` | VM3 exporter ports reachable dari VM1 |
| `[ ]` | VM3 exporter bisa reach Oracle dan MSSQL listener |
| `[ ]` | Prometheus `remote_write` mengarah ke VM2 |
| `[ ]` | Grafana datasource mengarah ke VM2 |
| `[ ]` | Prometheus targets `UP` |
| `[ ]` | VictoriaMetrics berisi `up`, `oracle_up`, dan `mssql_up` |
| `[ ]` | Grafana dashboard menampilkan data baru |
| `[ ]` | Alertmanager tetap menerima alert dari Prometheus VM1 |
| `[ ]` | Operator sudah menerima topology dan network matrix terbaru |
