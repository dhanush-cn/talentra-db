"""Rule-violation tests for the Jobs and Applications module (job schema)."""
import pytest

from conftest import (
    CHECK_VIOLATION,
    EXCLUSION_VIOLATION,
    FOREIGN_KEY_VIOLATION,
    INSUFFICIENT_PRIVILEGE,
    UNIQUE_VIOLATION,
    make_application,
    make_candidate,
    make_job,
    make_position,
    make_user,
    move_application,
    ref_code_id,
    violates,
)


def statuses_in_history(db, application_id, job_id):
    return [
        r[0]
        for r in db.execute(
            """SELECT rc.code FROM job.application_status_history h
               JOIN mst.ref_code rc ON rc.id = h.to_status_ref_code_id
               WHERE h.application_id = %s AND h.job_requirement_id = %s ORDER BY h.id""",
            (application_id, job_id),
        )
    ]


# ---------------------------------------------------------------------------
# Job requirement rules
# ---------------------------------------------------------------------------

def test_rule5_job_salary_disclosed_needs_amount_currency_and_period(db):
    with violates(db, CHECK_VIOLATION):
        make_job(db, salary_disclosure_ref_code_id=ref_code_id(db, "DISCLOSURE_STATUS", "DISCLOSED"))


def test_rule2_job_salary_min_cannot_exceed_max(db):
    with violates(db, CHECK_VIOLATION):
        make_job(
            db,
            salary_disclosure_ref_code_id=ref_code_id(db, "DISCLOSURE_STATUS", "DISCLOSED"),
            salary_currency_id=1,
            salary_period_ref_code_id=ref_code_id(db, "SALARY_PERIOD", "ANNUAL"),
            salary_min_amount=1800000,
            salary_max_amount=1200000,
        )


def test_rule2_experience_range_must_be_ordered(db):
    with violates(db, CHECK_VIOLATION):
        make_job(db, min_experience_months=60, max_experience_months=24)


def test_job_draft_has_no_publish_time(db):
    with violates(db, CHECK_VIOLATION):
        make_job(db, publish_status_ref_code_id=ref_code_id(db, "JOB_PUBLISH_STATUS", "DRAFT"))


def test_gig_work_cannot_be_posted_as_a_job(db):
    """Gigs are a separate subsystem (justification J-03)."""
    with violates(db, CHECK_VIOLATION):
        make_job(db, job_category_ref_code_id=ref_code_id(db, "JOB_CATEGORY", "GIG_PROJECT"))


def test_job_full_text_search_finds_title_words(db):
    job = make_job(db, title="Senior PostgreSQL Engineer")
    found = db.execute(
        "SELECT id FROM job.job_requirement WHERE search_document @@ plainto_tsquery('simple', 'postgresql engineer')"
    ).fetchall()
    assert (job,) in found


# ---------------------------------------------------------------------------
# Applications: one per candidate per job, partitioned by job
# ---------------------------------------------------------------------------

def test_rule2_one_application_per_candidate_per_job(db):
    job, candidate = make_job(db), make_candidate(db)
    make_application(db, job, candidate)
    with violates(db, UNIQUE_VIOLATION):
        make_application(db, job, candidate)


def test_rule8_application_lands_in_a_hash_partition(db):
    job, candidate = make_job(db), make_candidate(db)
    application = make_application(db, job, candidate)
    partition = db.execute(
        "SELECT tableoid::regclass::text FROM job.application WHERE id = %s AND job_requirement_id = %s",
        (application, job),
    ).fetchone()[0]
    assert partition.startswith("job.application_h")


def test_application_position_must_belong_to_the_same_job(db):
    job, other_job, candidate = make_job(db), make_job(db), make_candidate(db)
    other_position = make_position(db, other_job)
    with violates(db, FOREIGN_KEY_VIOLATION):
        make_application(db, job, candidate, job_position_id=other_position)


def test_application_resume_must_belong_to_the_applicant(db):
    job, applicant, someone_else = make_job(db), make_candidate(db), make_candidate(db)
    their_resume = db.execute(
        """INSERT INTO prf.candidate_resume (candidate_profile_id, version_number, title, body)
           VALUES (%s, 1, 'CV', 'text') RETURNING id""",
        (someone_else,),
    ).fetchone()[0]
    with violates(db, FOREIGN_KEY_VIOLATION):
        make_application(db, job, applicant, candidate_resume_id=their_resume)


def test_sourced_application_records_who_sourced_it(db):
    job, candidate = make_job(db), make_candidate(db)
    with violates(db, CHECK_VIOLATION):
        make_application(db, job, candidate, application_source_ref_code_id=ref_code_id(db, "APPLICATION_SOURCE", "SOURCING"))


# ---------------------------------------------------------------------------
# Status pipeline enforced by the database
# ---------------------------------------------------------------------------

