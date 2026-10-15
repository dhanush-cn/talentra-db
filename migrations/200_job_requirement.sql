-- 200_job_requirement.sql
-- Purpose : Jobs and Applications, part 1: what an employer posts.
--             job_requirement                 the job post and its publish state
--             job_position                    openings per location; filled_count can never exceed openings
--             job_requirement_skill / _qualification
--             questionnaire, questionnaire_question, question_option, job_requirement_questionnaire
-- Owner   : Jobs and Applications (whole team, Phase 1)
-- Key decisions:
--   * Gigs are NOT stored here; they live in the gig schema (see docs/justification.md J-03).
--   * is_open_to_consultants is the switch the Sourcing module checks before a consultant may act.
--   * Salary follows the Rule 5 pattern: a disclosure status, amounts only when disclosed.

SET ROLE talentra_owner;
SET LOCAL app.user_id = '1';

SELECT mst.define_enumeration('JOB_PUBLISH_STATUS', 'Job publish status', 'JOB', 'Lifecycle of a job requirement.',
    ARRAY['DRAFT', 'PENDING_APPROVAL', 'PUBLISHED', 'PAUSED', 'CLOSED', 'EXPIRED'],
    ARRAY['Draft', 'Pending approval', 'Published', 'Paused', 'Closed', 'Expired']);
SELECT mst.define_enumeration('ANSWER_TYPE', 'Answer type', 'JOB', 'Kind of answer a screening question expects.',
    ARRAY['TEXT', 'NUMBER', 'DATE', 'SINGLE_CHOICE', 'MULTI_CHOICE'],
    ARRAY['Free text', 'Number', 'Date', 'Single choice', 'Multiple choice']);

