# Monitoring Platform

Lightweight, offline-ready database monitoring platform built with Prometheus, VictoriaMetrics, Grafana, Alertmanager, and database exporters.

---

## Overview

This platform is designed to:

- Monitor operating system and databases (Oracle, MSSQL, PostgreSQL, MongoDB)
- Run in restricted environments (no internet access)
- Use a centralized metric storage (VictoriaMetrics)
- Be fully deployable via scripts

---

## Architecture

```text
Exporters
  ├── Node Exporter
  ├── Oracle Exporter
  ├── MSSQL Exporter
  ├── PostgreSQL Exporter
  └── MongoDB Exporter
        ↓
Prometheus (scraper)
        ↓ remote_write
VictoriaMetrics (storage)
        ↓
Grafana (visualization)
        ↓
Alertmanager (alerting)
```

---

## Key Components

| Component       | Description               |
| --------------- | ------------------------- |
| Prometheus      | Metric scraper            |
| VictoriaMetrics | Time-series database      |
| Grafana         | Dashboard & visualization |
| Alertmanager    | Alert routing             |
| Exporters       | Metric collectors         |

---

## VM Directory Standard

All monitoring components must follow this structure:

```text
/monitoring/
├── prometheus/
├── victoriametrics/
├── grafana/
├── alertmanager/
├── exporters/
├── data/
├── logs/
└── sources/
```

---

## Deployment

This project supports:

### One Command Deployment

```bash
./deploy_all.sh
```

### Manual Deployment

```bash
./01_prepare_vm.sh
./02_install_victoriametrics.sh
./03_install_prometheus.sh
./04_install_node_exporter.sh
./05_install_grafana.sh
./06_install_alertmanager.sh
./07_install_oracle_exporter.sh
```

---

## Deployment Guide

For full step-by-step instructions (recommended for operators):

👉 See:

```text
deployment_plan.md
```

---

## Data Flow

```text
Exporter → Prometheus → VictoriaMetrics → Grafana
                              ↓
                        Alertmanager
```

---

## Default Ports

| Component       | Port |
| --------------- | ---- |
| Grafana         | 3000 |
| Prometheus      | 9090 |
| VictoriaMetrics | 8428 |
| Alertmanager    | 9093 |
| Node Exporter   | 9100 |
| Oracle Exporter | 9161 |

---

## Notes

- Prometheus is used only for scraping (no long-term storage)
- VictoriaMetrics is the primary storage backend
- Grafana reads data from VictoriaMetrics (Prometheus-compatible API)
- Oracle exporter requires manual configuration before activation

---

## Git Policy

Do NOT commit:

- environment files (`*.env`)
- binary files (`*.tar.gz`, `*.rpm`)
- monitoring data (`/data`)
- logs (`/logs`)
- credentials / passwords

---

## Status

This project provides:

- Full offline deployment capability
- Modular architecture
- Scalable monitoring foundation
- Extendable for advanced database performance analysis (DPA-like)

---