def test_pipeline_full_path_is_recorded_in_history(db):
    job, candidate = make_job(db), make_candidate(db)
    application = make_application(db, job, candidate)
    for status in ("SHORTLISTED", "INTERVIEWED", "OFFERED", "JOINED"):
        move_application(db, application, job, status)
    assert statuses_in_history(db, application, job) == ["APPLIED", "SHORTLISTED", "INTERVIEWED", "OFFERED", "JOINED"]


def test_pipeline_cannot_skip_stages(db):
    job, candidate = make_job(db), make_candidate(db)
    application = make_application(db, job, candidate)
    with violates(db, CHECK_VIOLATION):
        move_application(db, application, job, "JOINED")


def test_pipeline_new_application_cannot_start_as_offered(db):
    job, candidate = make_job(db), make_candidate(db)
    with violates(db, CHECK_VIOLATION):
        make_application(db, job, candidate, status="OFFERED")


def test_pipeline_rejection_needs_a_reason(db):
    job, candidate = make_job(db), make_candidate(db)
    application = make_application(db, job, candidate)
    with violates(db, CHECK_VIOLATION):
        move_application(db, application, job, "REJECTED")


def test_pipeline_rejected_is_final(db):
    job, candidate = make_job(db), make_candidate(db)
    application = make_application(db, job, candidate)
    move_application(db, application, job, "REJECTED", rejection_reason="SKILLS_MISMATCH")
    with violates(db, CHECK_VIOLATION):
        move_application(db, application, job, "SHORTLISTED")


def test_application_cannot_be_moved_to_another_candidate(db):
    job, candidate, other = make_job(db), make_candidate(db), make_candidate(db)
    application = make_application(db, job, candidate)
    with violates(db, CHECK_VIOLATION):
        db.execute(
            "UPDATE job.application SET candidate_profile_id = %s WHERE id = %s AND job_requirement_id = %s",
            (other, application, job),
        )


def test_rule10_status_history_is_append_only(db):
    job, candidate = make_job(db), make_candidate(db)
    make_application(db, job, candidate)
    with violates(db, INSUFFICIENT_PRIVILEGE):
        db.execute("DELETE FROM job.application_status_history WHERE job_requirement_id = %s", (job,))


# ---------------------------------------------------------------------------
# Questionnaire answers
# ---------------------------------------------------------------------------

def test_answer_option_must_belong_to_its_question(db):
    job, candidate = make_job(db), make_candidate(db)
    application = make_application(db, job, candidate)
    organisation = db.execute("SELECT organisation_id FROM job.job_requirement WHERE id = %s", (job,)).fetchone()[0]
    questionnaire = db.execute(
        "INSERT INTO job.questionnaire (organisation_id, title) VALUES (%s, 'Screening') RETURNING id", (organisation,)
    ).fetchone()[0]
    q1, q2 = [
        db.execute(
            """INSERT INTO job.questionnaire_question (questionnaire_id, sequence_no, question_text, answer_type_ref_code_id)
               VALUES (%s, %s, %s, mst.ref_code_id('ANSWER_TYPE', 'SINGLE_CHOICE')) RETURNING id""",
            (questionnaire, n, text),
        ).fetchone()[0]
        for n, text in ((1, "Willing to relocate?"), (2, "Notice period?"))
    ]
    q2_option = db.execute(
        "INSERT INTO job.question_option (questionnaire_question_id, sequence_no, option_text) VALUES (%s, 1, '30 days') RETURNING id",
        (q2,),
    ).fetchone()[0]
    with violates(db, FOREIGN_KEY_VIOLATION):
        db.execute(
            """INSERT INTO job.application_answer (application_id, job_requirement_id, questionnaire_question_id, question_option_id)
               VALUES (%s, %s, %s, %s)""",
            (application, job, q1, q2_option),
        )


# ---------------------------------------------------------------------------
# Interviews, offers, joining
# ---------------------------------------------------------------------------

def schedule(db, application, job, interviewer, round_no, start, end):
    db.execute(
        """INSERT INTO job.interview (application_id, job_requirement_id, round_number, scheduled_start_at,
               scheduled_end_at, interviewer_user_account_id, interview_mode_ref_code_id)
           VALUES (%s, %s, %s, %s, %s, %s, mst.ref_code_id('INTERVIEW_MODE', 'VIDEO'))""",
        (application, job, round_no, start, end, interviewer),
    )


def test_rule2_interviewer_cannot_be_double_booked(db):
    job = make_job(db)
    a1 = make_application(db, job, make_candidate(db))
    a2 = make_application(db, job, make_candidate(db))
    interviewer = make_user(db, "RECRUITER")
    schedule(db, a1, job, interviewer, 1, "2026-10-20T10:00:00Z", "2026-10-20T11:00:00Z")
    with violates(db, EXCLUSION_VIOLATION):
        schedule(db, a2, job, interviewer, 1, "2026-10-20T10:30:00Z", "2026-10-20T11:30:00Z")


