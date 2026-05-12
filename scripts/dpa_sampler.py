#!/usr/bin/env python3
"""
Oracle mini-ASH and SQL snapshot sampler for the local PostgreSQL DPA repository.

The sampler intentionally keeps detailed SQL text, plan rows, and session samples
out of Prometheus labels. Prometheus remains the fast metric path; PostgreSQL is
the diagnostic drilldown store.
"""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


def load_env_file(path: str | None) -> None:
    if not path:
        return
    env_path = Path(path)
    if not env_path.exists():
        raise FileNotFoundError(f"env file not found: {env_path}")

    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or not value.strip():
        return default
    return int(value)


def require_env(name: str) -> str:
    value = os.getenv(name)
    if not value or "CHANGE_ME" in value:
        raise RuntimeError(f"{name} is not configured")
    return value


def import_drivers():
    try:
        import oracledb  # type: ignore
    except ImportError as exc:
        raise RuntimeError(
            "python-oracledb is not installed. Install wheels from "
            "/monitoring/sources/python or OS packages, then restart dpa_sampler."
        ) from exc

    try:
        import psycopg2  # type: ignore
    except ImportError as exc:
        raise RuntimeError(
            "psycopg2 is not installed. Install psycopg2/psycopg2-binary, "
            "then restart dpa_sampler."
        ) from exc

    return oracledb, psycopg2


