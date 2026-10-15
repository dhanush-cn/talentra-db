"""Talentra synthetic data generator (Day 1 skeleton).

    python -m generator --scale small        # 10k candidates, 1k jobs, 50k applications (minutes)
    python -m generator --scale laptop       # 1M candidates, 100k jobs, 5M applications (Day 3 target)
    python -m generator --candidates 50000 --jobs 5000 --applications 250000

How it loads:
  1. Rows are generated in Python with a fixed random seed (repeatable runs).
  2. Each batch is streamed with COPY into a temporary staging table (fast).
  3. INSERT ... SELECT moves staging rows into the real tables with OVERRIDING SYSTEM VALUE,
     so ids are known up front and foreign keys line up. Contact details are encrypted and
     blind-indexed inside the database (core.pii_encrypt / core.pii_hmac) on the way in.
  4. Applications and their status history are bulk-loaded with triggers disabled
     (session_replication_role = replica) because the pipeline trigger would otherwise
     force every application through each stage one UPDATE at a time. Integrity is then
     re-checked by explicit validation queries at the end of the run.

Covered so far: accounts, candidates, contacts, skills, education, experience, preferred
locations, organisations, recruiters, jobs, positions, job skills, applications, history.
Day 3 extends it to every module.

Data-quality issues injected on purpose (ground truth written to data/duplicates.csv):
  * ~2% of candidates are near-duplicates of an earlier candidate: same phone number,
    name spelled differently, re-imported from a legacy system with its own record id.
"""
import argparse
import csv
import io
import os
import random
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import psycopg

from generator.names import EMAIL_DOMAINS, make_name, name_variant

SCALES = {
    "small":  {"candidates": 10_000,    "jobs": 1_000,   "applications": 50_000},
    "medium": {"candidates": 100_000,   "jobs": 10_000,  "applications": 500_000},
    "laptop": {"candidates": 1_000_000, "jobs": 100_000, "applications": 5_000_000},
}

DUPLICATE_SHARE = 0.02
NOW = datetime(2026, 10, 15, tzinfo=timezone.utc)
HISTORY_START = datetime(2024, 1, 1, tzinfo=timezone.utc)

# City weights (share of candidates); the rest are spread over other seeded cities.
CITY_WEIGHTS = {
    "Bengaluru": 18, "Mumbai": 10, "New Delhi": 7, "Gurugram": 4, "Noida": 4, "Hyderabad": 10,
    "Chennai": 9, "Pune": 8, "Kolkata": 5, "Ahmedabad": 3,
}

# Final application status distribution (sums to 100).
STATUS_WEIGHTS = {
    "APPLIED": 40, "SHORTLISTED": 20, "INTERVIEWED": 10, "OFFERED": 3, "JOINED": 2, "REJECTED": 22, "WITHDRAWN": 3,
}
PIPELINE = ["APPLIED", "SHORTLISTED", "INTERVIEWED", "OFFERED", "JOINED"]

JOB_STATUS_WEIGHTS = {"PUBLISHED": 60, "CLOSED": 25, "PAUSED": 5, "EXPIRED": 5, "DRAFT": 5}

BATCH = 50_000


def log(message):
    print(f"[{datetime.now():%H:%M:%S}] {message}", flush=True)