def test_cancelled_interview_frees_the_slot(db):
    job = make_job(db)
    a1 = make_application(db, job, make_candidate(db))
    a2 = make_application(db, job, make_candidate(db))
    interviewer = make_user(db, "RECRUITER")
    schedule(db, a1, job, interviewer, 1, "2026-10-20T10:00:00Z", "2026-10-20T11:00:00Z")
    db.execute(
        "UPDATE job.interview SET interview_outcome_ref_code_id = mst.ref_code_id('INTERVIEW_OUTCOME', 'CANCELLED') WHERE application_id = %s",
        (a1,),
    )
    schedule(db, a2, job, interviewer, 1, "2026-10-20T10:30:00Z", "2026-10-20T11:30:00Z")


def make_offer(db, application, job, version=1, status="EXTENDED"):
    return db.execute(
        """INSERT INTO job.offer (application_id, job_requirement_id, offer_version, offered_amount, currency_id,
               extended_at, valid_until, responded_at, salary_period_ref_code_id, offer_status_ref_code_id)
           VALUES (%s, %s, %s, 1500000, 1, '2026-10-10T10:00:00Z', '2026-10-20',
                   CASE WHEN %s IN ('ACCEPTED', 'DECLINED') THEN '2026-10-11T10:00:00Z'::timestamptz END,
                   mst.ref_code_id('SALARY_PERIOD', 'ANNUAL'), mst.ref_code_id('OFFER_STATUS', %s))
           RETURNING id""",
        (application, job, version, status, status),
    ).fetchone()[0]


def test_only_one_live_offer_per_application(db):
    job = make_job(db)
    application = make_application(db, job, make_candidate(db))
    make_offer(db, application, job, 1)
    with violates(db, UNIQUE_VIOLATION):
        make_offer(db, application, job, 2)


def join(db, application, job, offer):
    db.execute(
        """INSERT INTO job.joining (application_id, job_requirement_id, offer_id, joined_on, joining_status_ref_code_id)
           VALUES (%s, %s, %s, '2026-11-01', mst.ref_code_id('JOINING_STATUS', 'JOINED'))""",
        (application, job, offer),
    )


def test_joining_requires_an_accepted_offer(db):
    job = make_job(db)
    application = make_application(db, job, make_candidate(db))
    offer = make_offer(db, application, job, status="EXTENDED")
    with violates(db, CHECK_VIOLATION):
        join(db, application, job, offer)


def test_joining_fills_the_position_and_cannot_overfill_it(db):
    job = make_job(db)
    position = make_position(db, job, openings=1)
    first = make_application(db, job, make_candidate(db), job_position_id=position)
    second = make_application(db, job, make_candidate(db), job_position_id=position)

    join(db, first, job, make_offer(db, first, job, status="ACCEPTED"))
    assert db.execute("SELECT filled_count FROM job.job_position WHERE id = %s", (position,)).fetchone()[0] == 1

    with violates(db, CHECK_VIOLATION):
        join(db, second, job, make_offer(db, second, job, status="ACCEPTED"))


# ---------------------------------------------------------------------------
# Shortlists and search history
# ---------------------------------------------------------------------------

def test_shortlist_one_live_entry_per_candidate_per_job_with_history(db):
    job, candidate, recruiter = make_job(db), make_candidate(db), make_user(db, "RECRUITER")
    sql = """INSERT INTO job.job_shortlist_entry (job_requirement_id, candidate_profile_id,
                 shortlisted_by_user_account_id, shortlist_source_ref_code_id)
             VALUES (%s, %s, %s, mst.ref_code_id('SHORTLIST_SOURCE', 'SEARCH')) RETURNING id"""
    entry = db.execute(sql, (job, candidate, recruiter)).fetchone()[0]
    with violates(db, UNIQUE_VIOLATION):
        db.execute(sql, (job, candidate, recruiter))
    events = db.execute("SELECT count(*) FROM job.job_shortlist_event WHERE job_shortlist_entry_id = %s", (entry,)).fetchone()[0]
    assert events == 1


def test_guest_search_is_recorded_without_an_account(db):
    db.execute(
        """INSERT INTO job.job_search_event (search_text, results_count, searched_at)
           VALUES ('data analyst', 42, '2026-10-12T07:00:00Z')"""
    )
    with violates(db, CHECK_VIOLATION):
        db.execute(
            """INSERT INTO job.job_search_event (candidate_profile_id, results_count, searched_at)
               VALUES (%s, 0, '2026-10-12T07:00:00Z')""",
            (make_candidate(db),),
        )
