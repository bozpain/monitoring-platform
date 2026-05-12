<div align="center">

<img src="docs/images/platform-architecture.svg" alt="Internal Database Observability Platform architecture" width="100%">

<h1>Internal Database Observability Platform</h1>

<p><strong>Platform observability internal untuk database, server, alerting, dan dashboard operasional.</strong></p>

<img src="https://img.shields.io/badge/Prometheus-Scrape%20%26%20Rules-E6522C?style=for-the-badge&logo=prometheus&logoColor=white" alt="Prometheus">
<img src="https://img.shields.io/badge/VictoriaMetrics-Long%20Retention-13A1DC?style=for-the-badge&logo=victoriametrics&logoColor=white" alt="VictoriaMetrics">
<img src="https://img.shields.io/badge/Grafana-Dashboards-F46800?style=for-the-badge&logo=grafana&logoColor=white" alt="Grafana">
<img src="https://img.shields.io/badge/Alertmanager-Notifications-00A98F?style=for-the-badge&logo=prometheus&logoColor=white" alt="Alertmanager">

</div>

## Ringkasan

Repository ini menyediakan installer dan konfigurasi untuk membangun monitoring stack single-VM yang bisa berjalan di environment internal atau offline. Fokusnya adalah visibility untuk Linux host, Oracle Database, Microsoft SQL Server, Prometheus health, VictoriaMetrics storage, Grafana, dan Alertmanager.

Semua instruksi teknis deployment, tuning, credential exporter, firewall, validasi, dan troubleshooting sekarang dipusatkan di:

<div align="center">

<a href="docs/deployment_guide.md"><img src="https://img.shields.io/badge/OPEN-DEPLOYMENT%20GUIDE-2563EB?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Buka Deployment Guide"></a>
<a href="docs/operator_handover.md"><img src="https://img.shields.io/badge/OPERATOR-HANDOVER-7C3AED?style=for-the-badge&logo=bookstack&logoColor=white" alt="Operator Handover"></a>
<a href="docs/alert_catalog.md"><img src="https://img.shields.io/badge/ALERT-CATALOG-DC2626?style=for-the-badge&logo=prometheus&logoColor=white" alt="Alert Catalog"></a>

</div>

## Apa Yang Dibangun

| Area | Komponen | Hasil |
| --- | --- | --- |
| Metrics collection | Node exporter, Oracle exporter, MSSQL exporter | Metrik server dan database dikumpulkan dari target internal |
| Scrape and rules | Prometheus | Service discovery, scrape, recording rules, alert rules |
| Long retention | VictoriaMetrics | Penyimpanan metrik jangka panjang dengan endpoint Prometheus-compatible |
| DPA repository | PostgreSQL local, Oracle DPA sampler, MSSQL DPA sampler | Mini-ASH/request samples, SQL text, plan history, advisory, dan change correlation |
| Visualization | Grafana | Dashboard fleet, node, Oracle, dan MSSQL |
| Notification | Alertmanager | Routing alert, grouping, repeat interval, dan email notification |
| Automation | Shell installer, inventory generator, systemd units | Deployment repeatable dari repository root |

## Arsitektur

Alur singkat:

1. Exporter membuka endpoint metrics untuk server, Oracle, dan MSSQL.
2. Prometheus membaca target dari file service discovery yang dihasilkan dari inventory.
3. Prometheus mengirim data jangka panjang ke VictoriaMetrics.
4. DPA sampler menulis SQL detail dan mini-ASH ke PostgreSQL lokal.
5. Grafana membaca datasource dari VictoriaMetrics dan DPA Repository.
6. Alert rules di Prometheus diteruskan ke Alertmanager.

## Highlight

| Capability | Status |
| --- | --- |
| Offline package layout | Tersedia |
| Single-VM deployment flow | Tersedia |
| 3-VM expansion guide | Tersedia |
| Grafana provisioning | Tersedia |
| Prometheus alert rules | Tersedia |
| DB exporter credential templates | Tersedia |
| PostgreSQL DPA repository | Tersedia |
| SQL text/plan drilldown | Tersedia |
| Health check script | Tersedia |
| Operator handover checklist | Tersedia |

## Dokumentasi Utama

