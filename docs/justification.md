# Schema justification

Why the design is the way it is. Each entry states the decision, the options considered, the reason, and the trade-off we accept. Deviations from the Section 5 standards are recorded separately in `deviations.md`.

| # | Decision |
| --- | --- |
| J-01 | PostgreSQL 16 |
| J-02 | BIGINT identity keys, plus a UUID `public_id` on exposed entities |
| J-03 | Gig work is a separate subsystem, not a job type |
| J-04 | One account per person; role-specific profiles attach to it |
| J-05 | One generic enumeration table with type-safe composite foreign keys |
| J-06 | Applications hash-partitioned by job requirement |
| J-07 | The hiring pipeline is enforced by the database, from data |
| J-08 | Contact details encrypted, blind-indexed and masked |
| J-09 | High-volume history tables partitioned by month |
| J-10 | Which workflows are central to the schema, and which are secondary |
| J-11 | Rules are proven by tests and a linter, not asserted |

---

## J-01: PostgreSQL 16

**Decision.** PostgreSQL 16 for the operational and analytical database.

**Options.** PostgreSQL or MySQL 8 (the two allowed by the brief).

**Reason.** Several mandatory rules are enforced natively by PostgreSQL and would have to move into application code on MySQL, which the brief forbids for limits and concurrency:

| Requirement | PostgreSQL | MySQL 8 |
| --- | --- | --- |
| Non-overlapping subscription periods and gig windows (Rules 9, 10, B35, B47) | `EXCLUDE USING gist` | not available; triggers plus locking |
| Recruiter sees only their company; blocked parties cannot see the candidate (Section 3) | Row-Level Security | views and application logic only |
| Soft-deleted rows excluded by default (Rule 4) | restrictive RLS policy + partial indexes | no partial indexes |
| Analytics refresh rules (B58) | materialized views | not available |
| Foreign keys on partitioned tables (100M applications) | supported | not supported |
| Standard domains (Rule 3) | `CREATE DOMAIN` with checks | not available |

**Trade-off.** RLS adds a per-row filter cost, measured on Day 4. The partition key must be part of every unique constraint on a partitioned table (see J-06 and D-04).

## J-02: BIGINT identity keys with a public UUID

**Decision.** Every primary key is `id bigint GENERATED ALWAYS AS IDENTITY`. Candidate, job, gig request, user account and organisation also carry `public_id uuid`, used in URLs and APIs.

**Reason.** At 100M applications, every index on a key column is roughly half the size with 8-byte keys instead of 16-byte UUIDs, and sequential keys insert at the right edge of the B-tree instead of randomly. The UUID stops anyone enumerating candidates by guessing `/candidate/1234`.

**Trade-off.** Ids from legacy systems never become our keys; they are kept as natural keys (`source_system` + `source_record_id`, unique).

## J-03: Gig work is a separate subsystem

**Decision.** Gig requests, gig worker profiles, gig applications, assignments and earnings live in their own `gig` schema. They share identity (`adm.user_account`), organisations (`org.organisation`) and master data (skills, cities, currencies) with the rest of the platform, but not the job and application tables. `job.job_requirement` carries a check constraint that rejects the gig category.

**Options considered.**

| | A. Gigs as a job type in `job_requirement` | B. Common parent table with job and gig subtypes | C. Separate subsystem on shared foundations (chosen) |
| --- | --- | --- | --- |
| Integrity | Gig-only columns (window, price, rate basis, handoff reference) are empty for every regular job, so many nullable columns and weaker checks | Good: each subtype has its own columns | Good: every column applies to every row |
| Business rules | Gig applications are one-way, fulfilled externally and rated; regular applications run a hiring pipeline. One status machine would serve both badly | Still one application table, same problem | Each side has its own lifecycle and constraints, e.g. no overlapping windows per gig worker |
| Reporting | Easiest: one table | One join to the parent for every query | Needs a combined view; solved in analytics with shared dimensions (skill, city, organisation, date) |
| Performance | Largest table carries rows it rarely needs | Extra join on every hiring query (the busiest path) | Hiring queries touch only hiring tables |
| Future change | A gig change risks the core hiring path | Changes to the parent affect both | Each side changes independently |

**Reason.** The brief's gig rules differ from hiring on almost every axis: time windows and pricing, one-way applications, external fulfilment with a handoff reference, earnings from an outside system, favourites and blacklists, and ratings. Option A would fill the busiest table with columns that are empty for most rows. Option B adds a join to every hiring query to make gig reporting slightly easier. Option C keeps both paths clean, and the cross-cutting reporting need is met where it belongs: the analytics layer.

**What stays shared.** One person can be both a candidate and a gig worker: both profiles attach to the same `user_account`. Skills, cities and organisations are the same rows, so "demand for PostgreSQL in Bengaluru across jobs and gigs" is a simple query in the analytics schema. Completed gig assignments appear on the candidate's profile as `prf.candidate_project` rows of kind `GIG`.

**Trade-off accepted.** A combined "all opportunities" listing needs a `UNION` view. We consider that cheaper than weakening integrity on the hiring tables.

## J-04: One account per person, role profiles attached

**Decision.** `adm.user_account` holds identity only (type, status, language). Candidate, gig worker and recruiter information lives in role-specific tables that reference it. Credentials, roles, permissions, consent and blocking are added by the Administration module.

**Reason.** One person can hold several roles over time; login, profile, PII and retention rules differ by role. Sub-roles inside an employer (posting, interviewing, pipeline) are out of scope for this version; they can be added later as rows in the role and permission tables of the Administration module, scoped by organisation, without changing any Phase 1 table.

