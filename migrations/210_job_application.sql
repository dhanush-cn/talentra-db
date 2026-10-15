-- 210_job_application.sql
-- Purpose : Jobs and Applications, part 2: the hiring pipeline.
--             application                  hash-partitioned by job_requirement_id (16 partitions)
--             application_status_transition the allowed pipeline moves (data, not code)
--             application_status_history   every status change, written by trigger (append-only)
--             application_answer           questionnaire answers (append-only)
--             interview                    rounds; an interviewer cannot be double-booked
--             offer                        versions; at most one live offer per application
--             joining                      outcome; joining fills a position, never beyond its openings
-- Owner   : Jobs and Applications (whole team, Phase 1)
-- Key decisions (docs/justification.md J-06, J-07):
--   * Hash partitioning by job_requirement_id keeps UNIQUE (job_requirement_id, candidate_profile_id)
--     enforceable: one application per candidate per job, guaranteed by the database.
--   * The status pipeline is enforced by the database from a transition table; the application
--     cannot skip stages (e.g. APPLIED -> JOINED) or reopen a rejected application.
--   * Child tables carry job_requirement_id and reference (id, job_requirement_id): this is what a
--     foreign key to a partitioned table requires, and it lets child rows co-locate by job.

SET ROLE talentra_owner;
SET LOCAL app.user_id = '1';

SELECT mst.define_enumeration('APPLICATION_SOURCE', 'Application source', 'JOB', 'How an application came in.',
    ARRAY['DIRECT', 'SOURCING', 'CONSULTANT', 'REFERRAL', 'CAMPUS_DRIVE', 'LEGACY_IMPORT'],
    ARRAY['Applied directly', 'Sourced by the employer', 'Submitted by a consultant', 'Referral', 'Campus drive', 'Imported from legacy system']);
SELECT mst.define_enumeration('REJECTION_REASON', 'Rejection reason', 'JOB', 'Why an application was rejected.',
    ARRAY['SKILLS_MISMATCH', 'EXPERIENCE_MISMATCH', 'SALARY_MISMATCH', 'LOCATION_MISMATCH', 'KNOCKOUT_ANSWER',
          'INTERVIEW_NOT_CLEARED', 'OFFER_DECLINED', 'POSITION_FILLED', 'OTHER'],
    ARRAY['Skills do not match', 'Experience does not match', 'Salary expectations do not match', 'Location does not match',
          'Knockout screening answer', 'Did not clear interview', 'Offer declined', 'Position filled', 'Other']);
SELECT mst.define_enumeration('INTERVIEW_MODE', 'Interview mode', 'JOB', 'How an interview is held.',
    ARRAY['IN_PERSON', 'VIDEO', 'PHONE'], ARRAY['In person', 'Video call', 'Phone call']);
SELECT mst.define_enumeration('INTERVIEW_OUTCOME', 'Interview outcome', 'JOB', 'Result of an interview round.',
    ARRAY['CLEARED', 'NOT_CLEARED', 'ON_HOLD', 'NO_SHOW', 'CANCELLED'],
    ARRAY['Cleared', 'Not cleared', 'On hold', 'Candidate did not attend', 'Cancelled']);
SELECT mst.define_enumeration('OFFER_STATUS', 'Offer status', 'JOB', 'State of an offer.',
    ARRAY['EXTENDED', 'ACCEPTED', 'DECLINED', 'WITHDRAWN', 'EXPIRED'],
    ARRAY['Extended', 'Accepted', 'Declined', 'Withdrawn by employer', 'Expired']);
SELECT mst.define_enumeration('JOINING_STATUS', 'Joining status', 'JOB', 'Whether an accepted offer turned into a hire.',
    ARRAY['JOINED', 'DEFERRED', 'NO_SHOW'], ARRAY['Joined', 'Joining deferred', 'Did not join']);