class Lookups:
    """ids of reference data, loaded once."""

    def __init__(self, conn):
        self.ref = {
            (t, c): i
            for t, c, i in conn.execute(
                "SELECT ct.code, rc.code, rc.id FROM mst.ref_code rc JOIN mst.code_type ct ON ct.id = rc.code_type_id"
            )
        }
        self.cities = dict(conn.execute("SELECT english_name, id FROM mst.city"))
        self.skills = [r[0] for r in conn.execute("SELECT id FROM mst.skill ORDER BY id")]
        self.qualifications = [r[0] for r in conn.execute("SELECT id FROM mst.qualification ORDER BY id")]
        self.institutions = [r[0] for r in conn.execute("SELECT id FROM mst.institution ORDER BY id")]
        self.job_roles = [r[0] for r in conn.execute("SELECT id FROM mst.job_role ORDER BY id")]
        self.industries = [r[0] for r in conn.execute("SELECT id FROM mst.industry ORDER BY id")]
        self.default_language = conn.execute("SELECT id FROM mst.language WHERE is_default").fetchone()[0]
        self.languages = [r[0] for r in conn.execute("SELECT id FROM mst.language ORDER BY sort_order")]
        self.inr = conn.execute("SELECT id FROM mst.currency WHERE iso_code = 'INR'").fetchone()[0]
        self.india = conn.execute("SELECT id FROM mst.country WHERE iso2_code = 'IN'").fetchone()[0]

        weighted = [(self.cities[c], w) for c, w in CITY_WEIGHTS.items() if c in self.cities]
        remaining = [i for n, i in self.cities.items() if n not in CITY_WEIGHTS]
        spread = (100 - sum(w for _, w in weighted)) / max(len(remaining), 1)
        self.city_ids = [i for i, _ in weighted] + remaining
        self.city_weights = [w for _, w in weighted] + [spread] * len(remaining)

    def code(self, code_type, code):
        return self.ref[(code_type, code)]


def next_id(conn, table):
    return conn.execute(f"SELECT coalesce(max(id), 0) + 1 FROM {table}").fetchone()[0]


def copy_rows(conn, staging, columns, rows):
    with conn.cursor().copy(f"COPY {staging} ({', '.join(columns)}) FROM STDIN") as copy:
        for row in rows:
            copy.write_row(row)


def random_time(rng, start, end):
    return start + timedelta(seconds=rng.randint(0, int((end - start).total_seconds())))


def zipf_choice(rng, n, skew=1.1):
    """Index in [0, n) with a long tail: a few items are very popular (skills, jobs)."""
    return min(int(rng.paretovariate(skew)) - 1, n - 1) if n else 0


# ---------------------------------------------------------------------------
# Candidates
# ---------------------------------------------------------------------------

