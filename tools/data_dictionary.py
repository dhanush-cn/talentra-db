"""Generates the data dictionary from the live database.

The schema is the single source of truth: every table and column comment carries
its tags ([class:...], [null: ...], [lifecycle:...], [enum:...]), so the dictionary
can never drift from what is actually deployed.

Usage:  python tools/data_dictionary.py > docs/generated/data_dictionary.md
        (or: make dictionary)
"""
import os
import re
import sys
from datetime import datetime, timezone

import psycopg

DSN = os.environ.get("TALENTRA_DSN", "postgresql://postgres:postgres@localhost:5432/talentra")
MODULE_SCHEMAS = ["mst", "prf", "job", "adm", "org", "gig", "lic", "src", "pay", "ntf", "ana"]
MODULE_NAMES = {
    "mst": "Master data", "prf": "Profile", "job": "Jobs and Applications",
    "adm": "Administration", "org": "Organisation and account", "gig": "Gig marketplace",
    "lic": "Licences, seats, devices and sessions", "src": "Sourcing and consultant requests",
    "pay": "Subscriptions, wallet, payments and download history",
    "ntf": "Notifications, preferences and community", "ana": "Analytics layer and reporting marts",
}
TAG = re.compile(r"\[(\w+):\s*([^\]]*)\]")

TABLES_SQL = """
SELECT n.nspname, c.relname, coalesce(obj_description(c.oid, 'pg_class'), ''),
       c.relkind = 'p' AS is_partitioned, c.relrowsecurity
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition AND n.nspname = ANY(%s)
ORDER BY array_position(%s, n.nspname::text), c.relname
"""

COLUMNS_SQL = """
SELECT a.attname,
       CASE WHEN t.typtype = 'd' THEN tn.nspname || '.' || t.typname
            ELSE format_type(a.atttypid, a.atttypmod) END,
       NOT a.attnotnull,
       coalesce(col_description(a.attrelid, a.attnum), '')
FROM pg_attribute a
JOIN pg_type t ON t.oid = a.atttypid
JOIN pg_namespace tn ON tn.oid = t.typnamespace
WHERE a.attrelid = %s::regclass AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY a.attnum
"""


def split_tags(comment):
    tags = {k: v.strip() for k, v in TAG.findall(comment)}
    text = TAG.sub("", comment).strip()
    return tags, re.sub(r"\s{2,}", " ", text)


def cell(value):
    return (value or "").replace("|", "\\|")


def main():
    out = sys.stdout
    with psycopg.connect(DSN) as conn:
        tables = conn.execute(TABLES_SQL, (MODULE_SCHEMAS, MODULE_SCHEMAS)).fetchall()
        out.write("# Talentra data dictionary\n\n")
        out.write(f"Generated from the live schema on {datetime.now(timezone.utc):%Y-%m-%d %H:%M} UTC. "
                  "Do not edit by hand: change the column comments and regenerate.\n\n")
        out.write(f"{len(tables)} tables.\n")

        current_schema = None
        for schema, table, comment, partitioned, rls in tables:
            if schema != current_schema:
                out.write(f"\n## {MODULE_NAMES[schema]} (`{schema}`)\n")
                current_schema = schema
            tags, text = split_tags(comment)
            flags = [f"lifecycle: {tags.get('lifecycle', 'MISSING')}"]
            if partitioned:
                flags.append("partitioned")
            if rls:
                flags.append("row-level security")
            out.write(f"\n### `{schema}.{table}`\n\n{text}\n\n_{' · '.join(flags)}_\n\n")
            out.write("| Column | Type / domain | Null | Class | Description |\n")
            out.write("| --- | --- | --- | --- | --- |\n")
            for name, dtype, nullable, col_comment in conn.execute(COLUMNS_SQL, (f"{schema}.{table}",)):
                ctags, ctext = split_tags(col_comment)
                null_text = f"yes: {ctags['null']}" if nullable else "no"
                if "enum" in ctags:
                    ctext = f"{ctext} Enumeration `{ctags['enum']}`."
                out.write(f"| `{name}` | `{dtype}` | {cell(null_text)} | {ctags.get('class', 'MISSING')} | {cell(ctext)} |\n")


if __name__ == "__main__":
    main()
