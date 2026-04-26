import csv
import os
import sys

INPUT_FILE = "inventory/targets.csv"
OUTPUT_DIR = "config/targets"

NODE_FILE = os.path.join(OUTPUT_DIR, "node_targets.yml")
ORACLE_FILE = os.path.join(OUTPUT_DIR, "oracle_targets.yml")
MSSQL_FILE = os.path.join(OUTPUT_DIR, "mssql_targets.yml")

REQUIRED_FIELDS = ["host", "ip", "node", "oracle", "mssql", "app", "tier", "owner"]


def fail(msg):
    print(f"[ERROR] {msg}")
    sys.exit(1)


def validate_row(row, line_no):
    for field in REQUIRED_FIELDS:
        if field not in row or not row[field].strip():
            fail(f"Missing field '{field}' at line {line_no}")

    if row["node"] not in ("yes", "no"):
        fail(f"Invalid value for node at line {line_no}")

    if row["oracle"] not in ("yes", "no"):
        fail(f"Invalid value for oracle at line {line_no}")

    if row["mssql"] not in ("yes", "no"):
        fail(f"Invalid value for mssql at line {line_no}")


def write_entry(file, ip, port, service, db_type, role, app, tier, owner):
    file.write(f"""- targets:
    - "{ip}:{port}"
  labels:
    service: "{service}"
    environment: "development"
    site: "development"
    team: "dba"
    role: "{role}"
    db_type: "{db_type}"
    app: "{app}"
    tier: "{tier}"
    owner: "{owner}"

""")


def main():
    if not os.path.exists(INPUT_FILE):
        fail(f"Input file not found: {INPUT_FILE}")

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    node_f = open(NODE_FILE, "w")
    oracle_f = open(ORACLE_FILE, "w")
    mssql_f = open(MSSQL_FILE, "w")

    seen_ips = set()

    with open(INPUT_FILE, newline="") as csvfile:
        reader = csv.DictReader(csvfile)

        if reader.fieldnames is None:
            fail("CSV header missing")

        for i, row in enumerate(reader, start=2):
            validate_row(row, i)

            ip = row["ip"].strip()

            if ip in seen_ips:
                fail(f"Duplicate IP detected: {ip}")
            seen_ips.add(ip)

            app = row["app"].strip()
            tier = row["tier"].strip()
            owner = row["owner"].strip()

            if row["node"] == "yes":
                write_entry(node_f, ip, 9100, "node", "none", "infrastructure", app, tier, owner)

            if row["oracle"] == "yes":
                write_entry(oracle_f, ip, 9161, "oracle", "oracle", "database", app, tier, owner)

            if row["mssql"] == "yes":
                write_entry(mssql_f, ip, 9399, "mssql", "mssql", "database", app, tier, owner)

    node_f.close()
    oracle_f.close()
    mssql_f.close()

    print("[DONE] Targets generated successfully")
    print(f"- {NODE_FILE}")
    print(f"- {ORACLE_FILE}")
    print(f"- {MSSQL_FILE}")


if __name__ == "__main__":
    main()
