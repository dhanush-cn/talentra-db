"""Rule-violation tests for the Profile module (prf schema)."""
import pytest

from conftest import (
    CHECK_VIOLATION,
    INSUFFICIENT_PRIVILEGE,
    UNIQUE_VIOLATION,
    make_candidate,
    make_organisation,
    make_user,
    ref_code_id,
    violates,
)


def add_contact(db, candidate_id, kind, value, primary=False):
    return db.execute(
        """INSERT INTO prf.candidate_contact (candidate_profile_id, contact_type_ref_code_id,
               value_encrypted, value_hmac, value_masked, phone_country_id, is_primary)
           VALUES (%s, mst.ref_code_id('CONTACT_TYPE', %s), core.pii_encrypt(%s), core.pii_hmac(%s),
                   CASE WHEN %s = 'EMAIL' THEN core.mask_email(%s) ELSE core.mask_phone(%s) END,
                   CASE WHEN %s = 'EMAIL' THEN NULL ELSE (SELECT id FROM mst.country WHERE iso2_code = 'IN') END,
                   %s)
           RETURNING id""",
        (candidate_id, kind, value, value, kind, value, value, kind, primary),
    ).fetchone()[0]


# ---------------------------------------------------------------------------
# Identity and natural keys (Rule 2)
# ---------------------------------------------------------------------------

def test_rule2_one_profile_per_account(db):
    candidate = make_candidate(db)
    account = db.execute("SELECT user_account_id FROM prf.candidate_profile WHERE id = %s", (candidate,)).fetchone()[0]
    with violates(db, UNIQUE_VIOLATION):
        make_candidate(db, user_account_id=account)


def test_rule2_legacy_natural_key_is_unique(db):
    legacy = ref_code_id(db, "SOURCE_SYSTEM", "LEGACY_ATS")
    make_candidate(db, source_system_ref_code_id=legacy, source_record_id="ATS-000042")
    with violates(db, UNIQUE_VIOLATION):
        make_candidate(db, source_system_ref_code_id=legacy, source_record_id="ATS-000042")


def test_rule2_legacy_record_needs_its_source_id(db):
    with violates(db, CHECK_VIOLATION):
        make_candidate(db, source_system_ref_code_id=ref_code_id(db, "SOURCE_SYSTEM", "LEGACY_CRM"))


# ---------------------------------------------------------------------------
# Rule 5: unknown vs not disclosed vs a real value
# ---------------------------------------------------------------------------

def test_rule5_undisclosed_salary_cannot_be_stored_as_zero(db):
    with violates(db, CHECK_VIOLATION):
        make_candidate(db, current_salary_amount=0, salary_currency_id=1)


def test_rule5_disclosed_salary_needs_an_amount(db):
    with violates(db, CHECK_VIOLATION):
        make_candidate(db, current_salary_disclosure_ref_code_id=ref_code_id(db, "DISCLOSURE_STATUS", "DISCLOSED"))


def test_rule5_disclosed_salary_with_amount_and_currency_is_accepted(db):
    inr = db.execute("SELECT id FROM mst.currency WHERE iso_code = 'INR'").fetchone()[0]
    make_candidate(
        db,
        current_salary_disclosure_ref_code_id=ref_code_id(db, "DISCLOSURE_STATUS", "DISCLOSED"),
        current_salary_amount=1200000,
        salary_currency_id=inr,
    )


def test_rule3_salary_amount_needs_a_currency(db):
    with violates(db, CHECK_VIOLATION):
        make_candidate(
            db,
            current_salary_disclosure_ref_code_id=ref_code_id(db, "DISCLOSURE_STATUS", "DISCLOSED"),
            current_salary_amount=1200000,
        )


# ---------------------------------------------------------------------------
# Rule 6: contact details are never stored readable
# ---------------------------------------------------------------------------

def test_rule6_contact_is_encrypted_masked_and_recoverable(db):
    candidate = make_candidate(db)
    contact = add_contact(db, candidate, "EMAIL", "priya.rao@example.in", primary=True)
    encrypted, masked, plain = db.execute(
        "SELECT value_encrypted, value_masked, core.pii_decrypt(value_encrypted) FROM prf.candidate_contact WHERE id = %s",
        (contact,),
    ).fetchone()
    assert b"priya" not in bytes(encrypted)
    assert masked == "pr***@example.in"
    assert plain == "priya.rao@example.in"


