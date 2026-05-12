#!/usr/bin/env python3
"""
MSSQL activity, query, plan, and ops sampler for the local PostgreSQL DPA repository.

Prometheus keeps the high-speed metrics path. This sampler stores the diagnostic
detail that should not live in labels: SQL text, plan XML, blocking episodes,
and advisory hints.
"""

from __future__ import annotations

import argparse
import os
import sys
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
        import pymssql  # type: ignore
    except ImportError as exc:
        raise RuntimeError(
            "pymssql is not installed. Install wheels from /monitoring/sources/python "
            "or OS packages, then restart mssql_dpa_sampler."
        ) from exc

    try:
        import psycopg2  # type: ignore
    except ImportError as exc:
        raise RuntimeError("psycopg2 is not installed. Install psycopg2/psycopg2-binary.") from exc

    return pymssql, psycopg2


def rows_as_dicts(cursor) -> list[dict[str, Any]]:
    columns = [col[0].lower() for col in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def mssql_query(conn, sql: str, params: tuple[Any, ...] | None = None) -> list[dict[str, Any]]:
    cur = conn.cursor()
    try:
        cur.execute(sql, params or ())
        return rows_as_dicts(cur)
    finally:
        cur.close()


def pg_execute(conn, sql: str, params: tuple[Any, ...] | None = None) -> int:
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        return cur.rowcount


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
    return str(value)[:limit]


def safe_mssql_query(conn, description: str, sql: str) -> list[dict[str, Any]]:
    try:
        return mssql_query(conn, sql)
    except Exception as exc:  # noqa: BLE001 - optional DMV modules should not stop core sampling.
        print(f"[WARN] Skipping {description}: {exc}", file=sys.stderr)
        return []


def get_instance_identity(ms_conn, configured_name: str) -> dict[str, Any]:
    rows = mssql_query(
        ms_conn,
        """
        SELECT
          CAST(SERVERPROPERTY('ServerName') AS nvarchar(256)) AS server_name,
          CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS product_version,
          CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(128)) AS product_level,
          CAST(SERVERPROPERTY('Edition') AS nvarchar(256)) AS edition
        """,
    )
    identity = rows[0] if rows else {}
    server_name = identity.get("server_name") or configured_name
    identity["instance_name"] = configured_name or server_name
    return identity


def upsert_instance(pg_conn, identity: dict[str, Any]) -> None:
    pg_execute(
        pg_conn,
        """
        INSERT INTO dpa.mssql_instance (
          instance_name, server_name, product_version, product_level, edition, first_seen, last_seen
        )
        VALUES (%s, %s, %s, %s, %s, now(), now())
        ON CONFLICT (instance_name) DO UPDATE SET
          server_name = EXCLUDED.server_name,
          product_version = EXCLUDED.product_version,
          product_level = EXCLUDED.product_level,
          edition = EXCLUDED.edition,
          last_seen = now()
        """,
        (
            identity["instance_name"],
            identity.get("server_name"),
            identity.get("product_version"),
            identity.get("product_level"),
            identity.get("edition"),
        ),
    )


def collect_request_samples(ms_conn, pg_conn, instance_name: str, sample_seconds: int) -> int:
    rows = mssql_query(
        ms_conn,
        """
        SELECT
          SYSDATETIMEOFFSET() AS sample_time,
          DB_NAME(r.database_id) AS database_name,
          r.session_id,
          r.request_id,
          r.status,
          r.command,
          COALESCE(r.wait_type, 'CPU/RUNNING') AS wait_type,
          r.wait_time AS wait_time_ms,
          r.wait_resource,
          NULLIF(r.blocking_session_id, 0) AS blocking_session_id,
          r.cpu_time AS cpu_time_ms,
          r.total_elapsed_time AS elapsed_time_ms,
          r.logical_reads,
          r.reads,
          r.writes,
          CONVERT(varchar(34), q.query_hash, 1) AS query_hash,
          CONVERT(varchar(34), q.query_plan_hash, 1) AS query_plan_hash,
          s.login_name,
          s.host_name,
          s.program_name
        FROM sys.dm_exec_requests r
        JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
        OUTER APPLY (
          SELECT TOP (1) qs.query_hash, qs.query_plan_hash
          FROM sys.dm_exec_query_stats qs
          WHERE qs.sql_handle = r.sql_handle
          ORDER BY qs.last_execution_time DESC
        ) q
        WHERE r.session_id <> @@SPID
          AND s.is_user_process = 1
        """,
    )
    return pg_executemany(
        pg_conn,
        """
        INSERT INTO dpa.mssql_request_sample (
          sample_time, instance_name, database_name, session_id, request_id, status, command,
          wait_type, wait_time_ms, wait_resource, blocking_session_id, cpu_time_ms,
          elapsed_time_ms, logical_reads, reads, writes, query_hash, query_plan_hash,
          login_name, host_name, program_name, sample_seconds
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            (
                row["sample_time"],
                instance_name,
                row.get("database_name"),
                row.get("session_id"),
                row.get("request_id"),
                row.get("status"),
                row.get("command"),
                row.get("wait_type"),
                row.get("wait_time_ms"),
                truncate(row.get("wait_resource"), 400),
                row.get("blocking_session_id"),
                row.get("cpu_time_ms"),
                row.get("elapsed_time_ms"),
                row.get("logical_reads"),
                row.get("reads"),
                row.get("writes"),
                row.get("query_hash"),
                row.get("query_plan_hash"),
                truncate(row.get("login_name"), 256),
                truncate(row.get("host_name"), 256),
                truncate(row.get("program_name"), 512),
                sample_seconds,
            )
            for row in rows
        ),
    )


def collect_query_snapshots(ms_conn, pg_conn, instance_name: str, top_n: int) -> int:
    top_n = max(1, min(top_n, 500))
    rows = mssql_query(
        ms_conn,
        f"""
        SELECT TOP ({top_n})
          SYSDATETIMEOFFSET() AS snapshot_time,
          COALESCE(DB_NAME(st.dbid), DB_NAME()) AS database_name,
          CONVERT(varchar(34), qs.query_hash, 1) AS query_hash,
          CONVERT(varchar(34), qs.query_plan_hash, 1) AS query_plan_hash,
          CONVERT(varchar(256), qs.plan_handle, 1) AS plan_handle,
          CONVERT(varchar(256), qs.sql_handle, 1) AS sql_handle,
          CONCAT(
            COALESCE(DB_NAME(st.dbid), DB_NAME()),
            ':',
            qs.statement_start_offset,
            ':',
            qs.statement_end_offset
          ) AS statement_context,
          qs.execution_count,
          qs.total_worker_time AS total_worker_time_us,
          qs.total_elapsed_time AS total_elapsed_time_us,
          qs.total_logical_reads,
          qs.total_physical_reads,
          qs.total_logical_writes,
          qs.total_rows,
          qs.last_execution_time,
          SUBSTRING(
            st.text,
            (qs.statement_start_offset / 2) + 1,
            (
              (
                CASE qs.statement_end_offset
                  WHEN -1 THEN DATALENGTH(st.text)
                  ELSE qs.statement_end_offset
                END - qs.statement_start_offset
              ) / 2
            ) + 1
          ) AS query_text
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        WHERE qs.last_execution_time >= DATEADD(hour, -6, SYSDATETIME())
        ORDER BY qs.total_worker_time + qs.total_elapsed_time + (qs.total_logical_reads * 1000) DESC
        """,
    )
    return pg_executemany(
        pg_conn,
        """
        INSERT INTO dpa.mssql_query_snapshot (
          snapshot_time, instance_name, database_name, query_hash, query_plan_hash, plan_handle,
          sql_handle, statement_context, execution_count, total_worker_time_us,
          total_elapsed_time_us, total_logical_reads, total_physical_reads,
          total_logical_writes, total_rows, last_execution_time, query_text
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            (
                row["snapshot_time"],
                instance_name,
                row.get("database_name"),
                row.get("query_hash"),
                row.get("query_plan_hash"),
                row.get("plan_handle"),
                row.get("sql_handle"),
                truncate(row.get("statement_context"), 512),
                row.get("execution_count"),
                row.get("total_worker_time_us"),
                row.get("total_elapsed_time_us"),
                row.get("total_logical_reads"),
                row.get("total_physical_reads"),
                row.get("total_logical_writes"),
                row.get("total_rows"),
                row.get("last_execution_time"),
                truncate(row.get("query_text"), 20000),
            )
            for row in rows
        ),
    )


def collect_plan_snapshots(ms_conn, pg_conn, instance_name: str, top_n: int) -> int:
    top_n = max(1, min(top_n, 100))
    rows = safe_mssql_query(
        ms_conn,
        "plan snapshots",
        f"""
        SELECT TOP ({top_n})
          SYSDATETIMEOFFSET() AS snapshot_time,
          COALESCE(DB_NAME(st.dbid), DB_NAME()) AS database_name,
          CONVERT(varchar(34), qs.query_hash, 1) AS query_hash,
          CONVERT(varchar(34), qs.query_plan_hash, 1) AS query_plan_hash,
          CONVERT(varchar(256), qs.plan_handle, 1) AS plan_handle,
          CAST(qp.query_plan AS nvarchar(max)) AS query_plan
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
        WHERE qs.last_execution_time >= DATEADD(hour, -6, SYSDATETIME())
        ORDER BY qs.total_worker_time + qs.total_elapsed_time + (qs.total_logical_reads * 1000) DESC
        """,
    )
    return pg_executemany(
        pg_conn,
        """
        INSERT INTO dpa.mssql_plan_snapshot (
          snapshot_time, instance_name, database_name, query_hash, query_plan_hash, plan_handle, query_plan
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
        (
            (
                row["snapshot_time"],
                instance_name,
                row.get("database_name"),
                row.get("query_hash"),
                row.get("query_plan_hash"),
                row.get("plan_handle"),
                truncate(row.get("query_plan"), 200000),
            )
            for row in rows
        ),
    )


def collect_blocking(ms_conn, pg_conn, instance_name: str) -> int:
    rows = mssql_query(
        ms_conn,
        """
        SELECT
          SYSDATETIMEOFFSET() AS sample_time,
          DB_NAME(br.database_id) AS database_name,
          br.session_id AS blocked_session_id,
          br.blocking_session_id,
          br.wait_type,
          br.wait_time AS wait_time_ms,
          br.wait_resource,
          CONVERT(varchar(34), bq.query_hash, 1) AS blocked_query_hash,
          CONVERT(varchar(34), rq.query_hash, 1) AS blocking_query_hash,
          bs.login_name,
          bs.host_name,
          bs.program_name
        FROM sys.dm_exec_requests br
        JOIN sys.dm_exec_sessions bs ON bs.session_id = br.session_id
        LEFT JOIN sys.dm_exec_requests rr ON rr.session_id = br.blocking_session_id
        OUTER APPLY (
          SELECT TOP (1) qs.query_hash
          FROM sys.dm_exec_query_stats qs
          WHERE qs.sql_handle = br.sql_handle
          ORDER BY qs.last_execution_time DESC
        ) bq
        OUTER APPLY (
          SELECT TOP (1) qs.query_hash
          FROM sys.dm_exec_query_stats qs
          WHERE qs.sql_handle = rr.sql_handle
          ORDER BY qs.last_execution_time DESC
        ) rq
        WHERE br.blocking_session_id <> 0
        """,
    )
    return pg_executemany(
        pg_conn,
        """
        INSERT INTO dpa.mssql_blocking_episode (
          sample_time, instance_name, database_name, blocked_session_id, blocking_session_id,
          wait_type, wait_time_ms, wait_resource, blocked_query_hash, blocking_query_hash,
          login_name, host_name, program_name
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            (
                row["sample_time"],
                instance_name,
                row.get("database_name"),
                row.get("blocked_session_id"),
                row.get("blocking_session_id"),
                row.get("wait_type"),
                row.get("wait_time_ms"),
                truncate(row.get("wait_resource"), 400),
                row.get("blocked_query_hash"),
                row.get("blocking_query_hash"),
                truncate(row.get("login_name"), 256),
                truncate(row.get("host_name"), 256),
                truncate(row.get("program_name"), 512),
            )
            for row in rows
        ),
    )


def collect_ops(ms_conn, pg_conn, instance_name: str) -> int:
    rows: list[tuple[Any, ...]] = []

    for row in safe_mssql_query(
        ms_conn,
        "database state snapshots",
        """
        SELECT
          SYSDATETIMEOFFSET() AS sample_time,
          name AS database_name,
          state AS state_value,
          state_desc,
          user_access_desc,
          recovery_model_desc,
          compatibility_level
        FROM sys.databases
        """,
    ):
        rows.append(
            (
                row["sample_time"],
                instance_name,
                row.get("database_name"),
                "database",
                "state",
                row.get("database_name"),
                row.get("state_desc"),
                row.get("state_value"),
                (
                    f"user_access={row.get('user_access_desc')}; "
                    f"recovery_model={row.get('recovery_model_desc')}; "
                    f"compatibility_level={row.get('compatibility_level')}"
                ),
            )
        )

    for row in safe_mssql_query(
        ms_conn,
        "backup age snapshots",
        """
        SELECT
          SYSDATETIMEOFFSET() AS sample_time,
          d.name AS database_name,
          DATEDIFF(hour, MAX(b.backup_finish_date), SYSDATETIME()) AS backup_age_hours,
          MAX(b.backup_finish_date) AS last_backup_time
        FROM sys.databases d
        LEFT JOIN msdb.dbo.backupset b
          ON b.database_name = d.name
         AND b.type = 'D'
        WHERE d.name <> 'tempdb'
        GROUP BY d.name
        """,
    ):
        rows.append(
            (
                row["sample_time"],
                instance_name,
                row.get("database_name"),
                "backup",
                "full_backup_age_hours",
                row.get("database_name"),
                None,
                row.get("backup_age_hours"),
                f"last_backup_time={row.get('last_backup_time')}",
            )
        )

    for row in safe_mssql_query(
        ms_conn,
        "failed SQL Agent jobs",
        """
        SELECT
          SYSDATETIMEOFFSET() AS sample_time,
          j.name AS job_name,
          COUNT_BIG(*) AS failed_runs_24h
        FROM msdb.dbo.sysjobhistory h
        JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
        WHERE h.step_id = 0
          AND h.run_status = 0
          AND msdb.dbo.agent_datetime(h.run_date, h.run_time) >= DATEADD(day, -1, GETDATE())
        GROUP BY j.name
        """,
    ):
        rows.append(
            (
                row["sample_time"],
                instance_name,
                "msdb",
                "agent",
                "failed_runs_24h",
                truncate(row.get("job_name"), 512),
                "FAILED",
                row.get("failed_runs_24h"),
                "SQL Agent job failures in the last 24 hours",
            )
        )

    return pg_executemany(
        pg_conn,
        """
        INSERT INTO dpa.mssql_ops_snapshot (
          sample_time, instance_name, database_name, category, metric_name, object_name, status, value, details
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        rows,
    )


def generate_advisories(pg_conn, instance_name: str) -> int:
    total = 0
    total += pg_execute(
        pg_conn,
        """
        INSERT INTO dpa.mssql_advisory (
          advisory_time, instance_name, severity, category, database_name, query_hash,
          query_plan_hash, signal, recommendation, impact_score
        )
        SELECT
          now(),
          instance_name,
          CASE WHEN active_seconds >= 300 THEN 'critical' ELSE 'warning' END,
          'wait',
          database_name,
          query_hash,
          query_plan_hash,
          wait_type,
          CASE
            WHEN wait_type LIKE 'LCK%' THEN 'Investigate blocking chain, transaction scope, and missing commit/rollback.'
            WHEN wait_type LIKE 'PAGEIOLATCH%' THEN 'Check storage latency, missing indexes, and query read pattern.'
            WHEN wait_type LIKE 'WRITELOG%' THEN 'Check log write latency, transaction batch size, and VLF/log configuration.'
            WHEN wait_type LIKE 'RESOURCE_SEMAPHORE%' THEN 'Check memory grants, cardinality estimates, and concurrent large queries.'
            WHEN wait_type LIKE 'CXPACKET%' OR wait_type LIKE 'CXCONSUMER%' THEN 'Review parallelism skew, MAXDOP, cost threshold, and plan operators.'
            ELSE 'Review top wait contributor and correlate with query text/plan history.'
          END,
          impact_score
        FROM dpa.v_mssql_query_impact_1h
        WHERE instance_name = %s
          AND active_seconds >= 60
          AND NOT EXISTS (
            SELECT 1
            FROM dpa.mssql_advisory a
            WHERE a.instance_name = dpa.v_mssql_query_impact_1h.instance_name
              AND a.category = 'wait'
              AND a.query_hash IS NOT DISTINCT FROM dpa.v_mssql_query_impact_1h.query_hash
              AND a.signal = dpa.v_mssql_query_impact_1h.wait_type
              AND a.advisory_time >= now() - interval '1 hour'
          )
        """,
        (instance_name,),
    )
    total += pg_execute(
        pg_conn,
        """
        INSERT INTO dpa.mssql_advisory (
          advisory_time, instance_name, severity, category, database_name, query_hash,
          signal, recommendation, impact_score
        )
        SELECT
          now(),
          instance_name,
          'warning',
          'plan',
          database_name,
          query_hash,
          'multiple_plan_hashes',
          'Query hash has multiple plan hashes in 24h. Compare plans and check parameter sensitivity/statistics changes.',
          plan_count * 100
        FROM dpa.v_mssql_plan_changes_24h v
        WHERE instance_name = %s
          AND NOT EXISTS (
            SELECT 1
            FROM dpa.mssql_advisory a
            WHERE a.instance_name = v.instance_name
              AND a.category = 'plan'
              AND a.query_hash = v.query_hash
              AND a.signal = 'multiple_plan_hashes'
              AND a.advisory_time >= now() - interval '6 hours'
          )
        """,
        (instance_name,),
    )
    total += pg_execute(
        pg_conn,
        """
        INSERT INTO dpa.mssql_advisory (
          advisory_time, instance_name, severity, category, database_name, query_hash,
          query_plan_hash, signal, recommendation, impact_score
        )
        SELECT
          now(),
          instance_name,
          'info',
          'logical_io',
          database_name,
          query_hash,
          query_plan_hash,
          'high_logical_reads_per_exec',
          'High logical reads per execution. Review predicates, covering indexes, join order, and stale statistics.',
          total_logical_reads / GREATEST(execution_count, 1)
        FROM dpa.mssql_query_snapshot q
        WHERE q.instance_name = %s
          AND q.snapshot_time >= now() - interval '1 hour'
          AND q.execution_count > 0
          AND (q.total_logical_reads / GREATEST(q.execution_count, 1)) >= 100000
          AND NOT EXISTS (
            SELECT 1
            FROM dpa.mssql_advisory a
            WHERE a.instance_name = q.instance_name
              AND a.category = 'logical_io'
              AND a.query_hash = q.query_hash
              AND a.advisory_time >= now() - interval '6 hours'
          )
        """,
        (instance_name,),
    )
    return total


def run_once() -> None:
    pymssql, psycopg2 = import_drivers()

    host = require_env("DPA_MSSQL_HOST")
    user = require_env("DPA_MSSQL_USER")
    password = require_env("DPA_MSSQL_PASSWORD")
    database = os.getenv("DPA_MSSQL_DATABASE", "master")
    port = env_int("DPA_MSSQL_PORT", 1433)
    configured_instance = os.getenv("DPA_MSSQL_INSTANCE_NAME", "").strip()
    pg_dsn = require_env("DPA_POSTGRES_DSN")

    sample_seconds = env_int("DPA_SAMPLE_SECONDS", 1)
    sql_top_n = env_int("DPA_SQL_TOP_N", 50)
    plan_top_n = env_int("DPA_PLAN_TOP_N", 20)
    retention_days = env_int("DPA_RETENTION_DAYS", 35)

    ms_conn = pymssql.connect(
        server=host,
        port=port,
        user=user,
        password=password,
        database=database,
        login_timeout=10,
        timeout=60,
        charset="UTF-8",
    )
    pg_conn = psycopg2.connect(pg_dsn)

    try:
        identity = get_instance_identity(ms_conn, configured_instance)
        instance_name = identity["instance_name"]

        upsert_instance(pg_conn, identity)
        request_rows = collect_request_samples(ms_conn, pg_conn, instance_name, sample_seconds)
        query_rows = collect_query_snapshots(ms_conn, pg_conn, instance_name, sql_top_n)
        plan_rows = 0
        if env_bool("DPA_ENABLE_PLAN_SNAPSHOT", True):
            plan_rows = collect_plan_snapshots(ms_conn, pg_conn, instance_name, plan_top_n)
        blocking_rows = collect_blocking(ms_conn, pg_conn, instance_name)
        ops_rows = 0
        if env_bool("DPA_ENABLE_MSSQL_OPS", True):
            ops_rows = collect_ops(ms_conn, pg_conn, instance_name)
        advisory_rows = 0
        if env_bool("DPA_ENABLE_ADVISORY", True):
            advisory_rows = generate_advisories(pg_conn, instance_name)

        pg_execute(pg_conn, "SELECT dpa.purge_old_mssql_data(%s)", (retention_days,))
        pg_conn.commit()
        print(
            "[INFO] MSSQL DPA sample complete: "
            f"instance={instance_name} requests={request_rows} queries={query_rows} "
            f"plans={plan_rows} blocking={blocking_rows} ops={ops_rows} advisories={advisory_rows}"
        )
    except Exception:
        pg_conn.rollback()
        raise
    finally:
        pg_conn.close()
        ms_conn.close()


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="MSSQL DPA repository sampler")
    parser.add_argument("--env-file", help="Load environment variables from this file")
    parser.add_argument("--once", action="store_true", help="Run one sample and exit")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    load_env_file(args.env_file)
    run_once()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except Exception as exc:  # noqa: BLE001
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1)
