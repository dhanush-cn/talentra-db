-- demo/demo.sql: live demo of the database enforcing its own rules.
-- Run: make demo   (or: psql -f demo/demo.sql)
-- Everything runs in one transaction that is rolled back at the end: nothing is saved.
-- Each step tries to break a rule. An ERROR line is the expected, correct outcome.

\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
\set VERBOSITY terse
\pset footer off

BEGIN;
SELECT set_config('app.user_id', '1', true) AS ignored \gset
SELECT set_config('app.pii_key', 'dev-only-pii-key-change-me', true) AS ignored \gset
SELECT set_config('app.hmac_key', 'dev-only-hmac-key-change-me', true) AS ignored \gset

\echo
\echo '=== Setup: one employer, one job, one candidate ==='
INSERT INTO adm.user_account (preferred_language_id, user_type_ref_code_id, account_status_ref_code_id)
VALUES (1, mst.ref_code_id('USER_TYPE', 'RECRUITER'), mst.ref_code_id('ACCOUNT_STATUS', 'ACTIVE'))
RETURNING id AS recruiter \gset
INSERT INTO adm.user_account (preferred_language_id, user_type_ref_code_id, account_status_ref_code_id)
VALUES (1, mst.ref_code_id('USER_TYPE', 'CANDIDATE'), mst.ref_code_id('ACCOUNT_STATUS', 'ACTIVE'))
RETURNING id AS candidate_user \gset
INSERT INTO org.organisation (legal_name, display_name, country_id, organisation_type_ref_code_id, account_status_ref_code_id)
VALUES ('Demo Fintech Private Limited', 'Demo Fintech', (SELECT id FROM mst.country WHERE iso2_code = 'IN'),
        mst.ref_code_id('ORGANISATION_TYPE', 'EMPLOYER'), mst.ref_code_id('ACCOUNT_STATUS', 'ACTIVE'))
RETURNING id AS org \gset
INSERT INTO job.job_requirement (organisation_id, posted_by_user_account_id, title, description,
    job_category_ref_code_id, employment_type_ref_code_id, work_type_ref_code_id, salary_disclosure_ref_code_id,
    publish_status_ref_code_id, published_at, source_system_ref_code_id)
VALUES (:org, :recruiter, 'Backend Engineer', 'Build payment services in Go and PostgreSQL.',
    mst.ref_code_id('JOB_CATEGORY', 'PERMANENT'), mst.ref_code_id('EMPLOYMENT_TYPE', 'FULL_TIME'),
    mst.ref_code_id('WORK_TYPE', 'HYBRID'), mst.ref_code_id('DISCLOSURE_STATUS', 'NOT_DISCLOSED'),
    mst.ref_code_id('JOB_PUBLISH_STATUS', 'PUBLISHED'), now(), mst.ref_code_id('SOURCE_SYSTEM', 'DIRECT'))
RETURNING id AS job \gset
INSERT INTO prf.candidate_profile (user_account_id, full_name, profile_visibility_ref_code_id,
    current_salary_disclosure_ref_code_id, expected_salary_disclosure_ref_code_id, source_system_ref_code_id)
VALUES (:candidate_user, U&'\0CAA\0CCD\0CB0\0CBF\0CAF\0CBE \0CB0\0CBE\0CB5\0CCD', mst.ref_code_id('PROFILE_VISIBILITY', 'PUBLIC'),
    mst.ref_code_id('DISCLOSURE_STATUS', 'NOT_DISCLOSED'), mst.ref_code_id('DISCLOSURE_STATUS', 'NOT_DISCLOSED'),
    mst.ref_code_id('SOURCE_SYSTEM', 'DIRECT'))
RETURNING id AS candidate, full_name \gset
\echo 'Created job' :job 'and candidate' :candidate 'with a Kannada name. Proof it is stored exactly (no terminal needed):'
SELECT length(full_name) AS characters,
       full_name = U&'\0CAA\0CCD\0CB0\0CBF\0CAF\0CBE \0CB0\0CBE\0CB5\0CCD' AS stored_exactly,
       full_name ~ '^[\u0C80-\u0CFF ]+$' AS kannada_script_only
FROM prf.candidate_profile WHERE id = :candidate;

\echo
\echo '=== 1. A candidate applies to the job: allowed ==='
INSERT INTO job.application (job_requirement_id, candidate_profile_id, applied_at,
    application_status_ref_code_id, application_source_ref_code_id)
VALUES (:job, :candidate, now(), mst.ref_code_id('APPLICATION_STATUS', 'APPLIED'), mst.ref_code_id('APPLICATION_SOURCE', 'DIRECT'))
RETURNING id AS application, tableoid::regclass AS stored_in_partition \gset
\echo 'Application' :application 'stored in partition' :stored_in_partition

\echo
\echo '=== 2. The same candidate applies again: REFUSED (one application per job) ==='
INSERT INTO job.application (job_requirement_id, candidate_profile_id, applied_at,
    application_status_ref_code_id, application_source_ref_code_id)
VALUES (:job, :candidate, now(), mst.ref_code_id('APPLICATION_STATUS', 'APPLIED'), mst.ref_code_id('APPLICATION_SOURCE', 'DIRECT'));

\echo
\echo '=== 3. Jump from APPLIED straight to JOINED: REFUSED (pipeline enforced) ==='
UPDATE job.application SET application_status_ref_code_id = mst.ref_code_id('APPLICATION_STATUS', 'JOINED')
WHERE id = :application AND job_requirement_id = :job;