def test_rule6_duplicate_candidates_found_by_blind_index_without_decrypting(db):
    first = make_candidate(db, full_name="Priya Rao")
    second = make_candidate(db, full_name="PRIYA  RAO")
    add_contact(db, first, "PHONE", "+919876543210")
    add_contact(db, second, "PHONE", " +919876543210 ")   # same number, typed differently
    owners = db.execute(
        """SELECT count(DISTINCT candidate_profile_id) FROM prf.candidate_contact
           WHERE value_hmac = core.pii_hmac('+919876543210')"""
    ).fetchone()[0]
    assert owners == 2


def test_rule6_pii_cannot_be_processed_without_a_key(db):
    db.execute("SELECT set_config('app.pii_key', '', true)")
    with violates(db, INSUFFICIENT_PRIVILEGE):
        db.execute("SELECT core.pii_encrypt('someone@example.in')")


def test_profile_one_primary_contact_per_type(db):
    candidate = make_candidate(db)
    add_contact(db, candidate, "EMAIL", "a@example.in", primary=True)
    with violates(db, UNIQUE_VIOLATION):
        add_contact(db, candidate, "EMAIL", "b@example.in", primary=True)


def test_profile_phone_contact_needs_a_country(db):
    candidate = make_candidate(db)
    with violates(db, CHECK_VIOLATION):
        db.execute(
            """INSERT INTO prf.candidate_contact (candidate_profile_id, contact_type_ref_code_id,
                   value_encrypted, value_hmac, value_masked)
               VALUES (%s, mst.ref_code_id('CONTACT_TYPE', 'PHONE'), '\\x00', '\\x00', '+91******3210')""",
            (candidate,),
        )


# ---------------------------------------------------------------------------
# Date ranges and domain rules (Rule 2 check constraints, Rule 3)
# ---------------------------------------------------------------------------

def test_rule3_work_experience_cannot_end_before_it_starts(db):
    candidate = make_candidate(db)
    with violates(db, CHECK_VIOLATION):
        db.execute(
            """INSERT INTO prf.candidate_work_experience (candidate_profile_id, employer_name, designation,
                   start_date, end_date) VALUES (%s, 'Infosys', 'Engineer', '2024-06-01', '2023-01-01')""",
            (candidate,),
        )


def test_profile_current_job_has_no_end_date(db):
    candidate = make_candidate(db)
    with violates(db, CHECK_VIOLATION):
        db.execute(
            """INSERT INTO prf.candidate_work_experience (candidate_profile_id, employer_name, designation,
                   start_date, end_date, is_current) VALUES (%s, 'Infosys', 'Engineer', '2024-06-01', '2025-01-01', true)""",
            (candidate,),
        )


@pytest.mark.parametrize("scale,score", [("CGPA_10", 11), ("CGPA_4", 4.5), ("PERCENTAGE", 101)])
def test_profile_education_score_must_fit_its_scale(db, scale, score):
    candidate = make_candidate(db)
    with violates(db, CHECK_VIOLATION):
        db.execute(
            """INSERT INTO prf.candidate_education (candidate_profile_id, qualification_id, institution_id,
                   score_value, score_scale_ref_code_id)
               VALUES (%s, (SELECT id FROM mst.qualification WHERE short_name = 'B.E.'),
                       (SELECT id FROM mst.institution LIMIT 1), %s, mst.ref_code_id('SCORE_SCALE', %s))""",
            (candidate, score, scale),
        )


def test_profile_one_default_resume(db):
    candidate = make_candidate(db)
    for version in (1, 2):
        sql = """INSERT INTO prf.candidate_resume (candidate_profile_id, version_number, title, body, is_default)
                 VALUES (%s, %s, 'Backend roles', 'Resume text', true)"""
        if version == 1:
            db.execute(sql, (candidate, version))
        else:
            with violates(db, UNIQUE_VIOLATION):
                db.execute(sql, (candidate, version))