## J-05: Generic enumeration table with type-safe composite keys

**Decision.** Every fixed list of values is a row in `mst.code_type` with values in `mst.ref_code` and display names per language in `mst.ref_code_translation` (Rule 3). A column holding a value is a pair: `<role>_code_type_id` (fixed by a check) and `<role>_ref_code_id`, with a composite foreign key to `mst.ref_code (code_type_id, id)`.

**Options.** One lookup table per list (strong keys, ~60 tables); one generic table with a plain key (few tables, but a status column could hold a gender value); one generic table with a composite key (chosen).

**Reason.** One translation mechanism and one admin screen for every list, and the database still guarantees a column only holds values from its own list. A test proves it (`test_rule3_enumeration_value_must_belong_to_its_own_type`).

**Trade-off.** 8 extra bytes per enumeration per row (D-03), measured in the extrapolation.

## J-06: Applications hash-partitioned by job requirement

**Decision.** `job.application` and its children (`application_status_history`, `application_answer`) are hash-partitioned on `job_requirement_id` into 16 partitions. Children carry `job_requirement_id` and reference `(id, job_requirement_id)`.

**Options.**

| Partition key | Effect on "one application per candidate per job" | Effect on queries |
| --- | --- | --- |
| Range by `applied_at` | Cannot be enforced: a unique constraint must include the partition key | Good for archiving and time-sliced analytics |
| Hash by `candidate_profile_id` | Enforceable | "My applications" fast; employer pipeline view visits every partition |
| Hash by `job_requirement_id` (chosen) | Enforceable | Employer pipeline view (the busiest screen) hits one partition; "my applications" visits all 16 |

**Reason.** The uniqueness rule is a correctness requirement; time-based archiving is not. Between the two hash options, employers and recruiters run many more queries per application than candidates do.

**Trade-off and prediction.** The candidate's "my applications" query must probe all 16 partition indexes. We expect it to be the first query to degrade at 100M rows, and the Day 4 extrapolation will measure it. Mitigation if needed: a small per-candidate summary table maintained by trigger.

## J-07: The hiring pipeline is enforced by the database

**Decision.** Allowed status moves are rows in `job.application_status_transition`. A trigger rejects any insert or update that is not an allowed move, sets `status_changed_at`, and writes `application_status_history`. A rejection must carry a reason; joined, rejected and withdrawn are final.

**Reason.** Pipeline integrity (no `APPLIED` straight to `JOINED`, no reopening a rejected application) holds no matter which service writes. The history every candidate sees ("application status tracking") cannot be skipped or edited. Changing the pipeline is a data change, not a code change.

**Trade-off.** Bulk loading must either replay each stage or load with triggers disabled and then validate. The generator does the second and runs five validation queries before committing (see `generator/`).

## J-08: Contact details encrypted, blind-indexed and masked

**Decision.** Candidate email and phone are stored as `value_encrypted` (pgcrypto, AES-256), `value_hmac` (HMAC-SHA256 of the normalised value) and `value_masked` (`pr***@gmail.com`). Keys come from the application's secret store per session, never from the database.

**Reason.** The HMAC lets the database find a candidate by email at login, enforce uniqueness, and detect duplicate candidates across legacy imports, all without decrypting. The masked value is what recruiters see until they download a profile, which is the credit-charged, logged action in the Payments module. This ties PII protection to the business model.

**Trade-off.** Encryption costs about 0.5 ms per value on load (measured: 20,000 contacts in 10 s). Day 4 replaces the single key with per-user keys so an erasure request can be honoured by deleting the key (crypto-shredding).

## J-09: High-volume history partitioned by month

**Decision.** Profile views, candidate activity and job searches are append-only and range-partitioned by month (`<table>_pYYYYMM`, plus `<table>_default`).

**Reason.** Retention becomes `DROP TABLE` of an old partition instead of a multi-million-row `DELETE`, and "last 30 days" questions touch one or two partitions.

## J-10: Central and secondary workflows

The brief asks which workflows are central to the schema. We ranked them by how much data they generate, how many rules they carry and how much of the platform depends on them.

| Workflow | Classification | Why |
| --- | --- | --- |
| Candidate registration and profile building | Central | Every other workflow reads the profile; 10M profiles is the sizing driver |
| Job search, application and status tracking | Central | Largest table (100M applications); most rules (uniqueness, pipeline, history) |
| Employer registration, verification and job posting | Central | Scope for every recruiter permission and consultant rule |
| Wallet recharge and credit consumption | Central | Money: append-only ledger, no negative balances, audit |
| Sourcing, consultant requests and bulk outreach | Central | Carries the consultant-openness and blocking rules |
| Blocking of users and companies | Central | A visibility rule every candidate read must respect |
| Licences, devices and sessions | Central | Hard limits under concurrency (Rule 9) |
| Gig requests and applications | Central (own subsystem) | Primary revenue category; separate rules (J-03) |
| Questionnaires | Secondary | Attached to jobs; low volume |
| Resume creation and self-assessment | Secondary | Enrich the profile; do not drive other workflows |
| Notifications and job alerts | Secondary for rules, high for volume | Few rules, but the highest write rate; designed for throughput |
| Support tickets and FAQs | Secondary | Low volume, few cross-module rules |

## J-11: Rules are proven, not asserted

**Decision.** Every rule the database enforces has a test that tries to break it (`tests/`), and the schema is checked against the naming, domain, audit, nullability and classification standards by a linter that queries the system catalog (`tools/lint_schema.sql`). The data dictionary and ER diagram are generated from the schema.

**Reason.** The review can watch the database refuse every violation, and the documents cannot drift from what is deployed.