\echo
\echo '=== 4. Reject without giving a reason: REFUSED ==='
UPDATE job.application SET application_status_ref_code_id = mst.ref_code_id('APPLICATION_STATUS', 'REJECTED')
WHERE id = :application AND job_requirement_id = :job;

\echo
\echo '=== 5. Move to SHORTLISTED properly: allowed, and history is written automatically ==='
UPDATE job.application SET application_status_ref_code_id = mst.ref_code_id('APPLICATION_STATUS', 'SHORTLISTED')
WHERE id = :application AND job_requirement_id = :job;
SELECT coalesce(f.code, '(new)') AS from_status, t.code AS to_status, h.changed_at
FROM job.application_status_history h
LEFT JOIN mst.ref_code f ON f.id = h.from_status_ref_code_id
JOIN mst.ref_code t ON t.id = h.to_status_ref_code_id
WHERE h.application_id = :application AND h.job_requirement_id = :job ORDER BY h.id;

\echo
\echo '=== 6. Erase that history: REFUSED (append-only) ==='
DELETE FROM job.application_status_history WHERE application_id = :application AND job_requirement_id = :job;

\echo
\echo '=== 7. Store an undisclosed salary as 0: REFUSED (Rule 5: missing is never 0) ==='
UPDATE prf.candidate_profile SET current_salary_amount = 0, salary_currency_id = 1 WHERE id = :candidate;

\echo
\echo '=== 8. Placeholder and badly formatted values: REFUSED by the standard domains ==='
SELECT 'NA'::core.person_name;
SELECT 'Priya@Gmail.com'::core.email_address;
SELECT '9876543210'::core.phone_e164;

\echo
\echo '=== 9. Contact details are encrypted at rest; recruiters see the masked value ==='
INSERT INTO prf.candidate_contact (candidate_profile_id, contact_type_ref_code_id, value_encrypted, value_hmac,
    value_masked, phone_country_id, is_primary)
VALUES (:candidate, mst.ref_code_id('CONTACT_TYPE', 'PHONE'), core.pii_encrypt('+919876543210'),
    core.pii_hmac('+919876543210'), core.mask_phone('+919876543210'), (SELECT id FROM mst.country WHERE iso2_code = 'IN'), true);
SELECT left(encode(value_encrypted, 'hex'), 40) || '...' AS stored_on_disk,
       value_masked AS recruiter_sees,
       core.pii_decrypt(value_encrypted) AS after_paid_download
FROM prf.candidate_contact WHERE candidate_profile_id = :candidate;

\echo
\echo '=== 10. Book one interviewer into two overlapping interviews: REFUSED (exclusion constraint) ==='
INSERT INTO job.interview (application_id, job_requirement_id, round_number, scheduled_start_at, scheduled_end_at,
    interviewer_user_account_id, interview_mode_ref_code_id)
VALUES (:application, :job, 1, '2026-10-20 10:00+05:30', '2026-10-20 11:00+05:30', :recruiter, mst.ref_code_id('INTERVIEW_MODE', 'VIDEO'));
INSERT INTO adm.user_account (preferred_language_id, user_type_ref_code_id, account_status_ref_code_id)
VALUES (1, mst.ref_code_id('USER_TYPE', 'CANDIDATE'), mst.ref_code_id('ACCOUNT_STATUS', 'ACTIVE')) RETURNING id AS u2 \gset
INSERT INTO prf.candidate_profile (user_account_id, full_name, profile_visibility_ref_code_id,
    current_salary_disclosure_ref_code_id, expected_salary_disclosure_ref_code_id, source_system_ref_code_id)
VALUES (:u2, 'Rahul Sharma', mst.ref_code_id('PROFILE_VISIBILITY', 'PUBLIC'), mst.ref_code_id('DISCLOSURE_STATUS', 'NOT_DISCLOSED'),
    mst.ref_code_id('DISCLOSURE_STATUS', 'NOT_DISCLOSED'), mst.ref_code_id('SOURCE_SYSTEM', 'DIRECT')) RETURNING id AS c2 \gset
INSERT INTO job.application (job_requirement_id, candidate_profile_id, applied_at, application_status_ref_code_id, application_source_ref_code_id)
VALUES (:job, :c2, now(), mst.ref_code_id('APPLICATION_STATUS', 'SHORTLISTED'), mst.ref_code_id('APPLICATION_SOURCE', 'DIRECT'))
RETURNING id AS a2 \gset
INSERT INTO job.interview (application_id, job_requirement_id, round_number, scheduled_start_at, scheduled_end_at,
    interviewer_user_account_id, interview_mode_ref_code_id)
VALUES (:a2, :job, 1, '2026-10-20 10:30+05:30', '2026-10-20 11:30+05:30', :recruiter, mst.ref_code_id('INTERVIEW_MODE', 'VIDEO'));

\echo
\echo '=== 11. A write by an unidentified user: REFUSED (every change has an accountable actor) ==='
SELECT set_config('app.user_id', '', true) AS ignored \gset
INSERT INTO mst.skill (english_name, skill_category_ref_code_id) VALUES ('Rust', mst.ref_code_id('SKILL_CATEGORY', 'TECHNICAL'));
SELECT set_config('app.user_id', '1', true) AS ignored \gset

\echo
\echo '=== Done. Rolling back: the demo leaves no data behind. ==='
ROLLBACK;
