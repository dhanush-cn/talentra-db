"""Generates the Phase 1 ER diagram (Mermaid) from the live schema.

Shows the Profile (prf) and Jobs and Applications (job) tables, the two identity anchors
(adm.user_account, org.organisation) and the master tables they lean on most. Enumeration
links to mst.ref_code and audit links to adm.user_account are left out: every table has
them and drawing them would hide the real structure.

Usage: python tools/er_diagram.py > docs/generated/er_phase1.md   (or: make er)
       python tools/er_diagram.py --raw                           (Mermaid source only)
       python tools/er_diagram.py --raw --focus job               (one schema plus the tables it points at)
"""
import os
import sys

import psycopg

DSN = os.environ.get("TALENTRA_DSN", "postgresql://postgres:postgres@localhost:5432/talentra")
SCHEMAS = ["prf", "job"]
EXTRA_TABLES = ["adm.user_account", "org.organisation", "mst.skill", "mst.city", "mst.qualification",
                "mst.institution", "mst.job_role"]
SKIP_COLUMNS = {"created_by", "updated_by", "deleted_by"}

TABLES_SQL = """
SELECT n.nspname || '.' || c.relname
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition
  AND (n.nspname = ANY(%s) OR (n.nspname || '.' || c.relname) = ANY(%s))
ORDER BY 1
"""

FKS_SQL = """
SELECT cn.nspname || '.' || cl.relname AS child,
       pn.nspname || '.' || pl.relname AS parent,
       array_agg(a.attname ORDER BY k.ord) AS columns,
       bool_and(a.attnotnull) AS mandatory,
       EXISTS (SELECT 1 FROM pg_constraint u
               WHERE u.conrelid = c.conrelid AND u.contype IN ('u', 'p') AND u.conkey <@ c.conkey AND c.conkey <@ u.conkey) AS one_to_one
FROM pg_constraint c
JOIN pg_class cl ON cl.oid = c.conrelid JOIN pg_namespace cn ON cn.oid = cl.relnamespace
JOIN pg_class pl ON pl.oid = c.confrelid JOIN pg_namespace pn ON pn.oid = pl.relnamespace
CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
WHERE c.contype = 'f' AND c.conparentid = 0
GROUP BY c.oid, c.conrelid, c.conkey, cn.nspname, cl.relname, pn.nspname, pl.relname
"""

COLUMNS_SQL = """
SELECT a.attname,
       CASE WHEN t.typtype = 'd' THEN t.typname ELSE format_type(a.atttypid, NULL) END,
       EXISTS (SELECT 1 FROM pg_constraint p WHERE p.conrelid = a.attrelid AND p.contype = 'p' AND a.attnum = ANY(p.conkey)),
       EXISTS (SELECT 1 FROM pg_constraint f WHERE f.conrelid = a.attrelid AND f.contype = 'f' AND f.conparentid = 0
               AND a.attnum = ANY(f.conkey) AND f.confrelid <> 'mst.ref_code'::regclass)
FROM pg_attribute a JOIN pg_type t ON t.oid = a.atttypid
WHERE a.attrelid = %s::regclass AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY a.attnum
"""


def entity(name):
    return name.replace(".", "__")


def main():
    raw = "--raw" in sys.argv
    focus = sys.argv[sys.argv.index("--focus") + 1] if "--focus" in sys.argv else None
    with psycopg.connect(DSN) as conn:
        tables = [r[0] for r in conn.execute(TABLES_SQL, (SCHEMAS, EXTRA_TABLES))]
        fks = conn.execute(FKS_SQL).fetchall()
        if focus:
            own = {t for t in tables if t.startswith(focus + ".")}
            parents = {p for c, p, *_ in fks if c in own and p in tables}
            tables = [t for t in tables if t in own or t in parents]
        in_scope = set(tables)
        lines = ["erDiagram"]
        for table in tables:
            lines.append(f"    {entity(table)} {{")
            for name, dtype, is_pk, is_fk in conn.execute(COLUMNS_SQL, (table,)):
                if name in SKIP_COLUMNS or not (is_pk or is_fk or table.split(".")[0] in SCHEMAS and name == "public_id"):
                    continue
                key = "PK" if is_pk else "FK"
                lines.append(f"        {dtype.replace(' ', '_')} {name} {key}")
            lines.append("    }")
        for child, parent, columns, mandatory, one_to_one in fks:
            if child not in in_scope or parent not in in_scope or set(columns) & SKIP_COLUMNS:
                continue
            left = "|o" if one_to_one else "}o"
            right = "||" if mandatory else "o|"
            label = ", ".join(c for c in columns if c != "job_requirement_id" or len(columns) == 1)
            lines.append(f'    {entity(parent)} {right}--{left} {entity(child)} : "{label}"')
    mermaid = "\n".join(lines)
    if raw:
        print(mermaid)
        return
    print("# Phase 1 ER diagram: Profile, Jobs and Applications\n")
    print("Generated from the live schema by `make er`. Enumeration links to `mst.ref_code` and audit links "
          "(`created_by`, `updated_by`) are omitted for readability. Entity names are `<schema>__<table>`.\n")
    print("```mermaid")
    print(mermaid)
    print("```")


if __name__ == "__main__":
    main()
