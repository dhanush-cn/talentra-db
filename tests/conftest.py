"""Shared fixtures for the rule-violation test suite.

Every test runs inside a transaction that is rolled back, so tests never
leave data behind and can run in any order against a freshly built database.

Connection: TALENTRA_DSN (default matches docker-compose.yml).
"""
import os
from contextlib import contextmanager

import psycopg
import pytest

DSN = os.environ.get(
    "TALENTRA_DSN", "postgresql://postgres:postgres@localhost:5432/talentra"
)
SYSTEM_USER_ID = 1

# Development-only keys. Real keys come from the application's secret store.
DEV_PII_KEY = os.environ.get("TALENTRA_PII_KEY", "dev-only-pii-key-change-me")
DEV_HMAC_KEY = os.environ.get("TALENTRA_HMAC_KEY", "dev-only-hmac-key-change-me")


@pytest.fixture
def db():
    """A connection in an open transaction, acting as the system account."""
    with psycopg.connect(DSN, autocommit=False) as conn:
        conn.execute("SELECT set_config('app.user_id', %s, true)", (str(SYSTEM_USER_ID),))
        conn.execute("SELECT set_config('app.pii_key', %s, true)", (DEV_PII_KEY,))
        conn.execute("SELECT set_config('app.hmac_key', %s, true)", (DEV_HMAC_KEY,))
        try:
            yield conn
        finally:
            conn.rollback()


@contextmanager
def violates(conn, sqlstate):
    """Assert that the block raises a database error with the given SQLSTATE.

    Uses a savepoint so the surrounding test transaction stays usable.

        with violates(db, "23514"):      # check_violation
            db.execute("INSERT ...")
    """
    with pytest.raises(psycopg.Error) as caught:
        with conn.transaction():
            yield
    allowed = {sqlstate}
    if sqlstate == FOREIGN_KEY_VIOLATION:
        allowed.add(RESTRICT_VIOLATION)   # PostgreSQL 18 reports ON DELETE RESTRICT as 23001
    assert caught.value.sqlstate in allowed, (
        f"expected SQLSTATE {sqlstate}, got {caught.value.sqlstate}: {caught.value}"
    )


# Common SQLSTATEs, named so tests read like the rule they prove.
CHECK_VIOLATION = "23514"
FOREIGN_KEY_VIOLATION = "23503"
RESTRICT_VIOLATION = "23001"
UNIQUE_VIOLATION = "23505"
NOT_NULL_VIOLATION = "23502"
EXCLUSION_VIOLATION = "23P01"
INSUFFICIENT_PRIVILEGE = "42501"


def ref_code_id(conn, code_type, code):
    """id of an enumeration value, e.g. ref_code_id(db, 'APPLICATION_STATUS', 'APPLIED')."""
    row = conn.execute(
        """SELECT rc.id FROM mst.ref_code rc
           JOIN mst.code_type ct ON ct.id = rc.code_type_id
           WHERE ct.code = %s AND rc.code = %s""",
        (code_type, code),
    ).fetchone()
    assert row, f"{code_type}.{code} not seeded"
    return row[0]


# ---------------------------------------------------------------------------
# Builders: create the minimum valid rows a test needs. Every builder returns ids.
# ---------------------------------------------------------------------------

def make_user(conn, user_type="CANDIDATE"):
    return conn.execute(
        """INSERT INTO adm.user_account (preferred_language_id, user_type_ref_code_id, account_status_ref_code_id)
           VALUES ((SELECT id FROM mst.language WHERE is_default),
                   mst.ref_code_id('USER_TYPE', %s), mst.ref_code_id('ACCOUNT_STATUS', 'ACTIVE'))
           RETURNING id""",
        (user_type,),
    ).fetchone()[0]


