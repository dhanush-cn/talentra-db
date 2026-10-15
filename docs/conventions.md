# Talentra schema conventions

Every table in every module follows this document. `make lint` checks most of it automatically; `make test` proves the rules are enforced. If you need to break a rule, record it in `docs/deviations.md` first (a justified deviation scores well; an undocumented one is a defect).

Owner: Dhanush. Changes are agreed at the 6 pm sync.

---

## 1. Engine and layout

- **PostgreSQL 16**, UTF-8, `C.UTF-8` locale, server time zone UTC.
- Extensions: `pgcrypto`, `pg_trgm`, `btree_gist`, `pg_stat_statements` (pgvector only if the stretch module goes ahead).
- **One schema per module.** The schema code is the only abbreviation we use:

| Code | Module | Owner |
| --- | --- | --- |
| `core` | Shared domains, helper functions, triggers | Dhanush |
| `mst` | Master data | Team |
| `prf` | Profile | Team |
| `job` | Jobs and Applications | Team |
| `adm` | Administration | Dhanush |
| `org` | Organisation and account | Bhargav |
| `src` | Sourcing and consultant requests | Bhargav |
| `gig` | Gig marketplace | Ranganath |
| `ntf` | Notifications, preferences and community | Ranganath |
| `ana` | Analytics layer and reporting marts | Ranganath |
| `lic` | Licences, seats, devices and sessions | Dhanush |
| `pay` | Subscriptions, wallet, payments and download history | Dhanush |

## 2. Naming (Rule 1, Rule 8)

| Object | Pattern | Example |
| --- | --- | --- |
| Table | singular `snake_case` noun | `job_requirement`, not `job_requirements` |
| Primary key | `id` | |
| Foreign key column | `<referenced_table>_id`, optionally with a role prefix | `candidate_profile_id`, `parent_industry_id`, `blocker_user_account_id` |
| Enumeration columns | `<role>_code_type_id` + `<role>_ref_code_id` (made by the helper) | `application_status_ref_code_id` |
| Boolean | `is_` / `has_` prefix | `is_active` |
| Money | `<what>_amount` + `currency_id` | `salary_min_amount` |
| Timestamp | `<event>_at` | `submitted_at` |
| Date | `<event>_date` or `start_date` / `end_date` | |
| Primary key constraint | `pk_<table>` | `pk_city` |
| Unique constraint or unique index | `uq_<table>_<columns>` | `uq_skill_normalized_name` |
| Foreign key constraint | `fk_<table>_<column>` | `fk_city_state_id` |
| Check constraint | `ck_<table>_<rule>` | `ck_city_coordinates_pair` |
| Exclusion constraint | `ex_<table>_<rule>` | `ex_subscription_period_no_overlap` |
| Index | `idx_<table>_<columns>` | `idx_application_candidate_profile_id` |
| Trigger | `trg_<table>_<purpose>` | `trg_city_audit` |
| RLS policy | `pol_<table>_<purpose>` | `pol_job_requirement_company_scope` |
| View | `v_<name>` | |
| Materialised view | `mv_<name>` | |
| Analytics tables (`ana`) | `dim_`, `fct_`, `agg_` | `fct_application`, `dim_candidate` |
| Range partition (monthly) | `<parent>_pYYYYMM` | `notification_delivery_p202610` |
| Hash partition | `<parent>_hNN` | `application_h07` |
| Default partition | `<parent>_default` | |

Never use a PostgreSQL or MySQL reserved word: `user` → `user_account`, `order` → `payment_order`, `position` → `job_position`, `rank` → `rank_value`. The linter checks both engines.

## 3. Keys and constraints (Rule 2)

- Primary key: `id bigint GENERATED ALWAYS AS IDENTITY` on every table. No exceptions outside `ana`.
- Externally exposed entities (candidate, job, gig request) also get `public_id uuid NOT NULL DEFAULT gen_random_uuid()` with a unique constraint. URLs and APIs use `public_id`, never `id`.
- Natural keys (email, PAN, GSTIN, source record id) are **unique constraints**, never primary keys.
- Every foreign key states its rules explicitly. Defaults:
  - `ON UPDATE RESTRICT` always (surrogate keys never change).
  - `ON DELETE RESTRICT` for references to master data and to anything with history.
  - `ON DELETE CASCADE` only for pure children that mean nothing alone (a translation, a line item).
  - `ON DELETE SET NULL` only with a `[null: ...]` reason that explains it.
- Every business rule the database can express is a `CHECK`: date ranges, min ≤ max, positive limits, paired columns.
- Non-overlap rules use `EXCLUDE USING gist` with `btree_gist`.
- Concurrency limits (device limit, seats, wallet balance) use row locks (`SELECT ... FOR UPDATE`) inside a function, plus a `CHECK` as the final guard.

## 4. Standard domains (Rule 3)

