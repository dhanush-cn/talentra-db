# Deviations from the data standards

The brief says a justified deviation is scored well and an undocumented one is a defect. Every deviation lives here, with the matching allow-list entry in `tools/lint_schema.sql`.

Format for each entry:

```
## D-NN: <short title>
- Rule: <rule group and rule>
- Objects: <schema.table.column>
- Deviation: <what we do differently>
- Reason: <why>
- Risk: <what could go wrong>
- Mitigation: <how we contain it>
```

---

## D-01: Enumeration columns are named after their role, not `ref_code_id`
- Rule: 1 (foreign keys use the referenced table name followed by `_id`)
- Objects: every `<role>_ref_code_id` column
- Deviation: a table can hold several enumerations, so each column is `<role>_ref_code_id` (e.g. `application_status_ref_code_id`) rather than a bare `ref_code_id`.
- Reason: a bare name would be ambiguous and impossible with two enumerations on one table.
- Risk: none; the name still ends with the referenced table name and `_id`.
- Mitigation: the linter accepts a role prefix and still checks the `<table>_id` suffix.

## D-02: Audit columns `created_by`, `updated_by`, `deleted_by` do not end in `_id`
- Rule: 1 (foreign key naming)
- Objects: audit columns on every table
- Deviation: the brief itself mandates these names (Rule 4); they reference `adm.user_account`.
- Reason: Rule 4 names them explicitly.
- Risk: none.
- Mitigation: the linter exempts exactly these three names.

## D-03: Enumeration type column per enumeration
- Rule: 3 (enumeration)
- Objects: every `<role>_code_type_id` column
- Deviation: each enumeration uses two columns (type and value) instead of one.
- Reason: a composite foreign key `(code_type_id, ref_code_id)` is the only way to stop a column holding a value from the wrong list while using one shared lookup table.
- Risk: 8 extra bytes per enumeration per row (about 0.8 GB across 100M applications per enumeration).
- Mitigation: measured in the extrapolation; the type column is constant so it compresses in backups.

## D-04: Partitioned tables have a primary key of (id, partition key)
- Rule: 2 (surrogate primary key `id`)
- Objects: every partitioned table, e.g. `prf.profile_view_event (id, viewed_at)`, `job.application (id, job_requirement_id)`
- Deviation: the primary key is `id` plus the partition key, not `id` alone.
- Reason: PostgreSQL requires every unique constraint on a partitioned table to include the partition key. Partitioning is what keeps 100M-row tables manageable (Section 6 extrapolation).
- Risk: `id` alone is not guaranteed unique by a constraint; child tables must reference `(id, partition key)`.
- Mitigation: `id` is an identity column, so the database never generates a duplicate; the linter requires `id` to be the first primary-key column; children carry the partition key and use a composite foreign key.