-- ===========================================================================
-- job_requirement
-- ===========================================================================
CREATE TABLE job.job_requirement (
    id                        bigint GENERATED ALWAYS AS IDENTITY,
    public_id                 uuid                  NOT NULL DEFAULT gen_random_uuid(),
    organisation_id           bigint                NOT NULL,
    posted_by_user_account_id bigint                NOT NULL,
    title                     core.text_255         NOT NULL,
    job_role_id               bigint,
    industry_id               bigint,
    description               core.long_text        NOT NULL,
    description_language_id   bigint,
    min_experience_months     core.non_negative_int NOT NULL DEFAULT 0,
    max_experience_months     core.non_negative_int,
    salary_currency_id        bigint,
    salary_min_amount         core.money_amount,
    salary_max_amount         core.money_amount,
    is_open_to_consultants    boolean               NOT NULL DEFAULT false,
    published_at              timestamptz,
    expires_at                timestamptz,
    closed_at                 timestamptz,
    source_record_id          core.text_100,
    search_document           tsvector NOT NULL GENERATED ALWAYS AS (
        setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('simple', left(coalesce(description, ''), 20000)), 'B')) STORED,
    CONSTRAINT pk_job_requirement PRIMARY KEY (id),
    CONSTRAINT uq_job_requirement_public_id UNIQUE (public_id),
    CONSTRAINT ck_job_requirement_experience CHECK (max_experience_months >= min_experience_months),
    CONSTRAINT ck_job_requirement_salary_range CHECK (salary_min_amount >= 0 AND salary_max_amount >= salary_min_amount),
    CONSTRAINT ck_job_requirement_dates CHECK (expires_at > published_at AND closed_at >= published_at),
    CONSTRAINT fk_job_requirement_organisation_id FOREIGN KEY (organisation_id)
        REFERENCES org.organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_requirement_posted_by_user_account_id FOREIGN KEY (posted_by_user_account_id)
        REFERENCES adm.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_requirement_job_role_id FOREIGN KEY (job_role_id)
        REFERENCES mst.job_role (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_requirement_industry_id FOREIGN KEY (industry_id)
        REFERENCES mst.industry (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_requirement_description_language_id FOREIGN KEY (description_language_id)
        REFERENCES mst.language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_requirement_salary_currency_id FOREIGN KEY (salary_currency_id)
        REFERENCES mst.currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('job.job_requirement', 'job_category', 'JOB_CATEGORY');
SELECT core.add_ref_code_column('job.job_requirement', 'employment_type', 'EMPLOYMENT_TYPE');
SELECT core.add_ref_code_column('job.job_requirement', 'work_type', 'WORK_TYPE');
SELECT core.add_ref_code_column('job.job_requirement', 'salary_disclosure', 'DISCLOSURE_STATUS');
SELECT core.add_ref_code_column('job.job_requirement', 'salary_period', 'SALARY_PERIOD', true, 'salary not disclosed');
SELECT core.add_ref_code_column('job.job_requirement', 'publish_status', 'JOB_PUBLISH_STATUS');
SELECT core.add_ref_code_column('job.job_requirement', 'source_system', 'SOURCE_SYSTEM');

DO $$
DECLARE
    v_disclosed bigint := mst.ref_code_id('DISCLOSURE_STATUS', 'DISCLOSED');
    v_draft     bigint := mst.ref_code_id('JOB_PUBLISH_STATUS', 'DRAFT');
    v_pending   bigint := mst.ref_code_id('JOB_PUBLISH_STATUS', 'PENDING_APPROVAL');
    v_closed    bigint := mst.ref_code_id('JOB_PUBLISH_STATUS', 'CLOSED');
    v_direct    bigint := mst.ref_code_id('SOURCE_SYSTEM', 'DIRECT');
    v_gig       bigint := mst.ref_code_id('JOB_CATEGORY', 'GIG_PROJECT');
BEGIN
    -- Rule 5: salary amounts, currency and period exist exactly when the salary is disclosed.
    EXECUTE format('ALTER TABLE job.job_requirement ADD CONSTRAINT ck_job_requirement_salary_disclosed
        CHECK ((salary_disclosure_ref_code_id = %s) = (salary_min_amount IS NOT NULL)
               AND (salary_min_amount IS NULL) = (salary_currency_id IS NULL)
               AND (salary_min_amount IS NULL) = (salary_period_ref_code_id IS NULL)
               AND (salary_max_amount IS NULL OR salary_min_amount IS NOT NULL))', v_disclosed);
    -- A job that has ever been published carries its publish time; drafts never do.
    EXECUTE format('ALTER TABLE job.job_requirement ADD CONSTRAINT ck_job_requirement_published_at
        CHECK ((publish_status_ref_code_id IN (%s, %s)) = (published_at IS NULL))', v_draft, v_pending);
    EXECUTE format('ALTER TABLE job.job_requirement ADD CONSTRAINT ck_job_requirement_closed_at
        CHECK ((publish_status_ref_code_id = %s) = (closed_at IS NOT NULL))', v_closed);
    EXECUTE format('ALTER TABLE job.job_requirement ADD CONSTRAINT ck_job_requirement_source_record_id
        CHECK (source_system_ref_code_id = %s OR source_record_id IS NOT NULL)', v_direct);
    -- Gig work is a separate subsystem (justification J-03): never posted as a job requirement.
    EXECUTE format('ALTER TABLE job.job_requirement ADD CONSTRAINT ck_job_requirement_not_gig
        CHECK (job_category_ref_code_id <> %s)', v_gig);
END $$;

ALTER TABLE job.job_requirement ADD CONSTRAINT uq_job_requirement_source_system_ref_code_id_source_record_id
    UNIQUE (source_system_ref_code_id, source_record_id);
CREATE INDEX idx_job_requirement_organisation_id ON job.job_requirement (organisation_id, publish_status_ref_code_id);
CREATE INDEX idx_job_requirement_posted_by_user_account_id ON job.job_requirement (posted_by_user_account_id);
CREATE INDEX idx_job_requirement_job_role_id ON job.job_requirement (job_role_id);
CREATE INDEX idx_job_requirement_industry_id ON job.job_requirement (industry_id);
CREATE INDEX idx_job_requirement_search_document ON job.job_requirement USING gin (search_document);
SELECT core.add_audit_columns('job.job_requirement');
SELECT core.enable_soft_delete('job.job_requirement');

-- Candidate job search scans only live, published jobs: keep that index small.
DO $$
BEGIN
    EXECUTE format('CREATE INDEX idx_job_requirement_published ON job.job_requirement (published_at DESC)
        INCLUDE (organisation_id, job_role_id) WHERE publish_status_ref_code_id = %s AND deleted_at IS NULL',
        mst.ref_code_id('JOB_PUBLISH_STATUS', 'PUBLISHED'));
END $$;

COMMENT ON TABLE  job.job_requirement IS 'A job post by an employer: requirements, salary, publish state and consultant openness. [lifecycle:soft_delete] [retention: 7 years after closing for hiring records] [owner:team]';
COMMENT ON COLUMN job.job_requirement.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.job_requirement.public_id IS '[class:public] Identifier used in URLs and APIs.';
COMMENT ON COLUMN job.job_requirement.organisation_id IS '[class:internal] Employer or client the job belongs to; recruiters only see their own organisation''s jobs.';
COMMENT ON COLUMN job.job_requirement.posted_by_user_account_id IS '[class:internal] Who created the post.';
COMMENT ON COLUMN job.job_requirement.title IS '[class:public] Job title.';
COMMENT ON COLUMN job.job_requirement.job_role_id IS '[class:public] [null: title not mapped to a standard role yet] Standard role.';
COMMENT ON COLUMN job.job_requirement.industry_id IS '[class:public] [null: employer did not classify the job] Industry.';
COMMENT ON COLUMN job.job_requirement.description IS '[class:public] [unbounded: job descriptions are long-form content; the application limits them to 50 KB] Full description as entered.';
COMMENT ON COLUMN job.job_requirement.description_language_id IS '[class:internal] [null: language not detected] Language of the description (Rule 7).';
COMMENT ON COLUMN job.job_requirement.min_experience_months IS '[class:public] Minimum experience; 0 for freshers. Default 0.';
COMMENT ON COLUMN job.job_requirement.max_experience_months IS '[class:public] [null: no upper limit] Maximum experience.';
COMMENT ON COLUMN job.job_requirement.salary_currency_id IS '[class:public] [null: salary not disclosed] Currency of the salary range.';
COMMENT ON COLUMN job.job_requirement.salary_min_amount IS '[class:public] [null: salary not disclosed; see salary_disclosure] Lower bound of the salary range.';
COMMENT ON COLUMN job.job_requirement.salary_max_amount IS '[class:public] [null: not disclosed, or no upper bound stated] Upper bound of the salary range.';
COMMENT ON COLUMN job.job_requirement.is_open_to_consultants IS '[class:internal] Consultants may source candidates for this job. Default false.';
COMMENT ON COLUMN job.job_requirement.published_at IS '[class:public] [null: never published (draft or pending approval)] First publish time (UTC).';
COMMENT ON COLUMN job.job_requirement.expires_at IS '[class:public] [null: no expiry set] When the post stops accepting applications (UTC).';
COMMENT ON COLUMN job.job_requirement.closed_at IS '[class:internal] [null: not closed] When the employer closed the job (UTC).';
COMMENT ON COLUMN job.job_requirement.source_record_id IS '[class:internal] [null: posted directly on the platform] Record id in the legacy system.';
COMMENT ON COLUMN job.job_requirement.search_document IS '[class:public] Full-text search vector over title (weight A) and description (weight B); generated, language-neutral ''simple'' configuration for multilingual text.';

-- ===========================================================================
-- job_position: openings per location
-- ===========================================================================
CREATE TABLE job.job_position (
    id                 bigint GENERATED ALWAYS AS IDENTITY,
    job_requirement_id bigint                NOT NULL,
    city_id            bigint,
    openings_count     core.positive_int     NOT NULL,
    filled_count       core.non_negative_int NOT NULL DEFAULT 0,
    CONSTRAINT pk_job_position PRIMARY KEY (id),
    CONSTRAINT uq_job_position_job_requirement_id_city_id UNIQUE NULLS NOT DISTINCT (job_requirement_id, city_id),
    -- Target of composite FKs: a position can only be used with its own job requirement.
    CONSTRAINT uq_job_position_id_job_requirement_id UNIQUE (id, job_requirement_id),
    CONSTRAINT ck_job_position_not_overfilled CHECK (filled_count <= openings_count),
    CONSTRAINT fk_job_position_job_requirement_id FOREIGN KEY (job_requirement_id)
        REFERENCES job.job_requirement (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_job_position_city_id FOREIGN KEY (city_id)
        REFERENCES mst.city (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_job_position_city_id ON job.job_position (city_id, job_requirement_id);
SELECT core.add_audit_columns('job.job_position');

COMMENT ON TABLE  job.job_position IS 'Openings of a job per location. filled_count is maintained when candidates join and can never exceed openings_count. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN job.job_position.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.job_position.job_requirement_id IS '[class:internal] Job.';
COMMENT ON COLUMN job.job_position.city_id IS '[class:public] [null: remote position, no fixed location] Work location.';
COMMENT ON COLUMN job.job_position.openings_count IS '[class:public] Number of people to hire at this location (> 0).';
COMMENT ON COLUMN job.job_position.filled_count IS '[class:internal] Candidates who have joined. Default 0.';

-- ===========================================================================
-- job_requirement_skill and job_requirement_qualification
-- ===========================================================================
CREATE TABLE job.job_requirement_skill (
    id                 bigint GENERATED ALWAYS AS IDENTITY,
    job_requirement_id bigint        NOT NULL,
    skill_id           bigint        NOT NULL,
    is_mandatory       boolean       NOT NULL DEFAULT true,
    min_years          numeric(4, 1),
    CONSTRAINT pk_job_requirement_skill PRIMARY KEY (id),
    CONSTRAINT uq_job_requirement_skill_job_requirement_id_skill_id UNIQUE (job_requirement_id, skill_id),
    CONSTRAINT ck_job_requirement_skill_min_years CHECK (min_years BETWEEN 0 AND 60),
    CONSTRAINT fk_job_requirement_skill_job_requirement_id FOREIGN KEY (job_requirement_id)
        REFERENCES job.job_requirement (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_job_requirement_skill_skill_id FOREIGN KEY (skill_id)
        REFERENCES mst.skill (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
-- Matching runs both ways: jobs needing a skill, skills a job needs.
CREATE INDEX idx_job_requirement_skill_skill_id ON job.job_requirement_skill (skill_id, job_requirement_id);
SELECT core.add_audit_columns('job.job_requirement_skill');

COMMENT ON TABLE  job.job_requirement_skill IS 'Skills a job asks for. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN job.job_requirement_skill.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.job_requirement_skill.job_requirement_id IS '[class:internal] Job.';
COMMENT ON COLUMN job.job_requirement_skill.skill_id IS '[class:public] Skill required.';
COMMENT ON COLUMN job.job_requirement_skill.is_mandatory IS '[class:public] Must-have rather than nice-to-have. Default true.';
COMMENT ON COLUMN job.job_requirement_skill.min_years IS '[class:public] [null: no minimum stated] Minimum years with the skill.';

CREATE TABLE job.job_requirement_qualification (
    id                 bigint GENERATED ALWAYS AS IDENTITY,
    job_requirement_id bigint  NOT NULL,
    qualification_id   bigint  NOT NULL,
    is_mandatory       boolean NOT NULL DEFAULT true,
    CONSTRAINT pk_job_requirement_qualification PRIMARY KEY (id),
    CONSTRAINT uq_job_requirement_qualification_job_requirement_id_qualification_id UNIQUE (job_requirement_id, qualification_id),
    CONSTRAINT fk_job_requirement_qualification_job_requirement_id FOREIGN KEY (job_requirement_id)
        REFERENCES job.job_requirement (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_job_requirement_qualification_qualification_id FOREIGN KEY (qualification_id)
        REFERENCES mst.qualification (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_audit_columns('job.job_requirement_qualification');

COMMENT ON TABLE  job.job_requirement_qualification IS 'Qualifications a job asks for. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN job.job_requirement_qualification.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.job_requirement_qualification.job_requirement_id IS '[class:internal] Job.';
COMMENT ON COLUMN job.job_requirement_qualification.qualification_id IS '[class:public] Qualification required.';
COMMENT ON COLUMN job.job_requirement_qualification.is_mandatory IS '[class:public] Must-have. Default true.';

-- ===========================================================================
-- Questionnaires attached to job requirements
-- ===========================================================================
CREATE TABLE job.questionnaire (
    id              bigint GENERATED ALWAYS AS IDENTITY,
    organisation_id bigint         NOT NULL,
    title           core.text_255  NOT NULL,
    description     core.text_1000,
    is_active       boolean        NOT NULL DEFAULT true,
    CONSTRAINT pk_questionnaire PRIMARY KEY (id),
    CONSTRAINT uq_questionnaire_organisation_id_title UNIQUE (organisation_id, title),
    CONSTRAINT fk_questionnaire_organisation_id FOREIGN KEY (organisation_id)
        REFERENCES org.organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_audit_columns('job.questionnaire');

COMMENT ON TABLE  job.questionnaire IS 'Reusable screening questionnaire owned by an employer. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN job.questionnaire.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.questionnaire.organisation_id IS '[class:internal] Owning employer.';
COMMENT ON COLUMN job.questionnaire.title IS '[class:internal] Name shown to the employer.';
COMMENT ON COLUMN job.questionnaire.description IS '[class:public] [null: no instructions] Instructions shown to candidates.';
COMMENT ON COLUMN job.questionnaire.is_active IS '[class:internal] Can be attached to new jobs. Default true.';

CREATE TABLE job.questionnaire_question (
    id               bigint GENERATED ALWAYS AS IDENTITY,
    questionnaire_id bigint            NOT NULL,
    sequence_no      core.positive_int NOT NULL,
    question_text    core.text_1000    NOT NULL,
    is_mandatory     boolean           NOT NULL DEFAULT true,
    CONSTRAINT pk_questionnaire_question PRIMARY KEY (id),
    CONSTRAINT uq_questionnaire_question_questionnaire_id_sequence_no UNIQUE (questionnaire_id, sequence_no),
    CONSTRAINT fk_questionnaire_question_questionnaire_id FOREIGN KEY (questionnaire_id)
        REFERENCES job.questionnaire (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('job.questionnaire_question', 'answer_type', 'ANSWER_TYPE');
SELECT core.add_audit_columns('job.questionnaire_question');

COMMENT ON TABLE  job.questionnaire_question IS 'Questions in a questionnaire, in display order. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN job.questionnaire_question.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.questionnaire_question.questionnaire_id IS '[class:internal] Questionnaire.';
COMMENT ON COLUMN job.questionnaire_question.sequence_no IS '[class:internal] Display order (1, 2, 3 ...).';
COMMENT ON COLUMN job.questionnaire_question.question_text IS '[class:public] Question as written by the employer.';
COMMENT ON COLUMN job.questionnaire_question.is_mandatory IS '[class:public] Must be answered to apply. Default true.';

CREATE TABLE job.question_option (
    id                        bigint GENERATED ALWAYS AS IDENTITY,
    questionnaire_question_id bigint            NOT NULL,
    sequence_no               core.positive_int NOT NULL,
    option_text               core.text_255     NOT NULL,
    is_knockout               boolean           NOT NULL DEFAULT false,
    CONSTRAINT pk_question_option PRIMARY KEY (id),
    CONSTRAINT uq_question_option_questionnaire_question_id_sequence_no UNIQUE (questionnaire_question_id, sequence_no),
    -- Target of the composite FK from application_answer: an option can only answer its own question.
    CONSTRAINT uq_question_option_id_questionnaire_question_id UNIQUE (id, questionnaire_question_id),
    CONSTRAINT fk_question_option_questionnaire_question_id FOREIGN KEY (questionnaire_question_id)
        REFERENCES job.questionnaire_question (id) ON UPDATE RESTRICT ON DELETE CASCADE
);
SELECT core.add_audit_columns('job.question_option');

COMMENT ON TABLE  job.question_option IS 'Choices for single- and multiple-choice questions. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN job.question_option.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.question_option.questionnaire_question_id IS '[class:internal] Question.';
COMMENT ON COLUMN job.question_option.sequence_no IS '[class:internal] Display order.';
COMMENT ON COLUMN job.question_option.option_text IS '[class:public] Choice text.';
COMMENT ON COLUMN job.question_option.is_knockout IS '[class:internal] Choosing it disqualifies the application automatically. Default false.';

CREATE TABLE job.job_requirement_questionnaire (
    id                 bigint GENERATED ALWAYS AS IDENTITY,
    job_requirement_id bigint NOT NULL,
    questionnaire_id   bigint NOT NULL,
    CONSTRAINT pk_job_requirement_questionnaire PRIMARY KEY (id),
    CONSTRAINT uq_job_requirement_questionnaire_job_requirement_id_questionnaire_id UNIQUE (job_requirement_id, questionnaire_id),
    CONSTRAINT fk_job_requirement_questionnaire_job_requirement_id FOREIGN KEY (job_requirement_id)
        REFERENCES job.job_requirement (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_job_requirement_questionnaire_questionnaire_id FOREIGN KEY (questionnaire_id)
        REFERENCES job.questionnaire (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_job_requirement_questionnaire_questionnaire_id ON job.job_requirement_questionnaire (questionnaire_id);
SELECT core.add_audit_columns('job.job_requirement_questionnaire');

COMMENT ON TABLE  job.job_requirement_questionnaire IS 'Questionnaires attached to a job. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN job.job_requirement_questionnaire.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.job_requirement_questionnaire.job_requirement_id IS '[class:internal] Job.';
COMMENT ON COLUMN job.job_requirement_questionnaire.questionnaire_id IS '[class:internal] Questionnaire candidates must answer.';

-- Referral (Profile module) can now point at a job.
ALTER TABLE prf.referral ADD CONSTRAINT fk_referral_job_requirement_id FOREIGN KEY (job_requirement_id)
    REFERENCES job.job_requirement (id) ON UPDATE RESTRICT ON DELETE RESTRICT;

GRANT SELECT, INSERT, UPDATE ON job.job_requirement, job.questionnaire TO talentra_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON job.job_position, job.job_requirement_skill, job.job_requirement_qualification,
    job.questionnaire_question, job.question_option, job.job_requirement_questionnaire TO talentra_app;

RESET ROLE;