| Dokumen | Isi |
| --- | --- |
| [Deployment Guide](docs/deployment_guide.md) | Runbook teknis utama untuk install, tuning, validasi, dan troubleshooting |
| [Operator Handover](docs/operator_handover.md) | DB grants, manifest offline package, firewall, SELinux, dan validasi metrik |
| [Deployment Guide Expand](docs/deployment_guide_expand.md) | Panduan ekspansi 3 VM untuk memisahkan control plane, storage, dan exporter node |
| [DPA Metric Catalog](docs/dpa_metric_catalog.md) | Coverage metrik DPA-style untuk node, Oracle, dan MSSQL |
| [Oracle DPA Repository](docs/dpa_repository_design.md) | PostgreSQL repository, sampler, SQL drilldown, plan history, advisory, dan SLO weighting |
| [Oracle Monitoring Tiers](docs/oracle_monitoring_tiers.md) | Decision matrix exporter-only vs exporter + DPA Repository |
| [Oracle Runbooks](docs/runbooks/oracle) | Panduan tindakan untuk alert/advisory Oracle utama |
| [MSSQL Monitoring Tiers](docs/mssql_monitoring_tiers.md) | Decision matrix exporter-only vs exporter + DPA Repository untuk SQL Server |
| [MSSQL Runbooks](docs/runbooks/mssql) | Panduan tindakan untuk blocking, waits, plan regression, I/O, memory, dan query SQL Server |
| [Alert Catalog](docs/alert_catalog.md) | Threshold default dan arti operasional alert |
| [Offline Manifest Template](docs/offline_package_manifest.example.csv) | Template versi package dan checksum yang disetujui |

## Repository Map

| Path | Fungsi |
| --- | --- |
| `deploy_all.sh` | Orkestrasi deployment end-to-end |
| `01_prepare_vm.sh` sampai `10_install_postgres_dpa.sh` | Installer per tahap, DPA repository, dan health check |
| `inventory/targets.csv` | Source inventory host yang dimonitor |
| `scripts/generate_targets.py` | Generator target Prometheus `file_sd` |
| `scripts/install_dpa_target.sh` | Helper onboarding target Oracle DPA dari template inventory |
| `scripts/install_mssql_dpa_target.sh` | Helper onboarding target MSSQL DPA dari template inventory |
| `config/prometheus.yml` | Scrape config, alerting, dan remote write |
| `config/alerts/` | Recording rules dan alert rules |
| `config/dpa/` | PostgreSQL DPA schema, sampler env, dan Python requirements |
| `config/targets/` | Output target Prometheus hasil generator |
| `config/*/*.env.example` | Template runtime tuning per service |
| `grafana/provisioning/` | Datasource dan dashboard provisioning |
| `grafana/dashboards/` | Dashboard JSON untuk fleet, node, Oracle, dan MSSQL |
| `scripts/dpa_sampler.py` | Oracle mini-ASH, SQL snapshot, plan snapshot, blocking, ops signal, advisory sampler |
| `scripts/mssql_dpa_sampler.py` | MSSQL request sample, SQL snapshot, plan XML, blocking, ops signal, advisory sampler |
| `systemd/` | Unit service yang diinstall ke server |
| `docs/images/` | Diagram arsitektur dan aset dokumentasi |

## Dashboard Coverage

| Dashboard family | Fokus |
| --- | --- |
| Fleet | Overview platform dan health target |
| Node | CPU, memory, filesystem, IO, network, dan capacity |
| Oracle | Overview, tablespace, SQL activity, blocking, RAC, ASM, performance |
| MSSQL | Overview, capacity, sessions, blocking, performance, dan DPA repository drilldown |

## Deployment

Mulai dari [docs/deployment_guide.md](docs/deployment_guide.md). Guide tersebut berisi semua langkah teknis mulai dari persiapan offline package, inventory, install, credential exporter, alert email, firewall, tuning, sampai validasi akhir.

## Ownership Notes

Platform ini dirancang untuk handover operasional yang jelas:

| Role | Biasanya menangani |
| --- | --- |
| Platform engineer | VM, package, systemd, Prometheus, VictoriaMetrics, Grafana, Alertmanager |
| DBA Oracle | User monitoring, grants, service name, dan validasi `oracle_up` |
| DBA MSSQL | Login monitoring, permissions, TLS policy, dan validasi `mssql_up` |
| NOC or operator | Dashboard, alert response, escalation, dan health check berkala |