def test_profile_resume_needs_content(db):
    candidate = make_candidate(db)
    with violates(db, CHECK_VIOLATION):
        db.execute(
            "INSERT INTO prf.candidate_resume (candidate_profile_id, version_number, title) VALUES (%s, 1, 'Empty')",
            (candidate,),
        )


# ---------------------------------------------------------------------------
# Rule 10: view history is append-only and partitioned by month
# ---------------------------------------------------------------------------

def test_rule10_profile_view_history_is_append_only(db):
    candidate = make_candidate(db)
    viewer = make_user(db, "RECRUITER")
    db.execute(
        """INSERT INTO prf.profile_view_event (candidate_profile_id, viewer_user_account_id, viewed_at, view_source_ref_code_id)
           VALUES (%s, %s, '2026-10-10T08:00:00Z', mst.ref_code_id('VIEW_SOURCE', 'SEARCH'))""",
        (candidate, viewer),
    )
    with violates(db, INSUFFICIENT_PRIVILEGE):
        db.execute("UPDATE prf.profile_view_event SET viewed_at = now() WHERE candidate_profile_id = %s", (candidate,))
    with violates(db, INSUFFICIENT_PRIVILEGE):
        db.execute("DELETE FROM prf.profile_view_event WHERE candidate_profile_id = %s", (candidate,))


def test_rule8_view_lands_in_its_monthly_partition(db):
    candidate = make_candidate(db)
    viewer = make_user(db, "RECRUITER")
    db.execute(
        """INSERT INTO prf.profile_view_event (candidate_profile_id, viewer_user_account_id, viewed_at, view_source_ref_code_id)
           VALUES (%s, %s, '2026-03-15T08:00:00Z', mst.ref_code_id('VIEW_SOURCE', 'SEARCH'))""",
        (candidate, viewer),
    )
    partition = db.execute(
        "SELECT tableoid::regclass::text FROM prf.profile_view_event WHERE candidate_profile_id = %s", (candidate,)
    ).fetchone()[0]
    assert partition == "prf.profile_view_event_p202603"


def test_rule10_bookmark_history_is_recorded_automatically(db):
    candidate = make_candidate(db)
    recruiter = make_user(db, "RECRUITER")
    bookmark = db.execute(
        """INSERT INTO prf.candidate_bookmark (owner_user_account_id, organisation_id, candidate_profile_id)
           VALUES (%s, %s, %s) RETURNING id""",
        (recruiter, make_organisation(db), candidate),
    ).fetchone()[0]
    db.execute("UPDATE prf.candidate_bookmark SET deleted_at = now(), deleted_by = 1 WHERE id = %s", (bookmark,))
    actions = [
        r[0]
        for r in db.execute(
            """SELECT rc.code FROM prf.candidate_bookmark_event e
               JOIN mst.ref_code rc ON rc.id = e.bookmark_action_ref_code_id
               WHERE e.candidate_bookmark_id = %s ORDER BY e.id""",
            (bookmark,),
        )
    ]
    assert actions == ["ADDED", "REMOVED"]


# ---------------------------------------------------------------------------
# Profile completion scoring
# ---------------------------------------------------------------------------

def test_profile_completion_weights_total_100(db):
    total = db.execute("SELECT sum(weight_percent) FROM prf.profile_completion_rule WHERE is_active").fetchone()[0]
    assert total == 100


def test_profile_completion_score_reflects_sections(db):
    candidate = make_candidate(db, is_fresher=True, headline="Backend developer", summary="Python and SQL.")
    assert db.execute("SELECT prf.refresh_completion(%s)", (candidate,)).fetchone()[0] == 25  # experience + headline
    for skill in ("Python", "SQL", "Git"):
        db.execute(
            "INSERT INTO prf.candidate_skill (candidate_profile_id, skill_id) SELECT %s, id FROM mst.skill WHERE english_name = %s",
            (candidate, skill),
        )
    assert db.execute("SELECT prf.refresh_completion(%s)", (candidate,)).fetchone()[0] == 40
    assert db.execute("SELECT completion_percent FROM prf.candidate_profile WHERE id = %s", (candidate,)).fetchone()[0] == 40
