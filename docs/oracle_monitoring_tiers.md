# Oracle Monitoring Tiers

Use two monitoring tiers so every Oracle database gets broad health coverage while only selected databases get deeper diagnostic sampling.

## Tier 1: Exporter Only

Use for most non-critical databases or stable systems.

Data path:

```text
oracle_exporter -> Prometheus/VictoriaMetrics -> Grafana/Alertmanager
```

Coverage:

- availability and exporter health
- sessions and blocking count
- wait class/event snapshots
- tablespace, temp, FRA capacity
- RAC/ASM status when grants exist
- top SQL metrics suitable for dashboards and alerts

Choose exporter-only when:

| Situation | Reason |
| --- | --- |
| DEV/SIT/temporary DB | Low operational risk |
| DB owner does not approve SQL text collection | DPA repository stores SQL text |
| Storage budget is tight | Prometheus metrics are cheaper than mini-ASH history |
| Only availability/capacity alerting is needed | DPA would add little value |

## Tier 2: Exporter + DPA Repository

Use for critical or actively investigated databases.

Data path:

```text
oracle_exporter -> Prometheus/VictoriaMetrics -> Grafana/Alertmanager
Oracle DB -> dpa_sampler@<target>.timer -> PostgreSQL dpa_repository -> Grafana
```

Coverage:

- mini-ASH historical samples
- SQL text snapshots
- plan history and plan diff signatures
- blocking history
- Data Guard, RMAN, scheduler, stale stats, unusable index, invalid object signals
- change correlation
- advisory queue
- app SLO and impact weighting

Choose DPA when:

| Situation | Reason |
| --- | --- |
| Production revenue/core system | Faster root-cause analysis |
| Repeated performance incidents | Historical wait and SQL evidence |
| Plan instability is suspected | Plan hash and plan row history |
| App team needs SQL/module attribution | DPA stores module, service, machine, SQL ID, and SQL text |
| DBA wants post-incident timeline | Mini-ASH and blocking episodes preserve the timeline |

## Inventory Flag

Use `oracle_dpa` in `inventory/targets.csv`:

```csv
host,ip,node,oracle,oracle_dpa,oracle_service,mssql,app,tier,owner
db-vm-01,10.243.176.250,yes,yes,yes,service_name,no,core-banking,sit,team-core
db-vm-03,10.243.176.252,yes,yes,no,service_name,yes,etl,sit,team-data
```

`oracle=yes, oracle_dpa=no` means exporter-only.

`oracle=yes, oracle_dpa=yes` means exporter plus a generated DPA sampler env template under:

```text
config/dpa/targets/<host>.env.example
```

Install the generated template on the monitoring VM:

```bash
sudo scripts/install_dpa_target.sh db-vm-01
sudo vi /monitoring/dpa/conf/db-vm-01.env
sudo systemctl enable --now dpa_sampler@db-vm-01.timer
```

## Approval Checklist

Before enabling DPA for a database:

| Check | Why |
| --- | --- |
| DBA approves dynamic view grants | Sampler reads session, SQL, plan, and operational metadata |
| SQL text collection is approved | SQL text can contain sensitive literals if applications do not bind variables |
| Repository storage is sized | Mini-ASH and plan snapshots grow with workload |
| App owner is mapped | Impact scoring and escalation depend on ownership |
| Retention is agreed | Default is 35 days |

If any item is not approved, keep the database on exporter-only until the gap is resolved.

## SQL Text Handling

DPA-enabled databases store SQL text in PostgreSQL. Treat that repository as sensitive operational data:

- Prefer DPA only for approved production or high-value troubleshooting targets.
- Verify applications use bind variables where possible.
- Restrict Grafana/DPA Repository access to approved DBA and operator groups.
- Avoid pasting raw SQL text into tickets when it contains sensitive literals.
- Use exporter-only mode when SQL text collection is not approved.