def make_candidate(conn, full_name="Test Candidate", **columns):
    """Candidate with salary not disclosed and source DIRECT unless overridden."""
    values = {
        "user_account_id": make_user(conn, "CANDIDATE"),
        "full_name": full_name,
        "profile_visibility_ref_code_id": ref_code_id(conn, "PROFILE_VISIBILITY", "PUBLIC"),
        "current_salary_disclosure_ref_code_id": ref_code_id(conn, "DISCLOSURE_STATUS", "NOT_DISCLOSED"),
        "expected_salary_disclosure_ref_code_id": ref_code_id(conn, "DISCLOSURE_STATUS", "NOT_DISCLOSED"),
        "source_system_ref_code_id": ref_code_id(conn, "SOURCE_SYSTEM", "DIRECT"),
    }
    values.update(columns)
    cols = ", ".join(values)
    marks = ", ".join(["%s"] * len(values))
    return conn.execute(
        f"INSERT INTO prf.candidate_profile ({cols}) VALUES ({marks}) RETURNING id", list(values.values())
    ).fetchone()[0]


def make_organisation(conn, name="Acme Technologies"):
    return conn.execute(
        """INSERT INTO org.organisation (legal_name, display_name, country_id,
                                         organisation_type_ref_code_id, account_status_ref_code_id)
           VALUES (%s, %s, (SELECT id FROM mst.country WHERE iso2_code = 'IN'),
                   mst.ref_code_id('ORGANISATION_TYPE', 'EMPLOYER'), mst.ref_code_id('ACCOUNT_STATUS', 'ACTIVE'))
           RETURNING id""",
        (name + " Pvt Ltd", name),
    ).fetchone()[0]


def make_job(conn, organisation_id=None, title="Backend Engineer", **columns):
    """Published job, salary not disclosed, unless overridden."""
    organisation_id = organisation_id or make_organisation(conn)
    values = {
        "organisation_id": organisation_id,
        "posted_by_user_account_id": make_user(conn, "RECRUITER"),
        "title": title,
        "description": "Build and run backend services.",
        "job_category_ref_code_id": ref_code_id(conn, "JOB_CATEGORY", "PERMANENT"),
        "employment_type_ref_code_id": ref_code_id(conn, "EMPLOYMENT_TYPE", "FULL_TIME"),
        "work_type_ref_code_id": ref_code_id(conn, "WORK_TYPE", "HYBRID"),
        "salary_disclosure_ref_code_id": ref_code_id(conn, "DISCLOSURE_STATUS", "NOT_DISCLOSED"),
        "publish_status_ref_code_id": ref_code_id(conn, "JOB_PUBLISH_STATUS", "PUBLISHED"),
        "published_at": "2026-10-01T09:00:00Z",
        "source_system_ref_code_id": ref_code_id(conn, "SOURCE_SYSTEM", "DIRECT"),
    }
    values.update(columns)
    cols = ", ".join(values)
    marks = ", ".join(["%s"] * len(values))
    return conn.execute(
        f"INSERT INTO job.job_requirement ({cols}) VALUES ({marks}) RETURNING id", list(values.values())
    ).fetchone()[0]


def make_position(conn, job_id, city="Bengaluru", openings=1):
    return conn.execute(
        """INSERT INTO job.job_position (job_requirement_id, city_id, openings_count)
           VALUES (%s, (SELECT id FROM mst.city WHERE english_name = %s), %s) RETURNING id""",
        (job_id, city, openings),
    ).fetchone()[0]


def make_application(conn, job_id, candidate_id, status="APPLIED", **columns):
    values = {
        "job_requirement_id": job_id,
        "candidate_profile_id": candidate_id,
        "applied_at": "2026-10-05T10:00:00Z",
        "application_status_ref_code_id": ref_code_id(conn, "APPLICATION_STATUS", status),
        "application_source_ref_code_id": ref_code_id(conn, "APPLICATION_SOURCE", "DIRECT"),
    }
    values.update(columns)
    cols = ", ".join(values)
    marks = ", ".join(["%s"] * len(values))
    return conn.execute(
        f"INSERT INTO job.application ({cols}) VALUES ({marks}) RETURNING id", list(values.values())
    ).fetchone()[0]


def move_application(conn, application_id, job_id, status, rejection_reason=None):
    conn.execute(
        """UPDATE job.application
           SET application_status_ref_code_id = mst.ref_code_id('APPLICATION_STATUS', %s),
               rejection_reason_ref_code_id = CASE WHEN %s::text IS NULL THEN NULL
                                                   ELSE mst.ref_code_id('REJECTION_REASON', %s) END
           WHERE id = %s AND job_requirement_id = %s""",
        (status, rejection_reason, rejection_reason, application_id, job_id),
    )