def rows_as_dicts(cursor) -> list[dict[str, Any]]:
    columns = [col[0].lower() for col in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def oracle_query(conn, sql: str, params: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    with conn.cursor() as cur:
        cur.execute(sql, params or {})
        return rows_as_dicts(cur)


def pg_executemany(conn, sql: str, rows: Iterable[tuple[Any, ...]]) -> int:
    data = list(rows)
    if not data:
        return 0
    with conn.cursor() as cur:
        cur.executemany(sql, data)
    return len(data)


def truncate(value: Any, limit: int) -> Any:
    if value is None:
        return None
    text = str(value)
    return text[:limit]


def get_db_identity(ora_conn, configured_name: str) -> dict[str, Any]:
    rows = oracle_query(
        ora_conn,
        """
        SELECT
          d.name AS db_name,
          NVL(d.db_unique_name, d.name) AS db_unique_name,
          d.platform_name AS platform_name,
          i.inst_id AS inst_id,
          i.instance_name AS instance_name,
          i.host_name AS host_name,
          i.version AS version
        FROM v$database d
        CROSS JOIN gv$instance i
        WHERE i.inst_id = USERENV('INSTANCE')
        """,
    )
    if not rows:
        return {"db_unique_name": configured_name}
    row = rows[0]
    if configured_name:
        row["db_unique_name"] = configured_name
    return row


def upsert_db_instance(pg_conn, identity: dict[str, Any]) -> None:
    with pg_conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO dpa.db_instance (
              db_unique_name, db_name, instance_name, inst_id, host_name, version, platform_name, last_seen
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, now())
            ON CONFLICT (db_unique_name) DO UPDATE SET
              db_name = EXCLUDED.db_name,
              instance_name = EXCLUDED.instance_name,
              inst_id = EXCLUDED.inst_id,
              host_name = EXCLUDED.host_name,
              version = EXCLUDED.version,
              platform_name = EXCLUDED.platform_name,
              last_seen = now()
            """,
            (
                identity.get("db_unique_name"),
                identity.get("db_name"),
                identity.get("instance_name"),
                identity.get("inst_id"),
                identity.get("host_name"),
                identity.get("version"),
                identity.get("platform_name"),
            ),
        )


def sample_ash(ora_conn, pg_conn, identity: dict[str, Any], sample_seconds: int) -> int:
    rows = oracle_query(
        ora_conn,
        """
        SELECT
          s.inst_id,
          s.con_id,
          NVL(c.name, 'CDB$ROOT') AS pdb_name,
          s.sid,
          s.serial# AS serial_no,
          NVL(s.username, 'UNKNOWN') AS username,
          s.status,
          s.state AS session_state,
          NVL(s.sql_id, 'UNKNOWN') AS sql_id,
          q.plan_hash_value,
          NVL(s.wait_class, 'UNKNOWN') AS wait_class,
          SUBSTR(NVL(s.event, 'ON CPU'), 1, 120) AS event,
          SUBSTR(NVL(s.module, 'UNKNOWN'), 1, 80) AS module,
          SUBSTR(NVL(s.action, 'UNKNOWN'), 1, 80) AS action,
          SUBSTR(NVL(s.service_name, 'UNKNOWN'), 1, 80) AS service_name,
          SUBSTR(NVL(s.machine, 'UNKNOWN'), 1, 120) AS machine,
          SUBSTR(NVL(s.program, 'UNKNOWN'), 1, 120) AS program,
          s.blocking_session
        FROM gv$session s
        LEFT JOIN gv$sql q ON s.inst_id = q.inst_id AND s.sql_id = q.sql_id AND s.sql_child_number = q.child_number
        LEFT JOIN v$containers c ON s.con_id = c.con_id
        WHERE s.status = 'ACTIVE'
        AND s.type = 'USER'
        """,
    )
    now = datetime.now(timezone.utc)
    db_unique_name = identity["db_unique_name"]
    instance_name = identity.get("instance_name")
    return pg_executemany(
        pg_conn,
        """
        INSERT INTO dpa.ash_sample (
          sample_time, db_unique_name, inst_id, instance_name, con_id, pdb_name, sid,
          serial_no, username, status, session_state, sql_id, plan_hash_value,
          wait_class, event, module, action, service_name, machine, program,
          blocking_session, sample_seconds
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            (
                now,
                db_unique_name,
                row.get("inst_id"),
                instance_name,
                row.get("con_id"),
                row.get("pdb_name"),
                row.get("sid"),
                row.get("serial_no"),
                truncate(row.get("username"), 128),
                row.get("status"),
                row.get("session_state"),
                row.get("sql_id"),
                row.get("plan_hash_value"),
                row.get("wait_class"),
                truncate(row.get("event"), 120),
                truncate(row.get("module"), 80),
                truncate(row.get("action"), 80),
                truncate(row.get("service_name"), 80),
                truncate(row.get("machine"), 120),
                truncate(row.get("program"), 120),
                row.get("blocking_session"),
                sample_seconds,
            )
            for row in rows
        ),
    )


def snapshot_sql(ora_conn, pg_conn, identity: dict[str, Any], top_n: int) -> int:
    rows = oracle_query(
        ora_conn,
        """
        SELECT *
        FROM (
          SELECT
            q.inst_id,
            q.con_id,
            NVL(c.name, 'CDB$ROOT') AS pdb_name,
            sql_id,
            plan_hash_value,
            parsing_schema_name,
            SUBSTR(NVL(module, 'UNKNOWN'), 1, 80) AS module,
            SUBSTR(NVL(action, 'UNKNOWN'), 1, 80) AS action,
            SUBSTR(NVL(service, 'UNKNOWN'), 1, 80) AS service_name,
            last_active_time,
            executions,
            elapsed_time AS elapsed_time_us,
            cpu_time AS cpu_time_us,
            buffer_gets,
            disk_reads,
            rows_processed,
            parse_calls,
            version_count,
            DBMS_LOB.SUBSTR(sql_fulltext, 4000, 1) AS sql_text
          FROM gv$sql q
          LEFT JOIN v$containers c ON q.con_id = c.con_id
          WHERE q.sql_id IS NOT NULL
          AND q.last_active_time >= SYSDATE - (1 / 24)
          ORDER BY elapsed_time DESC
        )
        WHERE rownum <= :top_n
        """,
        {"top_n": top_n},
    )
    now = datetime.now(timezone.utc)
    db_unique_name = identity["db_unique_name"]
    return pg_executemany(
        pg_conn,
        """
        INSERT INTO dpa.sql_snapshot (
          snapshot_time, db_unique_name, inst_id, con_id, pdb_name, sql_id,
          plan_hash_value, parsing_schema_name, module, action, service_name,
          last_active_time, executions, elapsed_time_us, cpu_time_us, buffer_gets,
          disk_reads, rows_processed, parse_calls, version_count, sql_text
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            (
                now,
                db_unique_name,
                row.get("inst_id"),
                row.get("con_id"),
                row.get("pdb_name"),
                row.get("sql_id"),
                row.get("plan_hash_value"),
                truncate(row.get("parsing_schema_name"), 128),
                truncate(row.get("module"), 80),
                truncate(row.get("action"), 80),
                truncate(row.get("service_name"), 80),
                row.get("last_active_time"),
                row.get("executions"),
                row.get("elapsed_time_us"),
                row.get("cpu_time_us"),
                row.get("buffer_gets"),
                row.get("disk_reads"),
                row.get("rows_processed"),
                row.get("parse_calls"),
                row.get("version_count"),
                row.get("sql_text"),
            )
            for row in rows
        ),
    )


def snapshot_plans(ora_conn, pg_conn, identity: dict[str, Any], top_n: int) -> int:
    rows = oracle_query(
        ora_conn,
        """
        SELECT
          p.inst_id,
          p.con_id,
          NVL(c.name, 'CDB$ROOT') AS pdb_name,
          p.sql_id,
          p.plan_hash_value,
          p.child_number,
          p.id,
          p.parent_id,
          p.operation,
          p.options,
          p.object_owner,
          p.object_name,
          p.object_type,
          p.cardinality,
          p.bytes,
          p.cost,
          p.optimizer
        FROM gv$sql_plan p
        LEFT JOIN v$containers c ON p.con_id = c.con_id
        WHERE p.sql_id IN (
          SELECT sql_id
          FROM (
            SELECT sql_id, SUM(elapsed_time) AS elapsed_time
            FROM gv$sql
            WHERE sql_id IS NOT NULL
            AND last_active_time >= SYSDATE - (1 / 24)
            GROUP BY sql_id
            ORDER BY SUM(elapsed_time) DESC
          )
          WHERE rownum <= :top_n
        )
        ORDER BY p.sql_id, p.plan_hash_value, p.child_number, p.id
        """,
        {"top_n": top_n},
    )
    now = datetime.now(timezone.utc)
    db_unique_name = identity["db_unique_name"]
    return pg_executemany(
        pg_conn,
        """
        INSERT INTO dpa.sql_plan_snapshot (
          snapshot_time, db_unique_name, inst_id, con_id, pdb_name, sql_id,
          plan_hash_value, child_number, id, parent_id, operation, options,
          object_owner, object_name, object_type, cardinality, bytes, cost, optimizer
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            (
                now,
                db_unique_name,
                row.get("inst_id"),
                row.get("con_id"),
                row.get("pdb_name"),
                row.get("sql_id"),
                row.get("plan_hash_value"),
                row.get("child_number"),
                row.get("id"),
                row.get("parent_id"),
                row.get("operation"),
                row.get("options"),
                row.get("object_owner"),
                row.get("object_name"),
                row.get("object_type"),
                row.get("cardinality"),
                row.get("bytes"),
                row.get("cost"),
                row.get("optimizer"),
            )
            for row in rows
        ),
    )


def snapshot_blocking(ora_conn, pg_conn, identity: dict[str, Any]) -> int:
    rows = oracle_query(
        ora_conn,
        """
        SELECT
          s.inst_id,
          s.con_id,
          NVL(c.name, 'CDB$ROOT') AS pdb_name,
          b.sid AS blocking_sid,
          s.sid AS blocked_sid,
          NVL(b.sql_id, 'UNKNOWN') AS blocking_sql_id,
          NVL(s.sql_id, 'UNKNOWN') AS blocked_sql_id,
          NVL(b.username, 'UNKNOWN') AS blocking_user,
          NVL(s.username, 'UNKNOWN') AS blocked_user,
          NVL(s.wait_class, 'UNKNOWN') AS wait_class,
          SUBSTR(NVL(s.event, 'UNKNOWN'), 1, 120) AS event,
          SUBSTR(NVL(s.module, 'UNKNOWN'), 1, 80) AS module,
          SUBSTR(NVL(s.machine, 'UNKNOWN'), 1, 120) AS machine
        FROM gv$session s
        JOIN gv$session b ON s.inst_id = b.inst_id AND s.blocking_session = b.sid
        LEFT JOIN v$containers c ON s.con_id = c.con_id
        WHERE s.blocking_session IS NOT NULL
        """,
    )
    now = datetime.now(timezone.utc)
    db_unique_name = identity["db_unique_name"]
    return pg_executemany(
        pg_conn,
        """
        INSERT INTO dpa.blocking_episode (
          sample_time, db_unique_name, inst_id, con_id, pdb_name, blocking_sid,
          blocked_sid, blocking_sql_id, blocked_sql_id, blocking_user, blocked_user,
          wait_class, event, module, machine
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            (
                now,
                db_unique_name,
                row.get("inst_id"),
                row.get("con_id"),
                row.get("pdb_name"),
                row.get("blocking_sid"),
                row.get("blocked_sid"),
                row.get("blocking_sql_id"),
                row.get("blocked_sql_id"),
                row.get("blocking_user"),
                row.get("blocked_user"),
                row.get("wait_class"),
                truncate(row.get("event"), 120),
                truncate(row.get("module"), 80),
                truncate(row.get("machine"), 120),
            )
            for row in rows
        ),
    )


def snapshot_change_events(ora_conn, pg_conn, identity: dict[str, Any], lookback_minutes: int) -> int:
    rows = oracle_query(
        ora_conn,
        """
        SELECT
          last_ddl_time AS event_time,
          TO_NUMBER(SYS_CONTEXT('USERENV', 'CON_ID')) AS con_id,
          'UNKNOWN' AS pdb_name,
          'DBA_OBJECTS' AS source,
          'DDL_CHANGE' AS event_type,
          owner AS object_owner,
          object_name,
          object_type,
          status AS details
        FROM dba_objects
        WHERE last_ddl_time >= SYSDATE - (:lookback_minutes / 1440)
        AND owner NOT IN ('SYS', 'SYSTEM')
        """,
        {"lookback_minutes": lookback_minutes},
    )
    db_unique_name = identity["db_unique_name"]
    count = 0
    with pg_conn.cursor() as cur:
        for row in rows:
            cur.execute(
                """
                INSERT INTO dpa.change_event (
                  event_time, db_unique_name, con_id, pdb_name, source, event_type,
                  object_owner, object_name, object_type, details
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT DO NOTHING
                """,
                (
                    row.get("event_time"),
                    db_unique_name,
                    row.get("con_id"),
                    row.get("pdb_name"),
                    row.get("source"),
                    row.get("event_type"),
                    row.get("object_owner"),
                    row.get("object_name"),
                    row.get("object_type"),
                    row.get("details"),
                ),
            )
            count += cur.rowcount
    return count


def snapshot_object_stats(ora_conn, pg_conn, identity: dict[str, Any]) -> int:
    rows = oracle_query(
        ora_conn,
        """
        SELECT *
        FROM (
          SELECT
            con_id,
            owner,
            object_name,
            subobject_name,
            object_type,
            statistic_name AS metric_name,
            value
          FROM v$segment_statistics
          WHERE statistic_name IN (
            'logical reads', 'physical reads', 'buffer busy waits', 'ITL waits', 'row lock waits'
          )
          ORDER BY value DESC
        )
        WHERE rownum <= 100
        """,
    )
    now = datetime.now(timezone.utc)
    db_unique_name = identity["db_unique_name"]
    return pg_executemany(
        pg_conn,
        """
        INSERT INTO dpa.object_stats_snapshot (
          sample_time, db_unique_name, con_id, pdb_name, owner, object_name,
          object_type, metric_name, value
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            (
                now,
                db_unique_name,
                row.get("con_id"),
                "UNKNOWN",
                row.get("owner"),
                row.get("object_name"),
                row.get("object_type"),
                row.get("metric_name"),
                row.get("value"),
            )
            for row in rows
        ),
    )


def snapshot_oracle_ops(ora_conn, pg_conn, identity: dict[str, Any]) -> int:
    now = datetime.now(timezone.utc)
    db_unique_name = identity["db_unique_name"]
    inst_id = identity.get("inst_id")
    queries = [
        (
            "invalid-objects",
            """
            SELECT TO_NUMBER(SYS_CONTEXT('USERENV', 'CON_ID')) AS con_id, 'object-health' AS category, 'invalid_objects' AS metric_name,
                   owner AS object_owner, object_type AS object_name, status,
                   COUNT(*) AS value, object_type AS details
            FROM dba_objects
            WHERE status <> 'VALID'
            AND owner NOT IN ('SYS', 'SYSTEM')
            GROUP BY owner, object_type, status
            """,
        ),
        (
            "unusable-indexes",
            """
            SELECT NULL AS con_id, 'index-health' AS category, 'unusable_indexes' AS metric_name,
                   owner AS object_owner, index_name AS object_name, status,
                   1 AS value, table_name AS details
            FROM dba_indexes
            WHERE status = 'UNUSABLE'
            """,
        ),
        (
            "stale-stats",
            """
            SELECT NULL AS con_id, 'optimizer-stats' AS category, 'stale_table_stats' AS metric_name,
                   owner AS object_owner, table_name AS object_name, stale_stats AS status,
                   1 AS value, 'num_rows=' || NVL(TO_CHAR(num_rows), 'unknown') AS details
            FROM dba_tab_statistics
            WHERE stale_stats = 'YES'
            AND owner NOT IN ('SYS', 'SYSTEM')
            """,
        ),
        (
            "scheduler-failures",
            """
            SELECT NULL AS con_id, 'scheduler' AS category, 'failed_jobs_24h' AS metric_name,
                   owner AS object_owner, job_name AS object_name, status,
                   1 AS value, additional_info AS details
            FROM dba_scheduler_job_run_details
            WHERE status <> 'SUCCEEDED'
            AND log_date >= SYSTIMESTAMP - INTERVAL '24' HOUR
            """,
        ),
        (
            "rman-backup-age",
            """
            SELECT NULL AS con_id, 'backup' AS category, 'latest_rman_backup_age_hours' AS metric_name,
                   NULL AS object_owner, input_type AS object_name, status,
                   ROUND((SYSDATE - MAX(end_time)) * 24, 2) AS value,
                   'latest_end_time=' || TO_CHAR(MAX(end_time), 'YYYY-MM-DD HH24:MI:SS') AS details
            FROM v$rman_backup_job_details
            WHERE end_time IS NOT NULL
            GROUP BY input_type, status
            """,
        ),
        (
            "data-guard-lag",
            """
            SELECT NULL AS con_id, 'dataguard' AS category, name AS metric_name,
                   NULL AS object_owner, NULL AS object_name, unit AS status,
                   NULL AS value, value AS details
            FROM v$dataguard_stats
            WHERE name IN ('transport lag', 'apply lag', 'apply finish time')
            """,
        ),
    ]
    total = 0
    with pg_conn.cursor() as cur:
        for _, sql in queries:
            try:
                rows = oracle_query(ora_conn, sql)
            except Exception:
                continue
            for row in rows:
                cur.execute(
                    """
                    INSERT INTO dpa.oracle_ops_snapshot (
                      sample_time, db_unique_name, inst_id, con_id, pdb_name, category,
                      metric_name, object_owner, object_name, status, value, details
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        now,
                        db_unique_name,
                        inst_id,
                        row.get("con_id"),
                        "UNKNOWN",
                        row.get("category"),
                        row.get("metric_name"),
                        row.get("object_owner"),
                        row.get("object_name"),
                        row.get("status"),
                        row.get("value"),
                        row.get("details"),
                    ),
                )
                total += 1
    return total


def generate_advisories(pg_conn, identity: dict[str, Any]) -> int:
    db_unique_name = identity["db_unique_name"]
    statements = [
        (
            "log-file-sync",
            """
            INSERT INTO dpa.dpa_advisory (
              db_unique_name, severity, category, sql_id, plan_hash_value, module,
              service_name, signal, recommendation, impact_score
            )
            SELECT db_unique_name, 'warning', 'commit-latency', sql_id, plan_hash_value,
                   module, service_name, 'log file sync active sessions',
                   'Check commit frequency, redo write latency, LGWR pressure, and application commit batching.',
                   impact_score
            FROM dpa.v_sql_impact_1h
            WHERE db_unique_name = %s
              AND event = 'log file sync'
              AND active_seconds >= 60
              AND NOT EXISTS (
                SELECT 1 FROM dpa.dpa_advisory x
                WHERE x.db_unique_name = dpa.v_sql_impact_1h.db_unique_name
                  AND x.category = 'commit-latency'
                  AND coalesce(x.sql_id, '') = coalesce(dpa.v_sql_impact_1h.sql_id, '')
                  AND x.advisory_time >= now() - interval '1 hour'
              )
            """,
        ),
        (
            "plan-change",
            """
            INSERT INTO dpa.dpa_advisory (
              db_unique_name, severity, category, sql_id, signal, recommendation, impact_score
            )
            SELECT pc.db_unique_name, 'warning', 'plan-change', pc.sql_id,
                   'multiple plan hash values in 24h',
                   'Compare dpa.sql_plan_snapshot rows for this SQL ID and inspect changed access paths, join methods, and object stats.',
                   coalesce(i.impact_score, 0)
            FROM dpa.v_plan_changes_24h pc
            LEFT JOIN (
              SELECT db_unique_name, sql_id, max(impact_score) AS impact_score
              FROM dpa.v_sql_impact_1h
              GROUP BY db_unique_name, sql_id
            ) i ON i.db_unique_name = pc.db_unique_name AND i.sql_id = pc.sql_id
            WHERE pc.db_unique_name = %s
              AND NOT EXISTS (
                SELECT 1 FROM dpa.dpa_advisory x
                WHERE x.db_unique_name = pc.db_unique_name
                  AND x.category = 'plan-change'
                  AND x.sql_id = pc.sql_id
                  AND x.advisory_time >= now() - interval '6 hours'
              )
            """,
        ),
        (
            "logical-io",
            """
            INSERT INTO dpa.dpa_advisory (
              db_unique_name, severity, category, sql_id, plan_hash_value, module,
              service_name, signal, recommendation, impact_score
            )
            SELECT s.db_unique_name, 'warning', 'logical-io', s.sql_id, s.plan_hash_value,
                   s.module, s.service_name, 'high buffer gets per execution',
                   'Check predicates, index selectivity, stale stats, join order, and plan stability.',
                   coalesce(i.impact_score, 0)
            FROM dpa.sql_snapshot s
            LEFT JOIN dpa.v_sql_impact_1h i
              ON i.db_unique_name = s.db_unique_name AND i.sql_id = s.sql_id
            WHERE s.db_unique_name = %s
              AND s.snapshot_time >= now() - interval '30 minutes'
              AND s.executions > 0
              AND (s.buffer_gets / greatest(s.executions, 1)) >= 100000
              AND NOT EXISTS (
                SELECT 1 FROM dpa.dpa_advisory x
                WHERE x.db_unique_name = s.db_unique_name
                  AND x.category = 'logical-io'
                  AND x.sql_id = s.sql_id
                  AND x.advisory_time >= now() - interval '6 hours'
              )
            """,
        ),
    ]
    total = 0
    with pg_conn.cursor() as cur:
        for _, sql in statements:
            cur.execute(sql, (db_unique_name,))
            total += cur.rowcount
    return total


def purge_old_data(pg_conn, retention_days: int) -> None:
    with pg_conn.cursor() as cur:
        cur.execute("SELECT dpa.purge_old_data(%s)", (retention_days,))


def run_once() -> None:
    oracledb, psycopg2 = import_drivers()

    oracle_user = require_env("DPA_ORACLE_USER")
    oracle_password = require_env("DPA_ORACLE_PASSWORD")
    oracle_dsn = require_env("DPA_ORACLE_DSN")
    postgres_dsn = require_env("DPA_POSTGRES_DSN")

    configured_db_name = os.getenv("DPA_DB_UNIQUE_NAME", "").strip()
    sample_seconds = env_int("DPA_SAMPLE_SECONDS", 1)
    sql_top_n = env_int("DPA_SQL_TOP_N", 50)
    plan_top_n = env_int("DPA_PLAN_TOP_N", 20)
    lookback_minutes = env_int("DPA_CHANGE_LOOKBACK_MINUTES", 15)
    retention_days = env_int("DPA_RETENTION_DAYS", 35)

    with oracledb.connect(user=oracle_user, password=oracle_password, dsn=oracle_dsn) as ora_conn:
        pg_conn = psycopg2.connect(postgres_dsn)
        try:
            identity = get_db_identity(ora_conn, configured_db_name)
            upsert_db_instance(pg_conn, identity)

            counts = {
                "ash": sample_ash(ora_conn, pg_conn, identity, sample_seconds),
                "sql": snapshot_sql(ora_conn, pg_conn, identity, sql_top_n),
                "blocking": snapshot_blocking(ora_conn, pg_conn, identity),
            }

            if env_bool("DPA_ENABLE_PLAN_SNAPSHOT", True):
                try:
                    counts["plans"] = snapshot_plans(ora_conn, pg_conn, identity, plan_top_n)
                except Exception as exc:
                    counts["plans_error"] = truncate(exc, 120)
            if env_bool("DPA_ENABLE_CHANGE_EVENTS", True):
                try:
                    counts["changes"] = snapshot_change_events(ora_conn, pg_conn, identity, lookback_minutes)
                except Exception as exc:
                    counts["changes_error"] = truncate(exc, 120)
            if env_bool("DPA_ENABLE_OBJECT_STATS", True):
                try:
                    counts["object_stats"] = snapshot_object_stats(ora_conn, pg_conn, identity)
                except Exception as exc:
                    counts["object_stats_error"] = truncate(exc, 120)
            if env_bool("DPA_ENABLE_ORACLE_OPS", True):
                try:
                    counts["oracle_ops"] = snapshot_oracle_ops(ora_conn, pg_conn, identity)
                except Exception as exc:
                    counts["oracle_ops_error"] = truncate(exc, 120)
            if env_bool("DPA_ENABLE_ADVISORY", True):
                counts["advisories"] = generate_advisories(pg_conn, identity)

            purge_old_data(pg_conn, retention_days)
            pg_conn.commit()
            print("DPA sampler OK " + " ".join(f"{key}={value}" for key, value in counts.items()))
        except Exception:
            pg_conn.rollback()
            raise
        finally:
            pg_conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Sample Oracle diagnostic data into PostgreSQL DPA repository.")
    parser.add_argument("--env-file", default=None, help="Optional env file to load before sampling.")
    parser.add_argument("--once", action="store_true", help="Run one sampling cycle.")
    args = parser.parse_args()

    try:
        load_env_file(args.env_file)
        run_once()
        return 0
    except Exception as exc:
        print(f"DPA sampler failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