Use the domain, not a raw type. The domains in `core` enforce the rule wherever they are used.

| Data | Use | Rule enforced |
| --- | --- | --- |
| Identifier | `bigint GENERATED ALWAYS AS IDENTITY` | |
| Person name | `core.person_name` | ≤ 150 chars, any script, trimmed, no sentinels |
| Short or medium text | `core.text_100`, `core.text_255`, `core.text_1000`, `core.text_4000` | stated max length, no sentinels |
| Long content (job description, resume body) | `core.long_text` + `[unbounded: reason]` tag | linter requires the reason |
| Email | `core.email_address` | ≤ 254, lowercase, basic format |
| Phone (plain) | `core.phone_e164` + `country_id` | E.164 with country code |
| Phone or email (PII, encrypted) | `bytea` ciphertext + `<col>_hmac bytea` blind index | see section 8 |
| Tax / registration id | `core.text_100` + `country_id` + `tax_id_type_ref_code_id` | format check per type in the owning module |
| Money | `core.money_amount` (numeric 18,2) + `currency_id` | never float; linter checks the pair |
| Percentage | `core.percentage` | 0–100 |
| Ratio | `core.ratio` | 0–1 |
| Date | `date` | |
| Timestamp | `timestamptz` (UTC); add `source_time_zone core.iana_time_zone` where display needs it | linter rejects `timestamp` |
| Date range | `start_*` / `end_*` + `CHECK (end >= start)`; or a `daterange`/`tstzrange` when an exclusion constraint needs it | |
| Enumeration | `core.add_ref_code_column(...)` | composite FK: value must belong to its own list |
| Boolean | `boolean NOT NULL DEFAULT <x>`; state the default in the comment | linter |
| Coordinates | `core.latitude`, `core.longitude` (6 dp) + `coordinate_source` enumeration | |
| UI label key | `core.label_key` | |
| Machine code | `core.code` | `UPPER_SNAKE` |
| Limits and counts | `core.positive_int`, `core.non_negative_int` | |

## 5. Enumerations

Every fixed list of values lives in `mst.ref_code`, with display names per language in `mst.ref_code_translation`. Never a free-text status column, never a PostgreSQL `ENUM` type.

To add one in your module's migration:

```sql
-- 1. register the list and its values
INSERT INTO mst.code_type (code, english_name, description, owning_module)
VALUES ('GIG_APPLICATION_STATUS', 'Gig application status', 'Stage of an application to a gig request.', 'GIG');
-- (insert the values and English display names the same way as 004_seed_reference_data.sql)

-- 2. add the column pair to your table
SELECT core.add_ref_code_column('gig.gig_application', 'gig_application_status', 'GIG_APPLICATION_STATUS');
-- nullable only with a reason:
SELECT core.add_ref_code_column('prf.work_experience', 'employment_type', 'EMPLOYMENT_TYPE', true, 'not stated by candidate');
```

Every value needs at least an English display name. Hindi and Kannada are added where we have reviewed text.

## 6. Audit and lifecycle (Rule 4)

**Every session identifies its actor.** The application runs `SET LOCAL app.user_id = '<user_account id>'` at the start of each transaction. Migrations and seed scripts use the system account, id 1. A write without an actor fails. This is what makes `created_by` trustworthy.

After `CREATE TABLE`, call exactly one of:

| Table kind | Call | Columns added |
| --- | --- | --- |
| Normal business table | `SELECT core.add_audit_columns('<schema>.<table>');` | `created_at`, `created_by`, `updated_at`, `updated_by` + trigger |
| Append-only (audit trail, ledgers, download and view history) | `SELECT core.add_creation_columns(...)` then `SELECT core.make_append_only(...)` | `created_at`, `created_by`; UPDATE/DELETE/TRUNCATE blocked by trigger and privilege |

Then tag the table's lifecycle in its comment, and add soft delete if needed:

| Tag | Meaning | How |
| --- | --- | --- |
| `[lifecycle:soft_delete]` | user-facing data that must be recoverable or retained | `SELECT core.enable_soft_delete(...)`: adds `deleted_at`/`deleted_by`, hides deleted rows from `talentra_app` via RLS, revokes DELETE |
| `[lifecycle:hard_delete]` | dependent rows with no history value (translations, preferences) | normal `DELETE` |
| `[lifecycle:append_only]` | set by `core.make_append_only` | never changed |
| `[lifecycle:deactivate]` | master data | `is_active = false`; FKs with `ON DELETE RESTRICT` prevent deletion |

**RLS warning.** `enable_soft_delete` creates a permissive `pol_<table>_default_allow` policy so the table is readable. If your module adds a scoping policy (company, blocking, ownership), **drop `pol_<table>_default_allow`** in the same migration, otherwise `true OR your_rule` makes your rule useless. A test for your scoping policy will catch this.

Retention per entity (deletion on request, on inactivity) is stated in the table comment as `[retention: ...]` and implemented by a scheduled function in the owning module.

