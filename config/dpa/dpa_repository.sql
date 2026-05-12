-- PostgreSQL repository for DPA-style historical diagnostics.
-- Loaded by 10_install_postgres_dpa.sh into database dpa_repository.

CREATE SCHEMA IF NOT EXISTS dpa;

CREATE TABLE IF NOT EXISTS dpa.db_instance (
  db_unique_name text PRIMARY KEY,
  db_name text,
  instance_name text,
  inst_id integer,
  host_name text,
  version text,
  platform_name text,
  first_seen timestamptz NOT NULL DEFAULT now(),
  last_seen timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dpa.ash_sample (
  sample_time timestamptz NOT NULL,
  db_unique_name text NOT NULL,
  inst_id integer,
  instance_name text,
  con_id integer,
  pdb_name text,
  sid integer,
  serial_no integer,
  username text,
  status text,
  session_state text,
  sql_id text,
  plan_hash_value numeric,
  wait_class text,
  event text,
  module text,
  action text,
  service_name text,
  machine text,
  program text,
  blocking_session integer,
  sample_seconds numeric NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS dpa.sql_snapshot (
  snapshot_time timestamptz NOT NULL,
  db_unique_name text NOT NULL,
  inst_id integer,
  con_id integer,
  pdb_name text,
  sql_id text NOT NULL,
  plan_hash_value numeric,
  parsing_schema_name text,
  module text,
  action text,
  service_name text,
  last_active_time timestamptz,
  executions numeric,
  elapsed_time_us numeric,
  cpu_time_us numeric,
  buffer_gets numeric,
  disk_reads numeric,
  rows_processed numeric,
  parse_calls numeric,
  version_count numeric,
  sql_text text
);

CREATE TABLE IF NOT EXISTS dpa.sql_plan_snapshot (
  snapshot_time timestamptz NOT NULL,
  db_unique_name text NOT NULL,
  inst_id integer,
  con_id integer,
  pdb_name text,
  sql_id text NOT NULL,
  plan_hash_value numeric NOT NULL,
  child_number integer,
  id integer,
  parent_id integer,
  operation text,
  options text,
  object_owner text,
  object_name text,
  object_type text,
  cardinality numeric,
  bytes numeric,
  cost numeric,
  optimizer text
);

CREATE TABLE IF NOT EXISTS dpa.blocking_episode (
  sample_time timestamptz NOT NULL,
  db_unique_name text NOT NULL,
  inst_id integer,
  con_id integer,
  pdb_name text,
  blocking_sid integer,
  blocked_sid integer,
  blocking_sql_id text,
  blocked_sql_id text,
  blocking_user text,
  blocked_user text,
  wait_class text,
  event text,
  module text,
  machine text
);

CREATE TABLE IF NOT EXISTS dpa.change_event (
  event_time timestamptz NOT NULL,
  db_unique_name text NOT NULL,
  con_id integer,
  pdb_name text,
  source text NOT NULL,
  event_type text NOT NULL,
  object_owner text,
  object_name text,
  object_type text,
  details text,
  detected_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (db_unique_name, con_id, source, event_type, object_owner, object_name, event_time)
);

CREATE TABLE IF NOT EXISTS dpa.object_stats_snapshot (
  sample_time timestamptz NOT NULL,
  db_unique_name text NOT NULL,
  con_id integer,
  pdb_name text,
  owner text,
  object_name text,
  object_type text,
  metric_name text NOT NULL,
  value numeric
);

CREATE TABLE IF NOT EXISTS dpa.app_slo (
  app text NOT NULL,
  tier text NOT NULL,
  db_unique_name text NOT NULL,
  target_db_time_ms_per_call numeric NOT NULL DEFAULT 100,
  business_weight numeric NOT NULL DEFAULT 1,
  owner text,
  notes text,
  PRIMARY KEY (app, tier, db_unique_name)
);

CREATE TABLE IF NOT EXISTS dpa.dpa_advisory (
  advisory_time timestamptz NOT NULL DEFAULT now(),
  db_unique_name text NOT NULL,
  severity text NOT NULL,
  category text NOT NULL,
  sql_id text,
  plan_hash_value numeric,
  module text,
  service_name text,
  signal text NOT NULL,
  recommendation text NOT NULL,
  impact_score numeric NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS dpa.oracle_ops_snapshot (
  sample_time timestamptz NOT NULL,
  db_unique_name text NOT NULL,
  inst_id integer,
  con_id integer,
  pdb_name text,
  category text NOT NULL,
  metric_name text NOT NULL,
  object_owner text,
  object_name text,
  status text,
  value numeric,
  details text
);

CREATE INDEX IF NOT EXISTS ix_ash_sample_time ON dpa.ash_sample (sample_time DESC);
CREATE INDEX IF NOT EXISTS ix_ash_sample_sql_time ON dpa.ash_sample (db_unique_name, sql_id, sample_time DESC);
CREATE INDEX IF NOT EXISTS ix_ash_sample_wait_time ON dpa.ash_sample (db_unique_name, wait_class, event, sample_time DESC);
CREATE INDEX IF NOT EXISTS ix_sql_snapshot_sql_time ON dpa.sql_snapshot (db_unique_name, sql_id, snapshot_time DESC);
CREATE INDEX IF NOT EXISTS ix_sql_plan_snapshot_sql ON dpa.sql_plan_snapshot (db_unique_name, sql_id, plan_hash_value, snapshot_time DESC);
CREATE INDEX IF NOT EXISTS ix_blocking_episode_time ON dpa.blocking_episode (db_unique_name, sample_time DESC);
CREATE INDEX IF NOT EXISTS ix_change_event_time ON dpa.change_event (db_unique_name, event_time DESC);
CREATE INDEX IF NOT EXISTS ix_advisory_time ON dpa.dpa_advisory (db_unique_name, advisory_time DESC);
CREATE INDEX IF NOT EXISTS ix_oracle_ops_time ON dpa.oracle_ops_snapshot (db_unique_name, category, sample_time DESC);

CREATE OR REPLACE VIEW dpa.v_sql_impact_1h AS
SELECT
  a.db_unique_name,
  a.inst_id,
  a.con_id,
  coalesce(nullif(a.pdb_name, ''), 'UNKNOWN') AS pdb_name,
  coalesce(nullif(a.sql_id, ''), 'UNKNOWN') AS sql_id,
  a.plan_hash_value,
  coalesce(nullif(a.module, ''), 'UNKNOWN') AS module,
  coalesce(nullif(a.service_name, ''), 'UNKNOWN') AS service_name,
  coalesce(nullif(a.wait_class, ''), 'UNKNOWN') AS wait_class,
  coalesce(nullif(a.event, ''), 'UNKNOWN') AS event,
  count(*) AS samples,
  sum(a.sample_seconds) AS active_seconds,
  max(s.sql_text) AS sample_sql_text,
  round(sum(a.sample_seconds) * coalesce(max(slo.business_weight), 1), 2) AS impact_score
FROM dpa.ash_sample a
LEFT JOIN LATERAL (
  SELECT ss.sql_text
  FROM dpa.sql_snapshot ss
  WHERE ss.db_unique_name = a.db_unique_name
    AND ss.sql_id = a.sql_id
  ORDER BY ss.snapshot_time DESC
  LIMIT 1
) s ON true
LEFT JOIN dpa.app_slo slo
  ON slo.db_unique_name = a.db_unique_name
 AND lower(slo.app) = lower(coalesce(nullif(a.module, ''), slo.app))
WHERE a.sample_time >= now() - interval '1 hour'
GROUP BY a.db_unique_name, a.inst_id, a.con_id, a.pdb_name, a.sql_id, a.plan_hash_value, a.module, a.service_name, a.wait_class, a.event;

CREATE OR REPLACE VIEW dpa.v_plan_changes_24h AS
SELECT
  db_unique_name,
  con_id,
  coalesce(pdb_name, 'UNKNOWN') AS pdb_name,
  sql_id,
  count(DISTINCT plan_hash_value) AS plan_count,
  min(snapshot_time) AS first_seen,
  max(snapshot_time) AS last_seen,
  string_agg(DISTINCT plan_hash_value::text, ', ' ORDER BY plan_hash_value::text) AS plan_hash_values
FROM dpa.sql_snapshot
WHERE snapshot_time >= now() - interval '24 hours'
  AND plan_hash_value IS NOT NULL
GROUP BY db_unique_name, con_id, coalesce(pdb_name, 'UNKNOWN'), sql_id
HAVING count(DISTINCT plan_hash_value) > 1;

CREATE OR REPLACE VIEW dpa.v_plan_diff_24h AS
WITH latest_plan_rows AS (
  SELECT DISTINCT ON (db_unique_name, con_id, sql_id, plan_hash_value, child_number, id)
    db_unique_name,
    con_id,
    coalesce(pdb_name, 'UNKNOWN') AS pdb_name,
    sql_id,
    plan_hash_value,
    child_number,
    id,
    parent_id,
    operation,
    options,
    object_owner,
    object_name,
    cost,
    cardinality,
    snapshot_time
  FROM dpa.sql_plan_snapshot
  WHERE snapshot_time >= now() - interval '24 hours'
  ORDER BY db_unique_name, con_id, sql_id, plan_hash_value, child_number, id, snapshot_time DESC
),
plan_signatures AS (
  SELECT
    db_unique_name,
    con_id,
    pdb_name,
    sql_id,
    plan_hash_value,
    max(snapshot_time) AS last_seen,
    string_agg(
      concat_ws(
        ' ',
        lpad(id::text, 3, '0'),
        coalesce(operation, ''),
        coalesce(options, ''),
        coalesce(object_owner, ''),
        coalesce(object_name, ''),
        'cost=' || coalesce(cost::text, '?'),
        'card=' || coalesce(cardinality::text, '?')
      ),
      E'\n'
      ORDER BY id
    ) AS plan_signature
  FROM latest_plan_rows
  GROUP BY db_unique_name, con_id, pdb_name, sql_id, plan_hash_value
)
SELECT
  ps.*,
  count(*) OVER (PARTITION BY db_unique_name, con_id, sql_id) AS plan_count
FROM plan_signatures ps
WHERE EXISTS (
  SELECT 1
  FROM dpa.v_plan_changes_24h pc
  WHERE pc.db_unique_name = ps.db_unique_name
    AND pc.sql_id = ps.sql_id
    AND pc.con_id IS NOT DISTINCT FROM ps.con_id
);

CREATE OR REPLACE VIEW dpa.v_wait_seasonal_baseline AS
SELECT
  db_unique_name,
  con_id,
  coalesce(pdb_name, 'UNKNOWN') AS pdb_name,
  extract(isodow from sample_time)::integer AS iso_dow,
  extract(hour from sample_time)::integer AS hour_of_day,
  coalesce(wait_class, 'UNKNOWN') AS wait_class,
  coalesce(event, 'UNKNOWN') AS event,
  count(*)::numeric / greatest(count(DISTINCT date_trunc('hour', sample_time)), 1) AS avg_samples_per_hour
FROM dpa.ash_sample
WHERE sample_time >= now() - interval '35 days'
GROUP BY db_unique_name, con_id, coalesce(pdb_name, 'UNKNOWN'), extract(isodow from sample_time), extract(hour from sample_time), wait_class, event;

CREATE OR REPLACE VIEW dpa.v_oracle_ops_latest AS
SELECT DISTINCT ON (db_unique_name, category, metric_name, object_owner, object_name, con_id)
  *
FROM dpa.oracle_ops_snapshot
ORDER BY db_unique_name, category, metric_name, object_owner, object_name, con_id, sample_time DESC;

CREATE OR REPLACE VIEW dpa.v_repository_table_size AS
SELECT
  schemaname,
  relname AS table_name,
  pg_total_relation_size(format('%I.%I', schemaname, relname)::regclass) AS total_bytes,
  pg_size_pretty(pg_total_relation_size(format('%I.%I', schemaname, relname)::regclass)) AS total_size,
  n_live_tup AS estimated_rows,
  n_dead_tup AS estimated_dead_rows
FROM pg_stat_user_tables
WHERE schemaname = 'dpa'
ORDER BY pg_total_relation_size(format('%I.%I', schemaname, relname)::regclass) DESC;

CREATE OR REPLACE VIEW dpa.v_repository_ingest_rate AS
SELECT 'ash_sample' AS table_name, db_unique_name, count(*) AS rows_last_hour, count(*) * 24 AS estimated_rows_per_day
FROM dpa.ash_sample
WHERE sample_time >= now() - interval '1 hour'
GROUP BY db_unique_name
UNION ALL
SELECT 'sql_snapshot', db_unique_name, count(*), count(*) * 24
FROM dpa.sql_snapshot
WHERE snapshot_time >= now() - interval '1 hour'
GROUP BY db_unique_name
UNION ALL
SELECT 'sql_plan_snapshot', db_unique_name, count(*), count(*) * 24
FROM dpa.sql_plan_snapshot
WHERE snapshot_time >= now() - interval '1 hour'
GROUP BY db_unique_name
UNION ALL
SELECT 'blocking_episode', db_unique_name, count(*), count(*) * 24
FROM dpa.blocking_episode
WHERE sample_time >= now() - interval '1 hour'
GROUP BY db_unique_name
UNION ALL
SELECT 'oracle_ops_snapshot', db_unique_name, count(*), count(*) * 24
FROM dpa.oracle_ops_snapshot
WHERE sample_time >= now() - interval '1 hour'
GROUP BY db_unique_name;

CREATE OR REPLACE VIEW dpa.v_recent_changes AS
SELECT *
FROM dpa.change_event
WHERE event_time >= now() - interval '7 days'
ORDER BY event_time DESC;

CREATE OR REPLACE VIEW dpa.v_advisory_queue AS
SELECT *
FROM dpa.dpa_advisory
WHERE advisory_time >= now() - interval '24 hours'
ORDER BY impact_score DESC, advisory_time DESC;

CREATE OR REPLACE FUNCTION dpa.purge_old_data(retention_days integer DEFAULT 35)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM dpa.ash_sample WHERE sample_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.sql_snapshot WHERE snapshot_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.sql_plan_snapshot WHERE snapshot_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.blocking_episode WHERE sample_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.object_stats_snapshot WHERE sample_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.oracle_ops_snapshot WHERE sample_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.dpa_advisory WHERE advisory_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.change_event WHERE event_time < now() - make_interval(days => retention_days * 3);
END;
$$;

GRANT USAGE ON SCHEMA dpa TO dpa_app, dpa_reader;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA dpa TO dpa_app;
GRANT SELECT ON ALL TABLES IN SCHEMA dpa TO dpa_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA dpa TO dpa_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA dpa TO dpa_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA dpa GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO dpa_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA dpa GRANT SELECT ON TABLES TO dpa_reader;

-- MSSQL DPA repository objects.

CREATE TABLE IF NOT EXISTS dpa.mssql_instance (
  instance_name text PRIMARY KEY,
  server_name text,
  product_version text,
  product_level text,
  edition text,
  first_seen timestamptz NOT NULL DEFAULT now(),
  last_seen timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dpa.mssql_request_sample (
  sample_time timestamptz NOT NULL,
  instance_name text NOT NULL,
  database_name text,
  session_id integer,
  request_id integer,
  status text,
  command text,
  wait_type text,
  wait_time_ms numeric,
  wait_resource text,
  blocking_session_id integer,
  cpu_time_ms numeric,
  elapsed_time_ms numeric,
  logical_reads numeric,
  reads numeric,
  writes numeric,
  query_hash text,
  query_plan_hash text,
  login_name text,
  host_name text,
  program_name text,
  sample_seconds numeric NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS dpa.mssql_query_snapshot (
  snapshot_time timestamptz NOT NULL,
  instance_name text NOT NULL,
  database_name text,
  query_hash text,
  query_plan_hash text,
  plan_handle text,
  sql_handle text,
  statement_context text,
  execution_count numeric,
  total_worker_time_us numeric,
  total_elapsed_time_us numeric,
  total_logical_reads numeric,
  total_physical_reads numeric,
  total_logical_writes numeric,
  total_rows numeric,
  last_execution_time timestamptz,
  query_text text
);

CREATE TABLE IF NOT EXISTS dpa.mssql_plan_snapshot (
  snapshot_time timestamptz NOT NULL,
  instance_name text NOT NULL,
  database_name text,
  query_hash text,
  query_plan_hash text,
  plan_handle text,
  query_plan text
);

CREATE TABLE IF NOT EXISTS dpa.mssql_blocking_episode (
  sample_time timestamptz NOT NULL,
  instance_name text NOT NULL,
  database_name text,
  blocked_session_id integer,
  blocking_session_id integer,
  wait_type text,
  wait_time_ms numeric,
  wait_resource text,
  blocked_query_hash text,
  blocking_query_hash text,
  login_name text,
  host_name text,
  program_name text
);

CREATE TABLE IF NOT EXISTS dpa.mssql_ops_snapshot (
  sample_time timestamptz NOT NULL,
  instance_name text NOT NULL,
  database_name text,
  category text NOT NULL,
  metric_name text NOT NULL,
  object_name text,
  status text,
  value numeric,
  details text
);

CREATE TABLE IF NOT EXISTS dpa.mssql_advisory (
  advisory_time timestamptz NOT NULL DEFAULT now(),
  instance_name text NOT NULL,
  severity text NOT NULL,
  category text NOT NULL,
  database_name text,
  query_hash text,
  query_plan_hash text,
  signal text NOT NULL,
  recommendation text NOT NULL,
  impact_score numeric NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS ix_mssql_request_sample_time ON dpa.mssql_request_sample (instance_name, sample_time DESC);
CREATE INDEX IF NOT EXISTS ix_mssql_request_sample_query ON dpa.mssql_request_sample (instance_name, query_hash, sample_time DESC);
CREATE INDEX IF NOT EXISTS ix_mssql_query_snapshot_query ON dpa.mssql_query_snapshot (instance_name, database_name, query_hash, snapshot_time DESC);
CREATE INDEX IF NOT EXISTS ix_mssql_plan_snapshot_query ON dpa.mssql_plan_snapshot (instance_name, database_name, query_hash, query_plan_hash, snapshot_time DESC);
CREATE INDEX IF NOT EXISTS ix_mssql_blocking_time ON dpa.mssql_blocking_episode (instance_name, sample_time DESC);
CREATE INDEX IF NOT EXISTS ix_mssql_ops_time ON dpa.mssql_ops_snapshot (instance_name, category, sample_time DESC);
CREATE INDEX IF NOT EXISTS ix_mssql_advisory_time ON dpa.mssql_advisory (instance_name, advisory_time DESC);

CREATE OR REPLACE VIEW dpa.v_mssql_query_impact_1h AS
SELECT
  r.instance_name,
  coalesce(r.database_name, 'UNKNOWN') AS database_name,
  coalesce(r.query_hash, 'UNKNOWN') AS query_hash,
  coalesce(r.query_plan_hash, 'UNKNOWN') AS query_plan_hash,
  coalesce(r.wait_type, 'CPU/RUNNING') AS wait_type,
  coalesce(r.program_name, 'UNKNOWN') AS program_name,
  count(*) AS samples,
  sum(r.sample_seconds) AS active_seconds,
  max(q.query_text) AS sample_query_text,
  round(sum(r.sample_seconds), 2) AS impact_score
FROM dpa.mssql_request_sample r
LEFT JOIN LATERAL (
  SELECT qs.query_text
  FROM dpa.mssql_query_snapshot qs
  WHERE qs.instance_name = r.instance_name
    AND qs.query_hash = r.query_hash
  ORDER BY qs.snapshot_time DESC
  LIMIT 1
) q ON true
WHERE r.sample_time >= now() - interval '1 hour'
GROUP BY r.instance_name, r.database_name, r.query_hash, r.query_plan_hash, r.wait_type, r.program_name;

CREATE OR REPLACE VIEW dpa.v_mssql_plan_changes_24h AS
SELECT
  instance_name,
  database_name,
  query_hash,
  count(DISTINCT query_plan_hash) AS plan_count,
  min(snapshot_time) AS first_seen,
  max(snapshot_time) AS last_seen,
  string_agg(DISTINCT query_plan_hash, ', ' ORDER BY query_plan_hash) AS query_plan_hashes
FROM dpa.mssql_query_snapshot
WHERE snapshot_time >= now() - interval '24 hours'
  AND query_hash IS NOT NULL
  AND query_plan_hash IS NOT NULL
GROUP BY instance_name, database_name, query_hash
HAVING count(DISTINCT query_plan_hash) > 1;

CREATE OR REPLACE VIEW dpa.v_mssql_ops_latest AS
SELECT DISTINCT ON (instance_name, database_name, category, metric_name, object_name)
  *
FROM dpa.mssql_ops_snapshot
ORDER BY instance_name, database_name, category, metric_name, object_name, sample_time DESC;

CREATE OR REPLACE VIEW dpa.v_mssql_advisory_queue AS
SELECT *
FROM dpa.mssql_advisory
WHERE advisory_time >= now() - interval '24 hours'
ORDER BY impact_score DESC, advisory_time DESC;

CREATE OR REPLACE FUNCTION dpa.purge_old_mssql_data(retention_days integer DEFAULT 35)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM dpa.mssql_request_sample WHERE sample_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.mssql_query_snapshot WHERE snapshot_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.mssql_plan_snapshot WHERE snapshot_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.mssql_blocking_episode WHERE sample_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.mssql_ops_snapshot WHERE sample_time < now() - make_interval(days => retention_days);
  DELETE FROM dpa.mssql_advisory WHERE advisory_time < now() - make_interval(days => retention_days);
END;
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA dpa TO dpa_app;
GRANT SELECT ON ALL TABLES IN SCHEMA dpa TO dpa_reader;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA dpa TO dpa_app;