-- A resume can only be attached to an application by its own candidate (composite FK target).
ALTER TABLE prf.candidate_resume ADD CONSTRAINT uq_candidate_resume_id_candidate_profile_id
    UNIQUE (id, candidate_profile_id);

-- ===========================================================================
-- application (hash-partitioned by job_requirement_id)
-- ===========================================================================
CREATE TABLE job.application (
    id                         bigint GENERATED ALWAYS AS IDENTITY,
    job_requirement_id         bigint         NOT NULL,
    candidate_profile_id       bigint         NOT NULL,
    job_position_id            bigint,
    candidate_resume_id        bigint,
    referral_id                bigint,
    sourced_by_user_account_id bigint,
    cover_note                 core.text_4000,
    applied_at                 timestamptz    NOT NULL,
    status_changed_at          timestamptz    NOT NULL DEFAULT now(),
    CONSTRAINT pk_application PRIMARY KEY (id, job_requirement_id),
    CONSTRAINT uq_application_job_requirement_id_candidate_profile_id UNIQUE (job_requirement_id, candidate_profile_id),
    CONSTRAINT ck_application_status_changed_at CHECK (status_changed_at >= applied_at),
    CONSTRAINT fk_application_job_requirement_id FOREIGN KEY (job_requirement_id)
        REFERENCES job.job_requirement (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_application_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_application_job_position FOREIGN KEY (job_position_id, job_requirement_id)
        REFERENCES job.job_position (id, job_requirement_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_application_candidate_resume FOREIGN KEY (candidate_resume_id, candidate_profile_id)
        REFERENCES prf.candidate_resume (id, candidate_profile_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_application_referral_id FOREIGN KEY (referral_id)
        REFERENCES prf.referral (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_application_sourced_by_user_account_id FOREIGN KEY (sourced_by_user_account_id)
        REFERENCES adm.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT
) PARTITION BY HASH (job_requirement_id);
SELECT core.create_hash_partitions('job.application', 16);
SELECT core.add_ref_code_column('job.application', 'application_status', 'APPLICATION_STATUS');
SELECT core.add_ref_code_column('job.application', 'application_source', 'APPLICATION_SOURCE');
SELECT core.add_ref_code_column('job.application', 'rejection_reason', 'REJECTION_REASON', true, 'application not rejected');

DO $$
BEGIN
    EXECUTE format('ALTER TABLE job.application ADD CONSTRAINT ck_application_rejection_reason
        CHECK ((rejection_reason_ref_code_id IS NOT NULL) = (application_status_ref_code_id = %s))',
        mst.ref_code_id('APPLICATION_STATUS', 'REJECTED'));
    EXECUTE format('ALTER TABLE job.application ADD CONSTRAINT ck_application_sourced_by
        CHECK ((sourced_by_user_account_id IS NOT NULL) = (application_source_ref_code_id IN (%s, %s)))',
        mst.ref_code_id('APPLICATION_SOURCE', 'SOURCING'), mst.ref_code_id('APPLICATION_SOURCE', 'CONSULTANT'));
    EXECUTE format('ALTER TABLE job.application ADD CONSTRAINT ck_application_referral
        CHECK ((referral_id IS NOT NULL) = (application_source_ref_code_id = %s))',
        mst.ref_code_id('APPLICATION_SOURCE', 'REFERRAL'));
END $$;

-- "My applications" (candidate view): has to visit every partition; see the extrapolation.
CREATE INDEX idx_application_candidate_profile_id ON job.application (candidate_profile_id, applied_at DESC);
-- Employer pipeline view: one partition, one job, grouped by stage.
CREATE INDEX idx_application_job_requirement_id_status ON job.application (job_requirement_id, application_status_ref_code_id, status_changed_at DESC);
CREATE INDEX idx_application_job_position_id ON job.application (job_position_id, job_requirement_id) WHERE job_position_id IS NOT NULL;
CREATE INDEX idx_application_candidate_resume_id ON job.application (candidate_resume_id, candidate_profile_id) WHERE candidate_resume_id IS NOT NULL;
CREATE INDEX idx_application_referral_id ON job.application (referral_id) WHERE referral_id IS NOT NULL;
CREATE INDEX idx_application_sourced_by_user_account_id ON job.application (sourced_by_user_account_id) WHERE sourced_by_user_account_id IS NOT NULL;
SELECT core.add_audit_columns('job.application');
SELECT core.enable_soft_delete('job.application');

COMMENT ON TABLE  job.application IS 'A candidate''s application to a job and its current pipeline stage. One per candidate per job. Hash-partitioned by job_requirement_id into 16 partitions. [lifecycle:soft_delete] [retention: anonymised with the profile; hiring records kept 7 years] [owner:team]';
COMMENT ON COLUMN job.application.id IS '[class:internal] Surrogate key (unique with job_requirement_id).';
COMMENT ON COLUMN job.application.job_requirement_id IS '[class:internal] Job applied to; partition key.';
COMMENT ON COLUMN job.application.candidate_profile_id IS '[class:internal] Candidate.';
COMMENT ON COLUMN job.application.job_position_id IS '[class:internal] [null: applied to the job, location not chosen yet] Position (location) applied for; must belong to the same job.';
COMMENT ON COLUMN job.application.candidate_resume_id IS '[class:internal] [null: applied with the profile only] Resume version sent; must belong to the same candidate.';
COMMENT ON COLUMN job.application.referral_id IS '[class:internal] [null: not a referral] Referral that led to the application.';
COMMENT ON COLUMN job.application.sourced_by_user_account_id IS '[class:internal] [null: candidate applied themselves] Recruiter or consultant who submitted the candidate.';
COMMENT ON COLUMN job.application.cover_note IS '[class:personal] [null: no cover note] Message from the candidate.';
COMMENT ON COLUMN job.application.applied_at IS '[class:internal] When the application was made (UTC).';
COMMENT ON COLUMN job.application.status_changed_at IS '[class:internal] When the current status was set (UTC); maintained by trigger.';

-- ===========================================================================
-- application_status_transition: the pipeline as data
-- ===========================================================================
CREATE TABLE job.application_status_transition (
    id bigint GENERATED ALWAYS AS IDENTITY,
    CONSTRAINT pk_application_status_transition PRIMARY KEY (id)
);
SELECT core.add_ref_code_column('job.application_status_transition', 'from_status', 'APPLICATION_STATUS', true,
    'transition creates a new application (initial status)');
SELECT core.add_ref_code_column('job.application_status_transition', 'to_status', 'APPLICATION_STATUS');
ALTER TABLE job.application_status_transition ADD CONSTRAINT uq_application_status_transition_from_status_ref_code_id_to_status_ref_code_id
    UNIQUE NULLS NOT DISTINCT (from_status_ref_code_id, to_status_ref_code_id);
SELECT core.add_audit_columns('job.application_status_transition');

COMMENT ON TABLE  job.application_status_transition IS 'Allowed pipeline moves. A row with no from_status lists a valid initial status. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN job.application_status_transition.id IS '[class:internal] Surrogate key.';

INSERT INTO job.application_status_transition (from_status_ref_code_id, to_status_ref_code_id)
SELECT CASE WHEN v.from_code IS NULL THEN NULL ELSE mst.ref_code_id('APPLICATION_STATUS', v.from_code) END,
       mst.ref_code_id('APPLICATION_STATUS', v.to_code)
FROM (VALUES
    (NULL, 'APPLIED'), (NULL, 'SHORTLISTED'),                 -- sourced candidates may start shortlisted
    ('APPLIED', 'SHORTLISTED'), ('APPLIED', 'REJECTED'), ('APPLIED', 'WITHDRAWN'),
    ('SHORTLISTED', 'INTERVIEWED'), ('SHORTLISTED', 'REJECTED'), ('SHORTLISTED', 'WITHDRAWN'),
    ('INTERVIEWED', 'OFFERED'), ('INTERVIEWED', 'REJECTED'), ('INTERVIEWED', 'WITHDRAWN'),
    ('OFFERED', 'JOINED'), ('OFFERED', 'REJECTED'), ('OFFERED', 'WITHDRAWN')
    -- JOINED, REJECTED and WITHDRAWN are final.
) AS v(from_code, to_code);

-- ===========================================================================
-- application_status_history (append-only, written only by trigger)
-- ===========================================================================
CREATE TABLE job.application_status_history (
    id                 bigint GENERATED ALWAYS AS IDENTITY,
    application_id     bigint      NOT NULL,
    job_requirement_id bigint      NOT NULL,
    changed_at         timestamptz NOT NULL,
    CONSTRAINT pk_application_status_history PRIMARY KEY (id, job_requirement_id),
    CONSTRAINT fk_application_status_history_application FOREIGN KEY (application_id, job_requirement_id)
        REFERENCES job.application (id, job_requirement_id) ON UPDATE RESTRICT ON DELETE RESTRICT
) PARTITION BY HASH (job_requirement_id);
SELECT core.create_hash_partitions('job.application_status_history', 16);
SELECT core.add_ref_code_column('job.application_status_history', 'from_status', 'APPLICATION_STATUS', true,
    'first status of the application');
SELECT core.add_ref_code_column('job.application_status_history', 'to_status', 'APPLICATION_STATUS');
SELECT core.add_ref_code_column('job.application_status_history', 'rejection_reason', 'REJECTION_REASON', true,
    'change was not a rejection');
CREATE INDEX idx_application_status_history_application_id
    ON job.application_status_history (application_id, job_requirement_id, changed_at);
SELECT core.add_creation_columns('job.application_status_history');
COMMENT ON TABLE job.application_status_history IS 'Every pipeline stage change: who, when, from what, to what and why (rejections). The candidate''s application history. [retention: as application] [owner:team]';
SELECT core.make_append_only('job.application_status_history');

COMMENT ON COLUMN job.application_status_history.id IS '[class:internal] Surrogate key (unique with job_requirement_id).';
COMMENT ON COLUMN job.application_status_history.application_id IS '[class:internal] Application.';
COMMENT ON COLUMN job.application_status_history.job_requirement_id IS '[class:internal] Job; partition key, co-located with the application.';
COMMENT ON COLUMN job.application_status_history.changed_at IS '[class:internal] When the change took effect (UTC).';

-- ===========================================================================
-- Pipeline enforcement and history triggers
-- ===========================================================================
CREATE FUNCTION job.trg_application_enforce_pipeline()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_from text;
    v_to   text;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.candidate_profile_id <> OLD.candidate_profile_id OR NEW.job_requirement_id <> OLD.job_requirement_id THEN
            RAISE EXCEPTION 'an application cannot be moved to another candidate or job'
                USING ERRCODE = 'check_violation';
        END IF;
        IF NEW.application_status_ref_code_id IS NOT DISTINCT FROM OLD.application_status_ref_code_id THEN
            RETURN NEW;
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM job.application_status_transition t
        WHERE t.from_status_ref_code_id IS NOT DISTINCT FROM
                  CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.application_status_ref_code_id END
          AND t.to_status_ref_code_id = NEW.application_status_ref_code_id)
    THEN
        SELECT code INTO v_to FROM mst.ref_code WHERE id = NEW.application_status_ref_code_id;
        IF TG_OP = 'INSERT' THEN
            RAISE EXCEPTION 'a new application cannot start as %', v_to
                USING ERRCODE = 'check_violation',
                      HINT = 'Allowed moves are listed in job.application_status_transition.';
        END IF;
        SELECT code INTO v_from FROM mst.ref_code WHERE id = OLD.application_status_ref_code_id;
        RAISE EXCEPTION 'application status cannot move from % to %', v_from, v_to
            USING ERRCODE = 'check_violation',
                  HINT = 'Allowed moves are listed in job.application_status_transition.';
    END IF;

    NEW.status_changed_at := CASE WHEN TG_OP = 'INSERT' THEN NEW.applied_at ELSE now() END;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_application_enforce_pipeline
    BEFORE INSERT OR UPDATE ON job.application
    FOR EACH ROW EXECUTE FUNCTION job.trg_application_enforce_pipeline();

CREATE FUNCTION job.trg_application_record_history()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.application_status_ref_code_id IS NOT DISTINCT FROM OLD.application_status_ref_code_id THEN
        RETURN NULL;
    END IF;
    INSERT INTO job.application_status_history
        (application_id, job_requirement_id, from_status_ref_code_id, to_status_ref_code_id,
         rejection_reason_ref_code_id, changed_at)
    VALUES
        (NEW.id, NEW.job_requirement_id,
         CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.application_status_ref_code_id END,
         NEW.application_status_ref_code_id, NEW.rejection_reason_ref_code_id, NEW.status_changed_at);
    RETURN NULL;
END $$;

CREATE TRIGGER trg_application_record_history
    AFTER INSERT OR UPDATE ON job.application
    FOR EACH ROW EXECUTE FUNCTION job.trg_application_record_history();

-- ===========================================================================
-- application_answer (append-only: answers are fixed once submitted)
-- ===========================================================================
CREATE TABLE job.application_answer (
    id                        bigint GENERATED ALWAYS AS IDENTITY,
    application_id            bigint         NOT NULL,
    job_requirement_id        bigint         NOT NULL,
    questionnaire_question_id bigint         NOT NULL,
    question_option_id        bigint,
    answer_text               core.text_4000,
    answer_number             numeric(18, 4),
    answer_date               date,
    CONSTRAINT pk_application_answer PRIMARY KEY (id, job_requirement_id),
    CONSTRAINT uq_application_answer_one_per_option UNIQUE NULLS NOT DISTINCT
        (application_id, job_requirement_id, questionnaire_question_id, question_option_id),
    CONSTRAINT ck_application_answer_exactly_one_value CHECK (
        num_nonnulls(question_option_id, answer_text, answer_number, answer_date) = 1),
    CONSTRAINT fk_application_answer_application FOREIGN KEY (application_id, job_requirement_id)
        REFERENCES job.application (id, job_requirement_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_application_answer_questionnaire_question_id FOREIGN KEY (questionnaire_question_id)
        REFERENCES job.questionnaire_question (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_application_answer_question_option FOREIGN KEY (question_option_id, questionnaire_question_id)
        REFERENCES job.question_option (id, questionnaire_question_id) ON UPDATE RESTRICT ON DELETE RESTRICT
) PARTITION BY HASH (job_requirement_id);
SELECT core.create_hash_partitions('job.application_answer', 16);
CREATE INDEX idx_application_answer_questionnaire_question_id ON job.application_answer (questionnaire_question_id);
CREATE INDEX idx_application_answer_question_option_id ON job.application_answer (question_option_id, questionnaire_question_id)
    WHERE question_option_id IS NOT NULL;
SELECT core.add_creation_columns('job.application_answer');
COMMENT ON TABLE job.application_answer IS 'Screening answers. One row per answer; multiple-choice questions have one row per chosen option. [retention: as application] [owner:team]';
SELECT core.make_append_only('job.application_answer');

COMMENT ON COLUMN job.application_answer.id IS '[class:internal] Surrogate key (unique with job_requirement_id).';
COMMENT ON COLUMN job.application_answer.application_id IS '[class:internal] Application.';
COMMENT ON COLUMN job.application_answer.job_requirement_id IS '[class:internal] Job; partition key.';
COMMENT ON COLUMN job.application_answer.questionnaire_question_id IS '[class:internal] Question answered.';
COMMENT ON COLUMN job.application_answer.question_option_id IS '[class:internal] [null: question is not multiple choice] Chosen option; must belong to the question.';
COMMENT ON COLUMN job.application_answer.answer_text IS '[class:personal] [null: answer is an option, number or date] Free-text answer.';
COMMENT ON COLUMN job.application_answer.answer_number IS '[class:personal] [null: answer is not numeric] Numeric answer.';
COMMENT ON COLUMN job.application_answer.answer_date IS '[class:personal] [null: answer is not a date] Date answer.';

-- ===========================================================================
-- interview
-- ===========================================================================
CREATE TABLE job.interview (
    id                          bigint GENERATED ALWAYS AS IDENTITY,
    application_id              bigint            NOT NULL,
    job_requirement_id          bigint            NOT NULL,
    round_number                core.positive_int NOT NULL,
    scheduled_start_at          timestamptz       NOT NULL,
    scheduled_end_at            timestamptz       NOT NULL,
    interviewer_user_account_id bigint,
    feedback                    core.text_4000,
    rating                      smallint,
    CONSTRAINT pk_interview PRIMARY KEY (id),
    CONSTRAINT uq_interview_application_id_round_number UNIQUE (application_id, job_requirement_id, round_number),
    CONSTRAINT ck_interview_schedule CHECK (scheduled_end_at > scheduled_start_at),
    CONSTRAINT ck_interview_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT fk_interview_application FOREIGN KEY (application_id, job_requirement_id)
        REFERENCES job.application (id, job_requirement_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_interview_interviewer_user_account_id FOREIGN KEY (interviewer_user_account_id)
        REFERENCES adm.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('job.interview', 'interview_mode', 'INTERVIEW_MODE');
SELECT core.add_ref_code_column('job.interview', 'interview_outcome', 'INTERVIEW_OUTCOME', true, 'interview not held yet');
SELECT core.add_audit_columns('job.interview');
SELECT core.enable_soft_delete('job.interview');

-- An interviewer cannot be booked into two overlapping interviews (cancelled ones excluded).
DO $$
BEGIN
    EXECUTE format('ALTER TABLE job.interview ADD CONSTRAINT ex_interview_interviewer_no_overlap
        EXCLUDE USING gist (interviewer_user_account_id WITH =, tstzrange(scheduled_start_at, scheduled_end_at) WITH &&)
        WHERE (interviewer_user_account_id IS NOT NULL AND deleted_at IS NULL
               AND interview_outcome_ref_code_id IS DISTINCT FROM %s)',
        mst.ref_code_id('INTERVIEW_OUTCOME', 'CANCELLED'));
END $$;
CREATE INDEX idx_interview_interviewer_user_account_id ON job.interview (interviewer_user_account_id, scheduled_start_at);

COMMENT ON TABLE  job.interview IS 'Interview rounds for an application. [lifecycle:soft_delete] [retention: as application] [owner:team]';
COMMENT ON COLUMN job.interview.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.interview.application_id IS '[class:internal] Application.';
COMMENT ON COLUMN job.interview.job_requirement_id IS '[class:internal] Job (with application_id, references the partitioned application).';
COMMENT ON COLUMN job.interview.round_number IS '[class:internal] 1 for the first round, 2 for the second ...';
COMMENT ON COLUMN job.interview.scheduled_start_at IS '[class:internal] Start (UTC).';
COMMENT ON COLUMN job.interview.scheduled_end_at IS '[class:internal] End (UTC); after the start.';
COMMENT ON COLUMN job.interview.interviewer_user_account_id IS '[class:internal] [null: interviewer not assigned yet] Lead interviewer; cannot be double-booked.';
COMMENT ON COLUMN job.interview.feedback IS '[class:personal] [null: no feedback recorded yet] Interviewer feedback.';
COMMENT ON COLUMN job.interview.rating IS '[class:personal] [null: not rated yet] Rating 1–5.';

-- ===========================================================================
-- offer
-- ===========================================================================
CREATE TABLE job.offer (
    id                    bigint GENERATED ALWAYS AS IDENTITY,
    application_id        bigint            NOT NULL,
    job_requirement_id    bigint            NOT NULL,
    offer_version         core.positive_int NOT NULL,
    offered_amount        core.money_amount NOT NULL,
    currency_id           bigint            NOT NULL,
    extended_at           timestamptz       NOT NULL,
    valid_until           date              NOT NULL,
    responded_at          timestamptz,
    expected_joining_date date,
    letter_storage_key    core.text_1000,
    CONSTRAINT pk_offer PRIMARY KEY (id),
    CONSTRAINT uq_offer_application_id_offer_version UNIQUE (application_id, job_requirement_id, offer_version),
    CONSTRAINT uq_offer_id_application_id_job_requirement_id UNIQUE (id, application_id, job_requirement_id),
    CONSTRAINT ck_offer_amount CHECK (offered_amount > 0),
    CONSTRAINT ck_offer_valid_until CHECK (valid_until >= (extended_at AT TIME ZONE 'UTC')::date),
    CONSTRAINT ck_offer_responded_at CHECK (responded_at >= extended_at),
    CONSTRAINT fk_offer_application FOREIGN KEY (application_id, job_requirement_id)
        REFERENCES job.application (id, job_requirement_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_offer_currency_id FOREIGN KEY (currency_id)
        REFERENCES mst.currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('job.offer', 'salary_period', 'SALARY_PERIOD');
SELECT core.add_ref_code_column('job.offer', 'offer_status', 'OFFER_STATUS');
SELECT core.add_audit_columns('job.offer');
SELECT core.enable_soft_delete('job.offer');
DO $$
DECLARE
    v_extended bigint := mst.ref_code_id('OFFER_STATUS', 'EXTENDED');
    v_accepted bigint := mst.ref_code_id('OFFER_STATUS', 'ACCEPTED');
    v_declined bigint := mst.ref_code_id('OFFER_STATUS', 'DECLINED');
BEGIN
    -- The candidate's response time exists exactly when they accepted or declined.
    EXECUTE format('ALTER TABLE job.offer ADD CONSTRAINT ck_offer_response
        CHECK ((responded_at IS NOT NULL) = (offer_status_ref_code_id IN (%s, %s)))', v_accepted, v_declined);
    -- At most one live (extended or accepted) offer per application.
    EXECUTE format('CREATE UNIQUE INDEX uq_offer_one_live_per_application ON job.offer (application_id, job_requirement_id)
        WHERE offer_status_ref_code_id IN (%s, %s) AND deleted_at IS NULL', v_extended, v_accepted);
END $$;

COMMENT ON TABLE  job.offer IS 'Offers made on an application; a revised offer is a new version. [lifecycle:soft_delete] [retention: as application] [owner:team]';
COMMENT ON COLUMN job.offer.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.offer.application_id IS '[class:internal] Application.';
COMMENT ON COLUMN job.offer.job_requirement_id IS '[class:internal] Job (with application_id, references the partitioned application).';
COMMENT ON COLUMN job.offer.offer_version IS '[class:internal] 1 for the first offer, 2 for a revision ...';
COMMENT ON COLUMN job.offer.offered_amount IS '[class:personal] Offered salary for salary_period.';
COMMENT ON COLUMN job.offer.currency_id IS '[class:personal] Currency of offered_amount.';
COMMENT ON COLUMN job.offer.extended_at IS '[class:internal] When the offer was made (UTC).';
COMMENT ON COLUMN job.offer.valid_until IS '[class:internal] Last day the candidate can accept.';
COMMENT ON COLUMN job.offer.responded_at IS '[class:internal] [null: no response yet, or offer withdrawn or expired] When the candidate accepted or declined (UTC).';
COMMENT ON COLUMN job.offer.expected_joining_date IS '[class:internal] [null: to be agreed] Planned start date.';
COMMENT ON COLUMN job.offer.letter_storage_key IS '[class:personal] [null: letter not generated yet] Object-storage key of the offer letter.';

-- ===========================================================================
-- joining
-- ===========================================================================
CREATE TABLE job.joining (
    id                 bigint GENERATED ALWAYS AS IDENTITY,
    application_id     bigint NOT NULL,
    job_requirement_id bigint NOT NULL,
    offer_id           bigint NOT NULL,
    joined_on          date,
    CONSTRAINT pk_joining PRIMARY KEY (id),
    CONSTRAINT uq_joining_application_id UNIQUE (application_id, job_requirement_id),
    CONSTRAINT fk_joining_application FOREIGN KEY (application_id, job_requirement_id)
        REFERENCES job.application (id, job_requirement_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_joining_offer FOREIGN KEY (offer_id, application_id, job_requirement_id)
        REFERENCES job.offer (id, application_id, job_requirement_id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('job.joining', 'joining_status', 'JOINING_STATUS');
DO $$
BEGIN
    EXECUTE format('ALTER TABLE job.joining ADD CONSTRAINT ck_joining_joined_on
        CHECK ((joined_on IS NOT NULL) = (joining_status_ref_code_id = %s))', mst.ref_code_id('JOINING_STATUS', 'JOINED'));
END $$;
CREATE INDEX idx_joining_offer_id ON job.joining (offer_id, application_id, job_requirement_id);
SELECT core.add_audit_columns('job.joining');

COMMENT ON TABLE  job.joining IS 'Whether an accepted offer became a hire. Joining fills a position; a position can never be filled beyond its openings. [lifecycle:hard_delete] [retention: as application] [owner:team]';
COMMENT ON COLUMN job.joining.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.joining.application_id IS '[class:internal] Application.';
COMMENT ON COLUMN job.joining.job_requirement_id IS '[class:internal] Job (with application_id, references the partitioned application).';
COMMENT ON COLUMN job.joining.offer_id IS '[class:internal] Accepted offer; must belong to the same application.';
COMMENT ON COLUMN job.joining.joined_on IS '[class:internal] [null: candidate has not joined (deferred or no-show)] First working day.';

-- Joining requires an accepted offer, and maintains job_position.filled_count.
-- ck_job_position_not_overfilled then makes over-hiring impossible.
CREATE FUNCTION job.trg_joining_fill_position()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_joined   bigint := mst.ref_code_id('JOINING_STATUS', 'JOINED');
    v_was      boolean := TG_OP = 'UPDATE' AND OLD.joining_status_ref_code_id = v_joined;
    v_is       boolean := NEW.joining_status_ref_code_id = v_joined;
    v_position bigint;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM job.offer o
                   WHERE o.id = NEW.offer_id
                     AND o.offer_status_ref_code_id = mst.ref_code_id('OFFER_STATUS', 'ACCEPTED')) THEN
        RAISE EXCEPTION 'joining requires an accepted offer' USING ERRCODE = 'check_violation';
    END IF;

    IF v_was = v_is THEN
        RETURN NEW;
    END IF;

    SELECT a.job_position_id INTO v_position
    FROM job.application a
    WHERE a.id = NEW.application_id AND a.job_requirement_id = NEW.job_requirement_id;

    IF v_position IS NOT NULL THEN
        UPDATE job.job_position
        SET filled_count = filled_count + CASE WHEN v_is THEN 1 ELSE -1 END
        WHERE id = v_position;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_joining_fill_position
    BEFORE INSERT OR UPDATE ON job.joining
    FOR EACH ROW EXECUTE FUNCTION job.trg_joining_fill_position();

GRANT SELECT, INSERT, UPDATE ON job.application, job.interview, job.offer, job.joining TO talentra_app;
GRANT SELECT, INSERT ON job.application_status_history, job.application_answer TO talentra_app;
GRANT SELECT ON job.application_status_transition TO talentra_app;

RESET ROLE;