## 7. Nullability (Rule 5)

- Default to `NOT NULL`.
- A nullable column carries a reason in its comment: `[null: candidate has not provided it]`. The linter rejects nullable columns without one.
- Never store `''`, `'NA'`, `'N/A'`, `'NULL'`, `'NONE'`, `'-'` or `0` to mean missing. The text domains reject these.
- When "not disclosed", "not applicable" and "unknown" mean different things, add a `DISCLOSURE_STATUS` enumeration next to the value and a `CHECK` that the value is set only when disclosed:

```sql
SELECT core.add_ref_code_column('job.job_requirement', 'salary_disclosure', 'DISCLOSURE_STATUS');
-- salary_min_amount is NULL unless salary_disclosure is DISCLOSED (enforce with a CHECK on the ref_code id
-- looked up at migration time, or a small immutable function)
```

## 8. Sensitive data classification (Rule 6)

Every column comment starts with one class tag. The linter rejects columns without one.

| Tag | Meaning | Storage rule |
| --- | --- | --- |
| `[class:public]` | shown without restriction | plain |
| `[class:internal]` | staff and the owning organisation | plain, access by role |
| `[class:personal]` | identifies a person | access control + audit on read where required |
| `[class:sensitive]` | national IDs, tax IDs, bank/payment references, credentials | never readable text: encrypted `bytea`, a `_token` from the external service, or a `_hash` / `_hmac`. The linter rejects readable text. |

- **Passwords**: `crypt(password, gen_salt('bf', 12))`, stored in `password_hash`. Never encrypted, never logged.
- **Email and phone** used for login: encrypted copy + HMAC blind index for exact-match lookup and uniqueness.
- **National ID**: never stored. Keep the verification service's `verification_token` and outcome only.
- **Per-user data keys** (crypto-shredding): personal fields are encrypted with the user's own key; deleting the key erases the data everywhere, including backups.
- **Audit records never contain raw personal data**, only ids and tokens, so erasure never conflicts with the append-only audit trail.

## 9. Multilingual (Rule 7)

- UTF-8 end to end; names in any script (tests include Kannada and Hindi).
- UI strings: `mst.ui_label` (key) + `mst.ui_label_translation` (one row per key and language). Read with `mst.ui_label_text(key, lang)`, which falls back to the default language (English). Keys are never shown to users.
- Enumeration display names: `mst.ref_code_display_name(id, lang)`, same fallback.
- User-entered content (job descriptions, resume text) is stored once, as entered, with a `content_language_id` column (nullable with reason `[null: language not detected]`).

## 10. Comments are the data dictionary

Write the comment in the same migration as the table. The dictionary is generated from them (`make dictionary`), so there is nothing to keep in sync by hand.

```sql
COMMENT ON TABLE  prf.candidate_profile IS 'One profile per candidate user. [lifecycle:soft_delete] [retention: 3 years after last login] [owner:team]';
COMMENT ON COLUMN prf.candidate_profile.full_name IS '[class:personal] Name as the candidate writes it; any script.';
COMMENT ON COLUMN prf.candidate_profile.headline IS '[class:public] [null: candidate has not written one yet] One-line summary.';
```

## 11. Roles and access

| Role | Used by | Notes |
| --- | --- | --- |
| `talentra_owner` | migrations | owns all objects; RLS does not apply to it |
| `talentra_app` | the application | subject to RLS; no UPDATE/DELETE on append-only tables |
| `talentra_readonly` | analytics, dashboards | `ana` schema only |
| `talentra_auditor` | compliance staff | audit and history tables |

Grant per table in the same migration. **Access tests must run as `talentra_app`** (`SET LOCAL ROLE talentra_app`); as owner or superuser, RLS is silently skipped.

## 12. Migrations and workflow

- One file per change, numbered: `migrations/NNN_<module>_<what>.sql`. Number ranges: `000–099` core and master, `100–199` Profile, `200–299` Jobs, `300` adm, `400` org, `500` gig, `600` lic, `700` src, `800` pay, `900` ntf, `950` ana. Within a range, take the next free number.
- Each file starts with `SET ROLE talentra_owner;` and ends with `RESET ROLE;`, runs in one transaction, and must apply cleanly to an empty database.
- Never edit a migration someone else has already built on; add a new one.
- **Phase 1 tables (mst, prf, job) are shared.** Announce any change in the group chat before pushing: every other module points foreign keys at them.
- Before every push: `make check` (rebuild from zero + lint + tests). Red = do not push.

## 13. Definition of done for a module

1. Migrations apply cleanly from zero.
2. Every table and column has a comment with its tags.
3. `make lint` passes with no errors (or the deviation is in `docs/deviations.md` and the allow-list).
4. At least 5 rule-violation tests in `tests/test_<module>.py`, each named after the rule it proves.
5. The data generator covers the module's tables.