def generate_candidates(conn, rng, lk, count, out_dir):
    log(f"candidates: generating {count:,}")
    first_user = next_id(conn, "adm.user_account")
    first_profile = next_id(conn, "prf.candidate_profile")

    conn.execute("""CREATE TEMP TABLE stg_candidate (
        user_id bigint, profile_id bigint, full_name text, city_id bigint, date_of_birth date,
        is_fresher boolean, experience_months int, notice_days int, salary_disclosed boolean,
        salary numeric, source_code text, source_record_id text, duplicate_of bigint,
        last_active_at timestamptz, gender text) ON COMMIT DROP""")
    conn.execute("""CREATE TEMP TABLE stg_contact (
        profile_id bigint, kind text, value text, is_primary boolean, is_verified boolean) ON COMMIT DROP""")
    conn.execute("""CREATE TEMP TABLE stg_child (
        kind text, profile_id bigint, ref_id bigint, ref2_id bigint, extra numeric, start_date date, end_date date,
        label text) ON COMMIT DROP""")

    candidates, contacts, children, duplicates = [], [], [], []
    phones = []   # (profile_id, phone, name) of originals, for duplicates

    for n in range(count):
        user_id, profile_id = first_user + n, first_profile + n
        is_duplicate = phones and rng.random() < DUPLICATE_SHARE
        if is_duplicate:
            original_id, phone, original_name = rng.choice(phones)
            name = name_variant(rng, original_name)
            email_base = f"dup{profile_id}"
            source, source_record = "LEGACY_ATS", f"ATS-{profile_id:09d}"
            duplicates.append((profile_id, original_id))
        else:
            name, email_base = make_name(rng)
            phone = f"+91{rng.choice('6789')}{rng.randint(0, 999_999_999):09d}"
            source = rng.choices(["DIRECT", "LEGACY_ATS", "LEGACY_CRM", "CAMPUS_DRIVE"], [80, 10, 5, 5])[0]
            source_record = None if source == "DIRECT" else f"{source[:3]}-{profile_id:09d}"
            phones.append((profile_id, phone, name))

        is_fresher = rng.random() < 0.25
        experience = 0 if is_fresher else int(min(rng.lognormvariate(3.8, 0.8), 480))
        disclosed = rng.random() < 0.4
        salary = round(rng.lognormvariate(13.4, 0.6), -3) if disclosed and not is_fresher else None
        candidates.append((
            user_id, profile_id, name,
            rng.choices(lk.city_ids, lk.city_weights)[0] if rng.random() < 0.95 else None,
            (NOW - timedelta(days=rng.randint(20 * 365, 55 * 365))).date() if rng.random() < 0.8 else None,
            is_fresher, experience if rng.random() < 0.9 or is_fresher else None,
            rng.choice([0, 15, 30, 60, 90]) if rng.random() < 0.7 else None,
            salary is not None, salary, source, source_record, None,
            random_time(rng, HISTORY_START, NOW) if rng.random() < 0.97 else None,
            rng.choices(["FEMALE", "MALE", "NON_BINARY", "PREFER_NOT_TO_SAY", None], [42, 48, 1, 4, 5])[0],
        ))

        email = f"{email_base.lower().replace(' ', '').replace(chr(39), '')}{rng.randint(1, 9999)}@{rng.choice(EMAIL_DOMAINS)}"
        contacts.append((profile_id, "EMAIL", email, True, rng.random() < 0.7))
        contacts.append((profile_id, "PHONE", phone, True, rng.random() < 0.8))

        for skill_n in rng.sample(range(len(lk.skills)), k=min(rng.randint(3, 10), len(lk.skills))):
            children.append(("skill", profile_id, lk.skills[zipf_choice(rng, len(lk.skills)) if rng.random() < 0.5 else skill_n],
                             None, round(rng.uniform(0.5, 10), 1), None, None, None))
        for _ in range(rng.randint(1, 2)):
            start = (NOW - timedelta(days=rng.randint(4 * 365, 25 * 365))).date()
            children.append(("education", profile_id, rng.choice(lk.qualifications), rng.choice(lk.institutions),
                             round(rng.uniform(5.5, 9.8), 2), start, start + timedelta(days=rng.choice([2, 3, 4]) * 365), None))
        if not is_fresher:
            cursor = (NOW - timedelta(days=30 * max(experience, 1))).date()
            jobs = rng.randint(1, 3)
            for j in range(jobs):
                end = None if j == jobs - 1 else cursor + timedelta(days=rng.randint(200, 1200))
                if end and end > NOW.date():
                    end = None
                children.append(("experience", profile_id, rng.choice(lk.job_roles), None, None, cursor, end,
                                 rng.choice(["Infosys", "TCS", "Wipro", "Flipkart", "Razorpay", "Zoho", "Swiggy",
                                             "HDFC Bank", "Accenture", "Local Business"])))
                if end is None:
                    break
                cursor = end + timedelta(days=rng.randint(0, 60))
        for city in set(rng.choices(lk.city_ids, lk.city_weights, k=rng.randint(1, 3))):
            children.append(("location", profile_id, city, None, None, None, None, None))

        if len(candidates) >= BATCH or n == count - 1:
            copy_rows(conn, "stg_candidate",
                      ["user_id", "profile_id", "full_name", "city_id", "date_of_birth", "is_fresher",
                       "experience_months", "notice_days", "salary_disclosed", "salary", "source_code",
                       "source_record_id", "duplicate_of", "last_active_at", "gender"], candidates)
            copy_rows(conn, "stg_contact", ["profile_id", "kind", "value", "is_primary", "is_verified"], contacts)
            copy_rows(conn, "stg_child", ["kind", "profile_id", "ref_id", "ref2_id", "extra", "start_date", "end_date", "label"], children)
            candidates, contacts, children = [], [], []

    log("candidates: loading accounts and profiles")
    conn.execute("""
        INSERT INTO adm.user_account (id, preferred_language_id, user_type_ref_code_id, account_status_ref_code_id, last_login_at)
        OVERRIDING SYSTEM VALUE
        SELECT user_id, %s, mst.ref_code_id('USER_TYPE', 'CANDIDATE'), mst.ref_code_id('ACCOUNT_STATUS', 'ACTIVE'), last_active_at
        FROM stg_candidate""", (lk.default_language,))
    conn.execute("""
        INSERT INTO prf.candidate_profile (id, user_account_id, full_name, current_city_id, date_of_birth,
            is_fresher, total_experience_months, notice_period_days, salary_currency_id, current_salary_amount,
            current_salary_disclosure_ref_code_id, expected_salary_disclosure_ref_code_id,
            profile_visibility_ref_code_id, source_system_ref_code_id, source_record_id,
            last_active_at, gender_ref_code_id)
        OVERRIDING SYSTEM VALUE
        SELECT profile_id, user_id, full_name, city_id, date_of_birth, is_fresher, experience_months, notice_days,
               CASE WHEN salary_disclosed THEN %s END, salary,
               mst.ref_code_id('DISCLOSURE_STATUS', CASE WHEN salary_disclosed THEN 'DISCLOSED'
                                                         WHEN is_fresher THEN 'NOT_APPLICABLE' ELSE 'NOT_DISCLOSED' END),
               mst.ref_code_id('DISCLOSURE_STATUS', 'NOT_DISCLOSED'),
               mst.ref_code_id('PROFILE_VISIBILITY', 'PUBLIC'),
               mst.ref_code_id('SOURCE_SYSTEM', source_code), source_record_id, last_active_at,
               CASE WHEN gender IS NOT NULL THEN mst.ref_code_id('GENDER', gender) END
        FROM stg_candidate""", (lk.inr,))

    log("candidates: encrypting and loading contacts")
    conn.execute("""
        INSERT INTO prf.candidate_contact (candidate_profile_id, contact_type_ref_code_id, value_encrypted,
            value_hmac, value_masked, phone_country_id, is_primary, is_verified, verified_at)
        SELECT profile_id, mst.ref_code_id('CONTACT_TYPE', kind), core.pii_encrypt(value), core.pii_hmac(value),
               CASE kind WHEN 'EMAIL' THEN core.mask_email(value) ELSE core.mask_phone(value) END,
               CASE kind WHEN 'EMAIL' THEN NULL ELSE %s END, is_primary, is_verified,
               CASE WHEN is_verified THEN now() END
        FROM stg_contact""", (lk.india,))

    log("candidates: loading skills, education, experience, locations")
    conn.execute("""
        INSERT INTO prf.candidate_skill (candidate_profile_id, skill_id, years_of_experience)
        SELECT DISTINCT ON (profile_id, ref_id) profile_id, ref_id, extra FROM stg_child WHERE kind = 'skill'""")
    conn.execute("""
        INSERT INTO prf.candidate_education (candidate_profile_id, qualification_id, institution_id, start_date, end_date,
            score_value, score_scale_ref_code_id)
        SELECT profile_id, ref_id, ref2_id, start_date, end_date,
               extra, mst.ref_code_id('SCORE_SCALE', 'CGPA_10')
        FROM stg_child WHERE kind = 'education'""")
    conn.execute("""
        INSERT INTO prf.candidate_work_experience (candidate_profile_id, employer_name, designation, job_role_id,
            start_date, end_date, is_current)
        SELECT c.profile_id, c.label, r.english_name, c.ref_id, c.start_date, c.end_date, c.end_date IS NULL
        FROM stg_child c JOIN mst.job_role r ON r.id = c.ref_id WHERE c.kind = 'experience'""")
    conn.execute("""
        INSERT INTO prf.candidate_preferred_location (candidate_profile_id, city_id)
        SELECT DISTINCT profile_id, ref_id FROM stg_child WHERE kind = 'location'""")

    out_dir.mkdir(parents=True, exist_ok=True)
    with open(out_dir / "duplicates.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["duplicate_candidate_profile_id", "original_candidate_profile_id"])
        writer.writerows(duplicates)
    log(f"candidates: done ({len(duplicates):,} injected duplicates -> {out_dir / 'duplicates.csv'})")
    return list(range(first_profile, first_profile + count))


# ---------------------------------------------------------------------------
# Organisations, recruiters and jobs
# ---------------------------------------------------------------------------

def generate_jobs(conn, rng, lk, count):
    organisations = max(count // 20, 10)
    log(f"jobs: generating {organisations:,} organisations and {count:,} jobs")
    first_org = next_id(conn, "org.organisation")
    first_user = next_id(conn, "adm.user_account")
    first_job = next_id(conn, "job.job_requirement")

    conn.execute("CREATE TEMP TABLE stg_org (id bigint, name text, recruiter_id bigint) ON COMMIT DROP")
    copy_rows(conn, "stg_org", ["id", "name", "recruiter_id"],
              [(first_org + i, f"Company {first_org + i:06d}", first_user + i) for i in range(organisations)])
    conn.execute("""
        INSERT INTO adm.user_account (id, preferred_language_id, user_type_ref_code_id, account_status_ref_code_id)
        OVERRIDING SYSTEM VALUE
        SELECT recruiter_id, %s, mst.ref_code_id('USER_TYPE', 'RECRUITER'), mst.ref_code_id('ACCOUNT_STATUS', 'ACTIVE')
        FROM stg_org""", (lk.default_language,))
    conn.execute("""
        INSERT INTO org.organisation (id, legal_name, display_name, country_id, organisation_type_ref_code_id,
            account_status_ref_code_id)
        OVERRIDING SYSTEM VALUE
        SELECT id, name || ' Private Limited', name, %s, mst.ref_code_id('ORGANISATION_TYPE', 'EMPLOYER'),
               mst.ref_code_id('ACCOUNT_STATUS', 'ACTIVE')
        FROM stg_org""", (lk.india,))

    conn.execute("""CREATE TEMP TABLE stg_job (
        id bigint, org_id bigint, poster_id bigint, title text, role_id bigint, industry_id bigint,
        min_exp int, max_exp int, disclosed boolean, sal_min numeric, sal_max numeric, open_to_consultants boolean,
        status text, published_at timestamptz, closed_at timestamptz, category text, employment text, work text,
        city_id bigint, openings int) ON COMMIT DROP""")
    conn.execute("CREATE TEMP TABLE stg_job_skill (job_id bigint, skill_id bigint, mandatory boolean) ON COMMIT DROP")

    role_names = dict(conn.execute("SELECT id, english_name FROM mst.job_role"))
    jobs, job_skills = [], []
    for n in range(count):
        job_id = first_job + n
        org = first_org + zipf_choice(rng, organisations, 1.3)
        role = rng.choice(lk.job_roles)
        status = rng.choices(list(JOB_STATUS_WEIGHTS), JOB_STATUS_WEIGHTS.values())[0]
        published = None if status == "DRAFT" else random_time(rng, HISTORY_START, NOW - timedelta(days=1))
        min_exp = rng.choice([0, 0, 12, 24, 36, 60, 96])
        disclosed = rng.random() < 0.55
        sal_min = round(rng.uniform(3, 30) * 100_000, -4) if disclosed else None
        jobs.append((
            job_id, org, org - first_org + first_user, f"{role_names[role]}", role, rng.choice(lk.industries),
            min_exp, min_exp + rng.choice([24, 36, 60]) if rng.random() < 0.7 else None,
            disclosed, sal_min, round(sal_min * rng.uniform(1.1, 1.8), -4) if sal_min else None,
            rng.random() < 0.3, status, published,
            published + timedelta(days=rng.randint(1, 120)) if status == "CLOSED" else None,
            rng.choices(["PERMANENT", "GENERAL_STAFFING", "PROFESSIONAL_STAFFING", "CAMPUS_FRESHER", "APPRENTICE",
                         "MANAGED_REMOTE"], [50, 15, 15, 10, 5, 5])[0],
            rng.choices(["FULL_TIME", "CONTRACT", "TEMPORARY", "INTERNSHIP"], [70, 20, 5, 5])[0],
            rng.choices(["ONSITE", "HYBRID", "REMOTE"], [50, 35, 15])[0],
            rng.choices(lk.city_ids, lk.city_weights)[0], rng.choice([1, 1, 1, 2, 3, 5, 10]),
        ))
        for skill in set(lk.skills[zipf_choice(rng, len(lk.skills))] for _ in range(rng.randint(2, 6))):
            job_skills.append((job_id, skill, rng.random() < 0.7))

    copy_rows(conn, "stg_job", ["id", "org_id", "poster_id", "title", "role_id", "industry_id", "min_exp", "max_exp",
                                "disclosed", "sal_min", "sal_max", "open_to_consultants", "status", "published_at",
                                "closed_at", "category", "employment", "work", "city_id", "openings"], jobs)
    copy_rows(conn, "stg_job_skill", ["job_id", "skill_id", "mandatory"], job_skills)

    conn.execute("""
        INSERT INTO job.job_requirement (id, organisation_id, posted_by_user_account_id, title, job_role_id, industry_id,
            description, min_experience_months, max_experience_months, salary_currency_id, salary_min_amount,
            salary_max_amount, is_open_to_consultants, published_at, closed_at,
            job_category_ref_code_id, employment_type_ref_code_id, work_type_ref_code_id,
            salary_disclosure_ref_code_id, salary_period_ref_code_id, publish_status_ref_code_id, source_system_ref_code_id)
        OVERRIDING SYSTEM VALUE
        SELECT id, org_id, poster_id, title, role_id, industry_id,
               'We are hiring a ' || title || '. You will work with a team building products used across India.',
               min_exp, max_exp, CASE WHEN disclosed THEN %s END, sal_min, sal_max, open_to_consultants,
               published_at, closed_at,
               mst.ref_code_id('JOB_CATEGORY', category), mst.ref_code_id('EMPLOYMENT_TYPE', employment),
               mst.ref_code_id('WORK_TYPE', work),
               mst.ref_code_id('DISCLOSURE_STATUS', CASE WHEN disclosed THEN 'DISCLOSED' ELSE 'NOT_DISCLOSED' END),
               CASE WHEN disclosed THEN mst.ref_code_id('SALARY_PERIOD', 'ANNUAL') END,
               mst.ref_code_id('JOB_PUBLISH_STATUS', status), mst.ref_code_id('SOURCE_SYSTEM', 'DIRECT')
        FROM stg_job""", (lk.inr,))
    conn.execute("""
        INSERT INTO job.job_position (job_requirement_id, city_id, openings_count)
        SELECT id, CASE WHEN work = 'REMOTE' THEN NULL ELSE city_id END, openings FROM stg_job""")
    conn.execute("""
        INSERT INTO job.job_requirement_skill (job_requirement_id, skill_id, is_mandatory)
        SELECT job_id, skill_id, mandatory FROM stg_job_skill""")
    log("jobs: done")

    rows = conn.execute("""
        SELECT j.id, p.id, j.published_at, j.closed_at FROM job.job_requirement j
        JOIN job.job_position p ON p.job_requirement_id = j.id
        WHERE j.id >= %s AND j.published_at IS NOT NULL ORDER BY j.id""", (first_job,)).fetchall()
    return rows


# ---------------------------------------------------------------------------
# Applications and status history
# ---------------------------------------------------------------------------

def path_to(status, rng):
    if status in PIPELINE:
        return PIPELINE[: PIPELINE.index(status) + 1]
    stop = rng.choice(PIPELINE[:4])            # REJECTED / WITHDRAWN after some stage
    return PIPELINE[: PIPELINE.index(stop) + 1] + [status]


def generate_applications(conn, rng, lk, count, candidates, jobs):
    log(f"applications: generating {count:,}")
    first_app = next_id(conn, "job.application")
    first_hist = next_id(conn, "job.application_status_history")
    conn.execute("""CREATE TEMP TABLE stg_app (id bigint, job_id bigint, candidate_id bigint, position_id bigint,
        applied_at timestamptz, status text, changed_at timestamptz, rejection text) ON COMMIT DROP""")
    conn.execute("""CREATE TEMP TABLE stg_hist (id bigint, app_id bigint, job_id bigint, from_status text,
        to_status text, rejection text, changed_at timestamptz) ON COMMIT DROP""")

    seen = set()
    apps, hist = [], []
    app_id, hist_id = first_app, first_hist
    reasons = ["SKILLS_MISMATCH", "EXPERIENCE_MISMATCH", "SALARY_MISMATCH", "LOCATION_MISMATCH",
               "INTERVIEW_NOT_CLEARED", "POSITION_FILLED", "OTHER"]
    attempts = 0
    while len(seen) < count and attempts < count * 3:
        attempts += 1
        job_id, position_id, published_at, closed_at = jobs[zipf_choice(rng, len(jobs), 0.9) if rng.random() < 0.6
                                                           else rng.randrange(len(jobs))]
        candidate = rng.choice(candidates)
        if (job_id, candidate) in seen:
            continue
        seen.add((job_id, candidate))
        end = min(closed_at or NOW, NOW)
        applied = random_time(rng, published_at, max(end, published_at + timedelta(hours=1)))
        status = rng.choices(list(STATUS_WEIGHTS), STATUS_WEIGHTS.values())[0]
        steps = path_to(status, rng)
        moment, previous = applied, None
        for step in steps:
            reason = rng.choice(reasons) if step == "REJECTED" else None
            hist.append((hist_id, app_id, job_id, previous, step, reason, moment))
            hist_id += 1
            previous = step
            last = moment
            moment = moment + timedelta(days=rng.randint(1, 10))
        apps.append((app_id, job_id, candidate, position_id, applied, status, last,
                     hist[-1][5] if status == "REJECTED" else None))
        app_id += 1
        if len(apps) >= BATCH:
            copy_rows(conn, "stg_app", ["id", "job_id", "candidate_id", "position_id", "applied_at", "status",
                                        "changed_at", "rejection"], apps)
            copy_rows(conn, "stg_hist", ["id", "app_id", "job_id", "from_status", "to_status", "rejection",
                                         "changed_at"], hist)
            apps, hist = [], []
    copy_rows(conn, "stg_app", ["id", "job_id", "candidate_id", "position_id", "applied_at", "status", "changed_at",
                                "rejection"], apps)
    copy_rows(conn, "stg_hist", ["id", "app_id", "job_id", "from_status", "to_status", "rejection", "changed_at"], hist)

    log("applications: bulk loading with triggers off (validated afterwards)")
    conn.execute("SET LOCAL session_replication_role = replica")
    conn.execute("""
        INSERT INTO job.application (id, job_requirement_id, candidate_profile_id, job_position_id, applied_at,
            status_changed_at, application_status_ref_code_id, application_source_ref_code_id,
            rejection_reason_ref_code_id, created_at, updated_at)
        OVERRIDING SYSTEM VALUE
        SELECT id, job_id, candidate_id, position_id, applied_at, changed_at,
               mst.ref_code_id('APPLICATION_STATUS', status), mst.ref_code_id('APPLICATION_SOURCE', 'DIRECT'),
               CASE WHEN rejection IS NOT NULL THEN mst.ref_code_id('REJECTION_REASON', rejection) END,
               applied_at, changed_at
        FROM stg_app""")
    conn.execute("""
        INSERT INTO job.application_status_history (id, application_id, job_requirement_id, from_status_ref_code_id,
            to_status_ref_code_id, rejection_reason_ref_code_id, changed_at, created_at)
        OVERRIDING SYSTEM VALUE
        SELECT id, app_id, job_id,
               CASE WHEN from_status IS NOT NULL THEN mst.ref_code_id('APPLICATION_STATUS', from_status) END,
               mst.ref_code_id('APPLICATION_STATUS', to_status),
               CASE WHEN rejection IS NOT NULL THEN mst.ref_code_id('REJECTION_REASON', rejection) END,
               changed_at, changed_at
        FROM stg_hist""")
    conn.execute("SET LOCAL session_replication_role = origin")
    log(f"applications: done ({len(seen):,} applications)")


# ---------------------------------------------------------------------------
# Validation of the trigger-free bulk load
# ---------------------------------------------------------------------------

VALIDATIONS = {
    "applications pointing at a missing job": """
        SELECT count(*) FROM job.application a WHERE NOT EXISTS (SELECT 1 FROM job.job_requirement j WHERE j.id = a.job_requirement_id)""",
    "applications pointing at a missing candidate": """
        SELECT count(*) FROM job.application a WHERE NOT EXISTS (SELECT 1 FROM prf.candidate_profile p WHERE p.id = a.candidate_profile_id)""",
    "history rows without their application": """
        SELECT count(*) FROM job.application_status_history h
        WHERE NOT EXISTS (SELECT 1 FROM job.application a WHERE a.id = h.application_id AND a.job_requirement_id = h.job_requirement_id)""",
    "history moves not allowed by the pipeline": """
        SELECT count(*) FROM job.application_status_history h
        WHERE NOT EXISTS (SELECT 1 FROM job.application_status_transition t
                          WHERE t.from_status_ref_code_id IS NOT DISTINCT FROM h.from_status_ref_code_id
                            AND t.to_status_ref_code_id = h.to_status_ref_code_id)""",
    "applications whose status differs from their last history row": """
        SELECT count(*) FROM job.application a
        JOIN LATERAL (SELECT h.to_status_ref_code_id FROM job.application_status_history h
                      WHERE h.application_id = a.id AND h.job_requirement_id = a.job_requirement_id
                      ORDER BY h.changed_at DESC, h.id DESC LIMIT 1) last ON true
        WHERE last.to_status_ref_code_id <> a.application_status_ref_code_id""",
}


def validate(conn):
    failures = 0
    for name, sql in VALIDATIONS.items():
        bad = conn.execute(sql).fetchone()[0]
        log(f"check: {name}: {bad}")
        failures += bad
    if failures:
        raise SystemExit("validation failed: the bulk load broke a rule; the transaction is rolled back")


def report(conn):
    for table in ["adm.user_account", "prf.candidate_profile", "prf.candidate_contact", "prf.candidate_skill",
                  "prf.candidate_education", "prf.candidate_work_experience", "org.organisation",
                  "job.job_requirement", "job.application", "job.application_status_history"]:
        log(f"rows: {table:35s} {conn.execute(f'SELECT count(*) FROM {table}').fetchone()[0]:>12,}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scale", choices=SCALES, default="small")
    parser.add_argument("--candidates", type=int)
    parser.add_argument("--jobs", type=int)
    parser.add_argument("--applications", type=int)
    parser.add_argument("--seed", type=int, default=20261015)
    parser.add_argument("--out", default="data")
    args = parser.parse_args()

    sizes = dict(SCALES[args.scale])
    for key in sizes:
        if getattr(args, key):
            sizes[key] = getattr(args, key)

    dsn = os.environ.get("TALENTRA_DSN", "postgresql://postgres:postgres@localhost:5432/talentra")
    rng = random.Random(args.seed)
    started = time.time()
    log(f"seed={args.seed} sizes={sizes}")

    with psycopg.connect(dsn) as conn:
        conn.execute("SELECT set_config('app.user_id', '1', false)")
        conn.execute("SELECT set_config('app.pii_key', %s, false)",
                     (os.environ.get("TALENTRA_PII_KEY", "dev-only-pii-key-change-me"),))
        conn.execute("SELECT set_config('app.hmac_key', %s, false)",
                     (os.environ.get("TALENTRA_HMAC_KEY", "dev-only-hmac-key-change-me"),))
        conn.execute("SET synchronous_commit = off")
        conn.execute("SET TIME ZONE 'UTC'")
        lk = Lookups(conn)
        with conn.transaction():
            candidates = generate_candidates(conn, rng, lk, sizes["candidates"], Path(args.out))
            jobs = generate_jobs(conn, rng, lk, sizes["jobs"])
            generate_applications(conn, rng, lk, sizes["applications"], candidates, jobs)
            validate(conn)
        for table in ["adm.user_account", "prf.candidate_profile", "org.organisation", "job.job_requirement",
                      "job.application", "job.application_status_history"]:
            conn.execute(f"SELECT setval(pg_get_serial_sequence('{table}', 'id'), (SELECT max(id) FROM {table}))")
        conn.execute("ANALYZE")
        report(conn)
    log(f"finished in {time.time() - started:,.0f}s")


if __name__ == "__main__":
    sys.exit(main())
