import csv
import os
import sys
from collections import defaultdict

INPUT_FILE = "inventory/targets.csv"
OUTPUT_DIR = "config/targets"

NODE_FILE = os.path.join(OUTPUT_DIR, "node_targets.yml")
ORACLE_FILE = os.path.join(OUTPUT_DIR, "oracle_targets.yml")
MSSQL_FILE = os.path.join(OUTPUT_DIR, "mssql_targets.yml")

REQUIRED_FIELDS = [
    "host",
    "ip",
    "node",
    "oracle",
    "mssql",
    "app",
    "tier",
    "owner",
]

VALID_YES_NO = {"yes", "no"}
VALID_TIER = {"vit", "sit", "uat", "pt", "shared"}


def fail(message: str) -> None:
    print(f"[ERROR] {message}")
    sys.exit(1)


def normalize(value: str) -> str:
    return value.strip().lower()


def validate_row(row: dict, line_no: int) -> None:
    for field in REQUIRED_FIELDS:
        if field not in row:
            fail(f"Missing CSV column '{field}'")
        if not row[field].strip():
            fail(f"Empty value for '{field}' at line {line_no}")

    for field in ["node", "oracle", "mssql"]:
        value = normalize(row[field])
        if value not in VALID_YES_NO:
            fail(f"Invalid value for '{field}' at line {line_no}: {row[field]}")

    tier = normalize(row["tier"])
    if tier not in VALID_TIER:
        fail(f"Invalid tier at line {line_no}: {row['tier']}")


def labels_key(
    service: str,
    role: str,
    db_type: str,
    app: str,
    tier: str,
    owner: str,
) -> tuple:
    return (
        service,
        "development",
        "development",
        "dba",
        role,
        db_type,
        app,
        tier,
        owner,
    )


def write_grouped_targets(file_path: str, grouped_targets: dict) -> None:
    with open(file_path, "w", encoding="utf-8", newline="\n") as f:
        for labels, targets in grouped_targets.items():
            (
                service,
                environment,
                site,
                team,
                role,
                db_type,
                app,
                tier,
                owner,
            ) = labels

            f.write("- targets:\n")
            for target in sorted(targets):
                f.write(f'    - "{target}"\n')

            f.write("  labels:\n")
            f.write(f'    service: "{service}"\n')
            f.write(f'    environment: "{environment}"\n')
            f.write(f'    site: "{site}"\n')
            f.write(f'    team: "{team}"\n')
            f.write(f'    role: "{role}"\n')
            f.write(f'    db_type: "{db_type}"\n')
            f.write(f'    app: "{app}"\n')
            f.write(f'    tier: "{tier}"\n')
            f.write(f'    owner: "{owner}"\n\n')


def main() -> None:
    if not os.path.exists(INPUT_FILE):
        fail(f"Input file not found: {INPUT_FILE}")

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    node_targets = defaultdict(list)
    oracle_targets = defaultdict(list)
    mssql_targets = defaultdict(list)

    seen_ip_service = set()
    seen_host = set()

    with open(INPUT_FILE, newline="", encoding="utf-8-sig") as csvfile:
        reader = csv.DictReader(csvfile)

        if reader.fieldnames is None:
            fail("CSV header missing")

        missing_columns = [field for field in REQUIRED_FIELDS if field not in reader.fieldnames]
        if missing_columns:
            fail(f"Missing required CSV columns: {', '.join(missing_columns)}")

        for line_no, row in enumerate(reader, start=2):
            validate_row(row, line_no)

            host = row["host"].strip()
            ip = row["ip"].strip()
            app = normalize(row["app"])
            tier = normalize(row["tier"])
            owner = normalize(row["owner"])

            node = normalize(row["node"])
            oracle = normalize(row["oracle"])
            mssql = normalize(row["mssql"])

            if host in seen_host:
                fail(f"Duplicate host detected at line {line_no}: {host}")
            seen_host.add(host)

            if node == "yes":
                service = "node"
                key = labels_key(
                    service=service,
                    role="infrastructure",
                    db_type="none",
                    app=app,
                    tier=tier,
                    owner=owner,
                )
                target = f"{ip}:9100"

                if (service, target) in seen_ip_service:
                    fail(f"Duplicate target detected: {target} for {service}")

                seen_ip_service.add((service, target))
                node_targets[key].append(target)

            if oracle == "yes":
                service = "oracle"
                key = labels_key(
                    service=service,
                    role="database",
                    db_type="oracle",
                    app=app,
                    tier=tier,
                    owner=owner,
                )
                target = f"{ip}:9161"

                if (service, target) in seen_ip_service:
                    fail(f"Duplicate target detected: {target} for {service}")

                seen_ip_service.add((service, target))
                oracle_targets[key].append(target)

            if mssql == "yes":
                service = "mssql"
                key = labels_key(
                    service=service,
                    role="database",
                    db_type="mssql",
                    app=app,
                    tier=tier,
                    owner=owner,
                )
                target = f"{ip}:9182"

                if (service, target) in seen_ip_service:
                    fail(f"Duplicate target detected: {target} for {service}")

                seen_ip_service.add((service, target))
                mssql_targets[key].append(target)

    write_grouped_targets(NODE_FILE, node_targets)
    write_grouped_targets(ORACLE_FILE, oracle_targets)
    write_grouped_targets(MSSQL_FILE, mssql_targets)

    print("[DONE] Targets generated successfully")
    print(f"[INFO] Node groups   : {len(node_targets)}")
    print(f"[INFO] Oracle groups : {len(oracle_targets)}")
    print(f"[INFO] MSSQL groups  : {len(mssql_targets)}")
    print(f"[INFO] Output: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
