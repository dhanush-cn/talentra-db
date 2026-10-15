# Talentra database

Operational and analytical database for Talentra, the job search and demand management platform in the Northbridge Workforce Systems hackathon brief. PostgreSQL 16.

Team: Dhanush (scrum master), Bhargav, Ranganath.

## Quick start

Requires PostgreSQL 16 (with `psql`) and Python 3.11+. **New laptop? Follow SETUP.md.** On Windows use `python run.py check|seed|demo` instead of make.

```bash
make deps     # Python packages for tests and tools
make up       # start PostgreSQL 16 in Docker (tuned for a 16 GB laptop)
make check    # rebuild from zero, lint the schema, run the rule-violation tests
```

Without Docker, point the Makefile at any local PostgreSQL 16:

```bash
make check PGHOST=localhost PGUSER=postgres PGPASSWORD=yourpassword
```

## Commands

| Command | What it does |
| --- | --- |
| `make up` / `make down` | start / stop PostgreSQL |
| `make reset` | drop and rebuild the database from `migrations/` |
| `make lint` | check the schema against the Section 5 data standards; fails on any error |
| `make test` | run the rule-violation test suite (each test tries to break a rule) |
| `make check` | reset + lint + test. **Run before every push.** |
| `make dictionary` | regenerate `docs/generated/data_dictionary.md` from the live schema |
| `make er` | regenerate `docs/generated/er_phase1.md` |
| `make seed` | load synthetic data (`SCALE=small`, `medium` or `laptop`) |
| `make psql` | open a psql session |

## Layout

```
migrations/      numbered SQL, applied in order, each in one transaction
  000–099        core framework and master data
  100–299        Profile, Jobs and Applications (Phase 1, whole team)
  300–950        individual modules (see docs/conventions.md for ranges)
tests/           rule-violation tests (pytest), one file per module
generator/       synthetic data generator (python -m generator)
tools/
  lint_schema.sql    compliance linter for Rule groups 1–8
  data_dictionary.py data dictionary generated from column comments
  er_diagram.py      ER diagram (Mermaid) generated from foreign keys
docs/
  conventions.md     the rules every table follows (read this first)
  justification.md   why the design is the way it is (J-01 to J-11)
  deviations.md      justified deviations from the standards
  generated/         generated documents; do not edit by hand
scripts/migrate.sh   migration runner
```

## What is built so far (end of Day 1)

| Area | Status |
| --- | --- |
| Core framework (`core`) | Standard domains for every Rule 3 data type, rejecting Rule 5 sentinels; mandatory actor identity; audit, append-only and soft-delete helpers; monthly and hash partition helpers; PII encryption, HMAC blind index and masking |
| Master data (`mst`) | Languages, enumerations with per-language names and fallback, UI labels, currencies, countries, Indian states, cities, skills, qualifications, institutions, industries, job roles |
| Identity anchors | `adm.user_account`, `org.organisation` (identity columns only; Administration and Organisation extend them) |
| Profile (`prf`, 20 tables) | Candidate, encrypted contacts, education, experience, skills, languages, versioned resumes, projects, assessments, courses, completion scoring, view and activity history, bookmarks, referrals |
| Jobs and Applications (`job`, 18 tables) | Job posts, positions, questionnaires, hash-partitioned applications with a database-enforced pipeline, status history, answers, interviews, offers, joining, shortlists, search history |
| Linter | Rule groups 1–8, reserved words for PostgreSQL and MySQL: 55 tables, 0 errors |
| Tests | 86 rule-violation tests, all passing |
| Generator | `make seed`: candidates (with ~2% injected duplicates and multilingual names), organisations, jobs, applications and full status history; validated before commit |
| Documents | `docs/conventions.md`, `docs/justification.md` (J-01 to J-11), `docs/deviations.md`, generated data dictionary and ER diagram |

Next: Administration and Licences (Dhanush), Gig marketplace (Ranganath) on Day 2; Organisation and Sourcing (Bhargav) on Day 3.

## Seeding

```bash
make seed                 # 10k candidates, 1k jobs, 50k applications (about 30 s)
make seed SCALE=medium    # 100k / 10k / 500k
make seed SCALE=laptop    # 1M / 100k / 5M: the Day 3 target
```

Run `make reset` first for a clean load. Duplicates injected on purpose are listed in `data/duplicates.csv` as ground truth for duplicate detection. Contact encryption is the slowest step (about 0.5 ms per value); plan the laptop-scale load for Day 3 morning.

## Working agreement

- Read `docs/conventions.md` before writing a table.
- Phase 1 tables (`mst`, `prf`, `job`) are shared: announce changes in the group chat before pushing.
- A module is done when it migrates from zero, every column is commented and tagged, `make lint` passes, it has at least 5 rule-violation tests, and the generator covers it.
