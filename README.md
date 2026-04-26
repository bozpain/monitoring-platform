# 🟦 Internal Database Observability Platform

<p align="center">
  Centralized observability for databases and infrastructure — scalable, lightweight, and fully open-source
</p>

<p align="center">
  <img src="docs/architecture.png" width="850"/>
</p>

---

## ✨ Overview

A centralized platform that provides full visibility across:

- RDBMS Databases
- NoSQL Databases
- Infrastructure (VM / OS / Servers)

Designed to deliver real-time monitoring, intelligent alerting, and unified dashboards across all environments.

---

## 🚀 Key Capabilities

| Capability               | Description                                     |
| ------------------------ | ----------------------------------------------- |
| 🔍 Fleet Visibility      | Single-pane-of-glass monitoring for all systems |
| 📊 Performance Insights  | Deep metrics for faster troubleshooting         |
| 🧠 Smart Alerting        | Context-aware alerts (app + tier based)         |
| ⚙️ Auto Discovery        | CSV-driven dynamic target generation            |
| 📦 Scalable Architecture | Supports 500+ instances                         |
| 🔒 Offline Ready         | No internet dependency                          |

---

## 🏗️ Architecture

<p align="center">
  <img src="docs/images/architecture.png" width="900"/>
</p>

### Flow

1. Metrics collected from databases and servers
2. Processed by Prometheus
3. Stored in VictoriaMetrics
4. Visualized via Grafana
5. Alerts sent via Alertmanager (Email)

---

## 📊 Dashboards

### 🧭 Fleet Overview

- Total systems
- Availability %
- Active alerts
- Down instances

### 🗄️ Database Monitoring

- Performance metrics
- Session & blocking analysis
- Capacity tracking

### 🖥️ Infrastructure

- CPU / Memory
- Disk usage
- Network / IO

---

## 📸 Screenshots

Dashboard previews will be added in the next update.

---

## ⚙️ Deployment

```bash
sudo ./deploy_all.sh
```

---

## 📁 Inventory & Auto Discovery

Manage targets:

```bash
inventory/targets.csv
```

Generate configs:

```bash
python scripts/generate_targets.py
```

Output:

```bash
config/targets/
```

---

## 🚨 Alerting

- Centralized via Alertmanager
- Email notifications (SMTP)
- Context included:
  - Application
  - Tier (SIT / UAT)
  - Severity
  - Instance

### Example

```
[CRITICAL][CORE-BANKING][SIT] High Resource Usage
```

---

## 📈 Scalability

- 500+ database instances
- Multi-application environments
- Cluster & distributed systems

---

## 🧠 Business Value

- Faster incident detection
- Reduced downtime risk
- Improved DBA productivity
- Standardized monitoring
- Better operational visibility

---

## 🔮 Roadmap

- AI anomaly detection
- Root cause analysis
- Auto remediation
- Multi-channel alerting

---

## 👨‍💻 Maintained by

**DBA Team**

---

<p align="center">
  Built with open-source technologies • Designed for scale • Made for operations
</p>
