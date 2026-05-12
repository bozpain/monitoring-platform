-- Optional DPA detail snapshot.
-- Run this outside Prometheus on a schedule when SQL text drilldown is needed.
-- Keep SQL text out of Prometheus labels to avoid high-cardinality time series.

DECLARE
  table_missing EXCEPTION;
  PRAGMA EXCEPTION_INIT(table_missing, -942);
BEGIN
  EXECUTE IMMEDIATE 'SELECT 1 FROM monitoring_sql_text_snapshot WHERE 1 = 0';
EXCEPTION
  WHEN table_missing THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE monitoring_sql_text_snapshot (
        snapshot_time       TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        sql_id              VARCHAR2(13) NOT NULL,
        plan_hash_value     NUMBER,
        parsing_schema_name VARCHAR2(128),
        module              VARCHAR2(64),
        action              VARCHAR2(64),
        service             VARCHAR2(64),
        last_active_time    DATE,
        executions          NUMBER,
        elapsed_time_us     NUMBER,
        cpu_time_us         NUMBER,
        buffer_gets         NUMBER,
        disk_reads          NUMBER,
        sql_text            CLOB
      )';
END;
/

INSERT INTO monitoring_sql_text_snapshot (
  sql_id,
  plan_hash_value,
  parsing_schema_name,
  module,
  action,
  service,
  last_active_time,
  executions,
  elapsed_time_us,
  cpu_time_us,
  buffer_gets,
  disk_reads,
  sql_text
)
SELECT sql_id,
       plan_hash_value,
       parsing_schema_name,
       module,
       action,
       service,
       last_active_time,
       executions,
       elapsed_time,
       cpu_time,
       buffer_gets,
       disk_reads,
       sql_fulltext
FROM (
  SELECT sql_id,
         plan_hash_value,
         parsing_schema_name,
         module,
         action,
         service,
         last_active_time,
         executions,
         elapsed_time,
         cpu_time,
         buffer_gets,
         disk_reads,
         sql_fulltext
  FROM v$sql
  WHERE sql_id IS NOT NULL
  AND last_active_time >= SYSDATE - (1 / 24)
  ORDER BY elapsed_time DESC
)
WHERE rownum <= 100;

COMMIT;
