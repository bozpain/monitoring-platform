# Oracle Monitoring Design

## Overview

This document describes the design of Oracle database monitoring using Prometheus, VictoriaMetrics, and Grafana.

The goal is to provide **DPA-like visibility** using lightweight, query-based metrics.

---

## Monitoring Philosophy

We focus on:

1. **Load**
2. **Wait**
3. **SQL**
4. **Blocking**

These represent the core pillars of database performance analysis.

---

## Architecture

```text
Oracle DB
   ↓
Oracle Exporter (SQL-based metrics)
   ↓
Prometheus (scraper)
   ↓
VictoriaMetrics (storage)
   ↓
Grafana (visualization)
```

---

## Architecture Diagram

<p align="center">
  <img src="images/oracle-monitoring-architecture.png" width="700"/>
</p>

---

## Core Metric Groups

### 1. Load Metrics

| Metric                   | Description       |
| ------------------------ | ----------------- |
| oracle_sessions_active   | Active sessions   |
| oracle_db_time_per_sec   | Database workload |
| oracle_cpu_usage_per_sec | CPU usage         |

Purpose:

- Measure real database load
- Detect spikes

---

### 2. Wait Analysis (ASH-like)

| Metric                     | Description             |
| -------------------------- | ----------------------- |
| oracle_ash_like_wait_class | Wait class distribution |
| oracle_ash_like_wait_event | Detailed wait events    |

Purpose:

- Identify bottlenecks
- Replace AWR/ASH basic insight

---

### 3. SQL Analysis

| Metric                     | Description        |
| -------------------------- | ------------------ |
| oracle_active_sql          | Active SQL         |
| oracle_top_sql_elapsed     | Heavy queries      |
| oracle_top_sql_buffer_gets | High logical reads |

Purpose:

- Identify problematic queries
- Support SQL tuning

---

### 4. Blocking Analysis

| Metric                  | Description                |
| ----------------------- | -------------------------- |
| oracle_sessions_blocked | Number of blocked sessions |
| oracle_blocking_tree    | Blocking relationships     |

Purpose:

- Detect locking issues
- Identify root cause session

---

## Data Flow

```text
Exporter → Prometheus → VictoriaMetrics → Grafana
```

---

## Grafana Dashboard Design

### Sections:

1. **Summary**
   - Active Sessions
   - DB Time
   - CPU
   - Blocking

2. **Wait Analysis**
   - Wait Class (Pie)
   - Top Wait Events

3. **SQL**
   - Active SQL
   - Top SQL

4. **Blocking**
   - Blocking Tree (Table)

---

## Key Concepts

### DB Time

Represents total database workload.

- High DB time = system under load
- Compare with CPU to detect bottleneck

---

### Wait Events

Primary method to diagnose performance issues.

Examples:

| Event                       | Meaning        |
| --------------------------- | -------------- |
| db file sequential read     | IO bottleneck  |
| log file sync               | commit latency |
| latch: cache buffers chains | contention     |

---

### Active Sessions

Indicates concurrent workload.

High value = potential pressure.

---

### Blocking Sessions

Critical for production issues.

- Even 1 blocking session can cause outage

---

## Alert Strategy

Alerts should be based on:

- Active sessions threshold
- Blocking sessions > 0
- High DB time
- Exporter down

---

## Limitations

- Not full replacement for AWR/ASH
- Snapshot-based, not historical session trace
- Limited SQL execution plan visibility

---

## Future Enhancements

- Multi-DB labeling
- Historical trend analysis
- Query text extraction
- Alert tuning
- Anomaly detection

---

## Summary

This design provides:

- Lightweight monitoring
- Real-time insight
- DPA-like capability without licensing cost

---
