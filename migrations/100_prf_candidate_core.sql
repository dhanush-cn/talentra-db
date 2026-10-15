-- 100_prf_candidate_core.sql
-- Purpose : Profile module, part 1: the candidate and everything that describes them.
--             candidate_profile          one per candidate user
--             candidate_contact          encrypted email/phone, blind index, masked display
--             candidate_preferred_location
--             candidate_education
--             candidate_work_experience
--             candidate_skill
--             candidate_language
-- Owner   : Profile (whole team, Phase 1)
-- Key decisions:
--   * Contact details are never stored readable. Recruiters see the masked value until
--     they download the profile (a credit-charged, logged action in the Payments module).
--   * Salary uses a disclosure status, so "not disclosed" is never stored as 0 (Rule 5).
--   * source_system + source_record_id is the natural key from legacy systems (Rule 2).
--   * duplicate_of_candidate_profile_id records resolved duplicates instead of deleting them.

SET ROLE talentra_owner;
SET LOCAL app.user_id = '1';

SELECT mst.define_enumeration('GENDER', 'Gender', 'PRF', 'Self-described gender; optional.',
    ARRAY['FEMALE', 'MALE', 'NON_BINARY', 'PREFER_NOT_TO_SAY'],
    ARRAY['Female', 'Male', 'Non-binary', 'Prefer not to say']);

SELECT mst.define_enumeration('PROFILE_VISIBILITY', 'Profile visibility', 'PRF',
    'Who can find the profile in search.',
    ARRAY['PUBLIC', 'RECRUITERS_ONLY', 'HIDDEN'],
    ARRAY['Visible to everyone', 'Visible to verified recruiters only', 'Hidden from search']);

SELECT mst.define_enumeration('CONTACT_TYPE', 'Contact type', 'PRF', 'Kind of contact detail.',
    ARRAY['EMAIL', 'PHONE', 'WHATSAPP'], ARRAY['Email', 'Phone', 'WhatsApp']);

SELECT mst.define_enumeration('SALARY_PERIOD', 'Salary period', 'MST', 'Period a salary amount refers to.',
    ARRAY['ANNUAL', 'MONTHLY', 'DAILY', 'HOURLY'], ARRAY['Per year', 'Per month', 'Per day', 'Per hour']);

SELECT mst.define_enumeration('SCORE_SCALE', 'Score scale', 'PRF', 'Scale an education score is expressed in.',
    ARRAY['PERCENTAGE', 'CGPA_10', 'CGPA_4'], ARRAY['Percentage', 'CGPA out of 10', 'GPA out of 4']);

-- ===========================================================================
-- candidate_profile
-- ===========================================================================
CREATE TABLE prf.candidate_profile (
    id                                 bigint GENERATED ALWAYS AS IDENTITY,
    public_id                          uuid              NOT NULL DEFAULT gen_random_uuid(),
    user_account_id                    bigint            NOT NULL,
    full_name                          core.person_name  NOT NULL,
    preferred_name                     core.person_name,
    date_of_birth                      date,
    nationality_country_id             bigint,
    current_city_id                    bigint,
    headline                           core.text_255,
    summary                            core.text_4000,
    summary_language_id                bigint,
    is_fresher                         boolean           NOT NULL DEFAULT false,
    total_experience_months            core.non_negative_int,
    notice_period_days                 core.non_negative_int,
    is_open_to_work                    boolean           NOT NULL DEFAULT true,
    salary_currency_id                 bigint,
    current_salary_amount              core.money_amount,
    expected_salary_amount             core.money_amount,
    completion_percent                 core.percentage   NOT NULL DEFAULT 0,
    source_record_id                   core.text_100,
    duplicate_of_candidate_profile_id  bigint,
    last_active_at                     timestamptz,
    CONSTRAINT pk_candidate_profile PRIMARY KEY (id),
    CONSTRAINT uq_candidate_profile_public_id UNIQUE (public_id),
    CONSTRAINT uq_candidate_profile_user_account_id UNIQUE (user_account_id),
    CONSTRAINT ck_candidate_profile_date_of_birth CHECK (date_of_birth >= DATE '1900-01-01'),
    CONSTRAINT ck_candidate_profile_fresher_experience CHECK (NOT is_fresher OR coalesce(total_experience_months, 0) = 0),
    CONSTRAINT ck_candidate_profile_salary_non_negative CHECK (current_salary_amount >= 0 AND expected_salary_amount >= 0),
    CONSTRAINT ck_candidate_profile_salary_currency CHECK (
        (current_salary_amount IS NULL AND expected_salary_amount IS NULL) OR salary_currency_id IS NOT NULL),
    CONSTRAINT ck_candidate_profile_not_own_duplicate CHECK (duplicate_of_candidate_profile_id IS DISTINCT FROM id),
    CONSTRAINT fk_candidate_profile_user_account_id FOREIGN KEY (user_account_id)
        REFERENCES adm.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_profile_nationality_country_id FOREIGN KEY (nationality_country_id)
        REFERENCES mst.country (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_profile_current_city_id FOREIGN KEY (current_city_id)
        REFERENCES mst.city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_profile_summary_language_id FOREIGN KEY (summary_language_id)
        REFERENCES mst.language (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_profile_salary_currency_id FOREIGN KEY (salary_currency_id)
        REFERENCES mst.currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_profile_duplicate_of_candidate_profile_id FOREIGN KEY (duplicate_of_candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('prf.candidate_profile', 'gender', 'GENDER', true, 'candidate has not answered');
SELECT core.add_ref_code_column('prf.candidate_profile', 'profile_visibility', 'PROFILE_VISIBILITY');
SELECT core.add_ref_code_column('prf.candidate_profile', 'current_salary_disclosure', 'DISCLOSURE_STATUS');
SELECT core.add_ref_code_column('prf.candidate_profile', 'expected_salary_disclosure', 'DISCLOSURE_STATUS');
SELECT core.add_ref_code_column('prf.candidate_profile', 'source_system', 'SOURCE_SYSTEM');

-- Rule 5: an amount exists exactly when it is disclosed; "not disclosed" is never 0.
-- Legacy records keep their source id; directly registered candidates may have none.
DO $$
DECLARE
    v_disclosed bigint := mst.ref_code_id('DISCLOSURE_STATUS', 'DISCLOSED');
    v_direct    bigint := mst.ref_code_id('SOURCE_SYSTEM', 'DIRECT');
BEGIN
    EXECUTE format('ALTER TABLE prf.candidate_profile ADD CONSTRAINT ck_candidate_profile_current_salary_disclosed
        CHECK ((current_salary_amount IS NOT NULL) = (current_salary_disclosure_ref_code_id = %s))', v_disclosed);
    EXECUTE format('ALTER TABLE prf.candidate_profile ADD CONSTRAINT ck_candidate_profile_expected_salary_disclosed
        CHECK ((expected_salary_amount IS NOT NULL) = (expected_salary_disclosure_ref_code_id = %s))', v_disclosed);
    EXECUTE format('ALTER TABLE prf.candidate_profile ADD CONSTRAINT ck_candidate_profile_source_record_id
        CHECK (source_system_ref_code_id = %s OR source_record_id IS NOT NULL)', v_direct);
END $$;

ALTER TABLE prf.candidate_profile ADD CONSTRAINT uq_candidate_profile_source_system_ref_code_id_source_record_id
    UNIQUE (source_system_ref_code_id, source_record_id);

CREATE INDEX idx_candidate_profile_current_city_id ON prf.candidate_profile (current_city_id);
CREATE INDEX idx_candidate_profile_duplicate_of_candidate_profile_id ON prf.candidate_profile (duplicate_of_candidate_profile_id)
    WHERE duplicate_of_candidate_profile_id IS NOT NULL;
CREATE INDEX idx_candidate_profile_full_name_trgm ON prf.candidate_profile USING gin (full_name gin_trgm_ops);
SELECT core.add_audit_columns('prf.candidate_profile');
SELECT core.enable_soft_delete('prf.candidate_profile');

COMMENT ON TABLE  prf.candidate_profile IS 'One profile per candidate. [lifecycle:soft_delete] [retention: anonymised on erasure request; flagged for deletion after 3 years without sign-in] [owner:team]';
COMMENT ON COLUMN prf.candidate_profile.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_profile.public_id IS '[class:internal] Identifier used in URLs and APIs.';
COMMENT ON COLUMN prf.candidate_profile.user_account_id IS '[class:internal] Account that owns the profile (1:1).';
COMMENT ON COLUMN prf.candidate_profile.full_name IS '[class:personal] Name as the candidate writes it; any script, no assumed word order.';
COMMENT ON COLUMN prf.candidate_profile.preferred_name IS '[class:personal] [null: candidate uses full_name] Name to address the candidate by.';
COMMENT ON COLUMN prf.candidate_profile.date_of_birth IS '[class:personal] [null: not provided] Date of birth.';
COMMENT ON COLUMN prf.candidate_profile.nationality_country_id IS '[class:personal] [null: not provided] Nationality.';
COMMENT ON COLUMN prf.candidate_profile.current_city_id IS '[class:personal] [null: not provided] City the candidate lives in.';
COMMENT ON COLUMN prf.candidate_profile.headline IS '[class:public] [null: not written yet] One-line summary shown in search results.';
COMMENT ON COLUMN prf.candidate_profile.summary IS '[class:public] [null: not written yet] Profile summary, stored as entered.';
COMMENT ON COLUMN prf.candidate_profile.summary_language_id IS '[class:internal] [null: language not detected or no summary] Language of summary (Rule 7).';
COMMENT ON COLUMN prf.candidate_profile.is_fresher IS '[class:public] No prior work experience. Default false.';
COMMENT ON COLUMN prf.candidate_profile.total_experience_months IS '[class:public] [null: not stated] Total experience as stated by the candidate.';
COMMENT ON COLUMN prf.candidate_profile.notice_period_days IS '[class:public] [null: not stated] Notice period in days.';
COMMENT ON COLUMN prf.candidate_profile.is_open_to_work IS '[class:public] Actively looking. Default true.';
COMMENT ON COLUMN prf.candidate_profile.salary_currency_id IS '[class:personal] [null: no salary disclosed] Currency of both salary amounts.';
COMMENT ON COLUMN prf.candidate_profile.current_salary_amount IS '[class:personal] [null: not disclosed or not applicable; see current_salary_disclosure] Current annual salary.';
COMMENT ON COLUMN prf.candidate_profile.expected_salary_amount IS '[class:personal] [null: not disclosed or not applicable; see expected_salary_disclosure] Expected annual salary.';
COMMENT ON COLUMN prf.candidate_profile.completion_percent IS '[class:internal] Profile completion score 0–100, recomputed by prf.refresh_completion().';
COMMENT ON COLUMN prf.candidate_profile.source_record_id IS '[class:internal] [null: registered directly on the platform] Record id in the source system; natural key with source_system.';
COMMENT ON COLUMN prf.candidate_profile.duplicate_of_candidate_profile_id IS '[class:internal] [null: not identified as a duplicate] Surviving profile when this one was merged as a duplicate.';
COMMENT ON COLUMN prf.candidate_profile.last_active_at IS '[class:internal] [null: never active since registration] Last sign-in or profile activity (UTC); drives inactivity retention.';

-- ===========================================================================
-- candidate_contact
-- ===========================================================================
CREATE TABLE prf.candidate_contact (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id bigint        NOT NULL,
    value_encrypted      bytea         NOT NULL,
    value_hmac           bytea         NOT NULL,
    value_masked         core.text_100 NOT NULL,
    phone_country_id     bigint,
    is_primary           boolean       NOT NULL DEFAULT false,
    is_verified          boolean       NOT NULL DEFAULT false,
    verified_at          timestamptz,
    CONSTRAINT pk_candidate_contact PRIMARY KEY (id),
    CONSTRAINT ck_candidate_contact_verified_pair CHECK (is_verified = (verified_at IS NOT NULL)),
    CONSTRAINT fk_candidate_contact_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_contact_phone_country_id FOREIGN KEY (phone_country_id)
        REFERENCES mst.country (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('prf.candidate_contact', 'contact_type', 'CONTACT_TYPE');
DO $$
BEGIN
    EXECUTE format('ALTER TABLE prf.candidate_contact ADD CONSTRAINT ck_candidate_contact_phone_country
        CHECK ((phone_country_id IS NOT NULL) = (contact_type_ref_code_id <> %s))', mst.ref_code_id('CONTACT_TYPE', 'EMAIL'));
END $$;
ALTER TABLE prf.candidate_contact ADD CONSTRAINT uq_candidate_contact_candidate_profile_id_contact_type_value_hmac
    UNIQUE (candidate_profile_id, contact_type_ref_code_id, value_hmac);
CREATE UNIQUE INDEX uq_candidate_contact_one_primary_per_type
    ON prf.candidate_contact (candidate_profile_id, contact_type_ref_code_id) WHERE is_primary;
CREATE INDEX idx_candidate_contact_value_hmac ON prf.candidate_contact (value_hmac);
SELECT core.add_audit_columns('prf.candidate_contact');

COMMENT ON TABLE  prf.candidate_contact IS 'Candidate email and phone numbers, encrypted at rest. [lifecycle:hard_delete] [retention: deleted with the profile] [owner:team]';
COMMENT ON COLUMN prf.candidate_contact.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_contact.candidate_profile_id IS '[class:internal] Profile the contact belongs to.';
COMMENT ON COLUMN prf.candidate_contact.value_encrypted IS '[class:personal] Email (lowercase) or E.164 phone, encrypted with core.pii_encrypt.';
COMMENT ON COLUMN prf.candidate_contact.value_hmac IS '[class:personal] HMAC-SHA256 blind index of the normalised value; exact-match lookup and duplicate detection without decrypting.';
COMMENT ON COLUMN prf.candidate_contact.value_masked IS '[class:personal] Masked value shown before a profile download, e.g. pr***@gmail.com.';
COMMENT ON COLUMN prf.candidate_contact.phone_country_id IS '[class:personal] [null: contact is an email] Country of the phone number.';
COMMENT ON COLUMN prf.candidate_contact.is_primary IS '[class:internal] Primary contact of its type; at most one per type. Default false.';
COMMENT ON COLUMN prf.candidate_contact.is_verified IS '[class:internal] Ownership confirmed by OTP or link. Default false.';
COMMENT ON COLUMN prf.candidate_contact.verified_at IS '[class:internal] [null: not verified] When ownership was confirmed (UTC).';

-- ===========================================================================
-- candidate_preferred_location
-- ===========================================================================
CREATE TABLE prf.candidate_preferred_location (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id bigint NOT NULL,
    city_id              bigint NOT NULL,
    CONSTRAINT pk_candidate_preferred_location PRIMARY KEY (id),
    CONSTRAINT uq_candidate_preferred_location_candidate_profile_id_city_id UNIQUE (candidate_profile_id, city_id),
    CONSTRAINT fk_candidate_preferred_location_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_preferred_location_city_id FOREIGN KEY (city_id)
        REFERENCES mst.city (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_candidate_preferred_location_city_id ON prf.candidate_preferred_location (city_id, candidate_profile_id);
SELECT core.add_audit_columns('prf.candidate_preferred_location');

COMMENT ON TABLE  prf.candidate_preferred_location IS 'Cities a candidate is willing to work in. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN prf.candidate_preferred_location.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_preferred_location.candidate_profile_id IS '[class:internal] Candidate.';
COMMENT ON COLUMN prf.candidate_preferred_location.city_id IS '[class:public] Preferred city.';

-- ===========================================================================
-- candidate_education
-- ===========================================================================
CREATE TABLE prf.candidate_education (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id bigint        NOT NULL,
    qualification_id     bigint        NOT NULL,
    institution_id       bigint,
    institution_name     core.text_255,
    specialisation       core.text_255,
    start_date           date,
    end_date             date,
    is_ongoing           boolean       NOT NULL DEFAULT false,
    score_value          numeric(6, 2),
    CONSTRAINT pk_candidate_education PRIMARY KEY (id),
    CONSTRAINT ck_candidate_education_institution CHECK (institution_id IS NOT NULL OR institution_name IS NOT NULL),
    CONSTRAINT ck_candidate_education_dates CHECK (end_date >= start_date),
    CONSTRAINT ck_candidate_education_ongoing CHECK (NOT (is_ongoing AND end_date IS NOT NULL)),
    CONSTRAINT fk_candidate_education_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_education_qualification_id FOREIGN KEY (qualification_id)
        REFERENCES mst.qualification (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_education_institution_id FOREIGN KEY (institution_id)
        REFERENCES mst.institution (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('prf.candidate_education', 'score_scale', 'SCORE_SCALE', true, 'score not disclosed');
DO $$
BEGIN
    EXECUTE format('ALTER TABLE prf.candidate_education ADD CONSTRAINT ck_candidate_education_score
        CHECK ((score_value IS NULL) = (score_scale_ref_code_id IS NULL)
               AND score_value >= 0
               AND score_value <= CASE score_scale_ref_code_id WHEN %s THEN 100 WHEN %s THEN 10 WHEN %s THEN 4 END)',
        mst.ref_code_id('SCORE_SCALE', 'PERCENTAGE'), mst.ref_code_id('SCORE_SCALE', 'CGPA_10'),
        mst.ref_code_id('SCORE_SCALE', 'CGPA_4'));
END $$;
CREATE INDEX idx_candidate_education_candidate_profile_id ON prf.candidate_education (candidate_profile_id);
CREATE INDEX idx_candidate_education_qualification_id ON prf.candidate_education (qualification_id);
CREATE INDEX idx_candidate_education_institution_id ON prf.candidate_education (institution_id);
SELECT core.add_audit_columns('prf.candidate_education');

COMMENT ON TABLE  prf.candidate_education IS 'Degrees, diplomas and certificates held or in progress. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN prf.candidate_education.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_education.candidate_profile_id IS '[class:internal] Candidate.';
COMMENT ON COLUMN prf.candidate_education.qualification_id IS '[class:public] Qualification from the catalogue.';
COMMENT ON COLUMN prf.candidate_education.institution_id IS '[class:public] [null: institution not in the catalogue; see institution_name] Institution.';
COMMENT ON COLUMN prf.candidate_education.institution_name IS '[class:public] [null: institution chosen from the catalogue] Institution name as typed.';
COMMENT ON COLUMN prf.candidate_education.specialisation IS '[class:public] [null: not applicable or not stated] Branch or major, e.g. Information Science.';
COMMENT ON COLUMN prf.candidate_education.start_date IS '[class:public] [null: not stated] Start date.';
COMMENT ON COLUMN prf.candidate_education.end_date IS '[class:public] [null: ongoing or not stated; see is_ongoing] Completion date.';
COMMENT ON COLUMN prf.candidate_education.is_ongoing IS '[class:public] Still studying. Default false.';
COMMENT ON COLUMN prf.candidate_education.score_value IS '[class:personal] [null: not disclosed] Score on score_scale (percentage 0–100, CGPA 0–10 or GPA 0–4).';

-- ===========================================================================
-- candidate_work_experience
-- ===========================================================================
CREATE TABLE prf.candidate_work_experience (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id bigint         NOT NULL,
    employer_name        core.text_255  NOT NULL,
    organisation_id      bigint,
    designation          core.text_255  NOT NULL,
    job_role_id          bigint,
    city_id              bigint,
    start_date           date           NOT NULL,
    end_date             date,
    is_current           boolean        NOT NULL DEFAULT false,
    description          core.text_4000,
    CONSTRAINT pk_candidate_work_experience PRIMARY KEY (id),
    CONSTRAINT ck_candidate_work_experience_dates CHECK (end_date >= start_date),
    CONSTRAINT ck_candidate_work_experience_current CHECK (is_current = (end_date IS NULL)),
    CONSTRAINT fk_candidate_work_experience_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_work_experience_organisation_id FOREIGN KEY (organisation_id)
        REFERENCES org.organisation (id) ON UPDATE RESTRICT ON DELETE SET NULL,
    CONSTRAINT fk_candidate_work_experience_job_role_id FOREIGN KEY (job_role_id)
        REFERENCES mst.job_role (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_work_experience_city_id FOREIGN KEY (city_id)
        REFERENCES mst.city (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('prf.candidate_work_experience', 'employment_type', 'EMPLOYMENT_TYPE', true, 'not stated by the candidate');
CREATE INDEX idx_candidate_work_experience_candidate_profile_id ON prf.candidate_work_experience (candidate_profile_id);
CREATE INDEX idx_candidate_work_experience_organisation_id ON prf.candidate_work_experience (organisation_id);
CREATE INDEX idx_candidate_work_experience_job_role_id ON prf.candidate_work_experience (job_role_id);
CREATE INDEX idx_candidate_work_experience_city_id ON prf.candidate_work_experience (city_id);
SELECT core.add_audit_columns('prf.candidate_work_experience');

COMMENT ON TABLE  prf.candidate_work_experience IS 'Employment history. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN prf.candidate_work_experience.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_work_experience.candidate_profile_id IS '[class:internal] Candidate.';
COMMENT ON COLUMN prf.candidate_work_experience.employer_name IS '[class:public] Employer name as entered.';
COMMENT ON COLUMN prf.candidate_work_experience.organisation_id IS '[class:internal] [null: employer is not an organisation on the platform; set to null if that organisation is removed] Matched employer.';
COMMENT ON COLUMN prf.candidate_work_experience.designation IS '[class:public] Job title as entered.';
COMMENT ON COLUMN prf.candidate_work_experience.job_role_id IS '[class:public] [null: title not mapped to a standard role yet] Standard role.';
COMMENT ON COLUMN prf.candidate_work_experience.city_id IS '[class:public] [null: remote or not stated] Work location.';
COMMENT ON COLUMN prf.candidate_work_experience.start_date IS '[class:public] Start date.';
COMMENT ON COLUMN prf.candidate_work_experience.end_date IS '[class:public] [null: current job; see is_current] End date.';
COMMENT ON COLUMN prf.candidate_work_experience.is_current IS '[class:public] Current job. Default false.';
COMMENT ON COLUMN prf.candidate_work_experience.description IS '[class:public] [null: not written] Responsibilities and achievements.';

-- ===========================================================================
-- candidate_skill
-- ===========================================================================
CREATE TABLE prf.candidate_skill (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id bigint        NOT NULL,
    skill_id             bigint        NOT NULL,
    years_of_experience  numeric(4, 1),
    last_used_year       smallint,
    is_primary           boolean       NOT NULL DEFAULT false,
    CONSTRAINT pk_candidate_skill PRIMARY KEY (id),
    CONSTRAINT uq_candidate_skill_candidate_profile_id_skill_id UNIQUE (candidate_profile_id, skill_id),
    CONSTRAINT ck_candidate_skill_years CHECK (years_of_experience BETWEEN 0 AND 60),
    CONSTRAINT ck_candidate_skill_last_used_year CHECK (last_used_year BETWEEN 1960 AND 2100),
    CONSTRAINT fk_candidate_skill_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_skill_skill_id FOREIGN KEY (skill_id)
        REFERENCES mst.skill (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('prf.candidate_skill', 'proficiency', 'PROFICIENCY_LEVEL', true, 'not self-assessed yet');
-- Recruiter search starts from a skill and finds candidates: (skill_id, candidate_profile_id).
CREATE INDEX idx_candidate_skill_skill_id ON prf.candidate_skill (skill_id, candidate_profile_id);
SELECT core.add_audit_columns('prf.candidate_skill');

COMMENT ON TABLE  prf.candidate_skill IS 'Skills a candidate claims. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN prf.candidate_skill.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_skill.candidate_profile_id IS '[class:internal] Candidate.';
COMMENT ON COLUMN prf.candidate_skill.skill_id IS '[class:public] Skill from the catalogue.';
COMMENT ON COLUMN prf.candidate_skill.years_of_experience IS '[class:public] [null: not stated] Years using the skill (0–60).';
COMMENT ON COLUMN prf.candidate_skill.last_used_year IS '[class:public] [null: not stated or still in use] Last year the skill was used.';
COMMENT ON COLUMN prf.candidate_skill.is_primary IS '[class:public] Highlighted on the profile. Default false.';

-- ===========================================================================
-- candidate_language
-- ===========================================================================
CREATE TABLE prf.candidate_language (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id bigint  NOT NULL,
    language_id          bigint  NOT NULL,
    can_read             boolean NOT NULL DEFAULT true,
    can_write            boolean NOT NULL DEFAULT true,
    can_speak            boolean NOT NULL DEFAULT true,
    CONSTRAINT pk_candidate_language PRIMARY KEY (id),
    CONSTRAINT uq_candidate_language_candidate_profile_id_language_id UNIQUE (candidate_profile_id, language_id),
    CONSTRAINT ck_candidate_language_some_ability CHECK (can_read OR can_write OR can_speak),
    CONSTRAINT fk_candidate_language_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_language_language_id FOREIGN KEY (language_id)
        REFERENCES mst.language (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('prf.candidate_language', 'proficiency', 'PROFICIENCY_LEVEL');
CREATE INDEX idx_candidate_language_language_id ON prf.candidate_language (language_id);
SELECT core.add_audit_columns('prf.candidate_language');

COMMENT ON TABLE  prf.candidate_language IS 'Languages a candidate knows. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN prf.candidate_language.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_language.candidate_profile_id IS '[class:internal] Candidate.';
COMMENT ON COLUMN prf.candidate_language.language_id IS '[class:public] Language.';
COMMENT ON COLUMN prf.candidate_language.can_read IS '[class:public] Can read. Default true.';
COMMENT ON COLUMN prf.candidate_language.can_write IS '[class:public] Can write. Default true.';
COMMENT ON COLUMN prf.candidate_language.can_speak IS '[class:public] Can speak. Default true.';

GRANT SELECT, INSERT, UPDATE ON prf.candidate_profile TO talentra_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON prf.candidate_contact, prf.candidate_preferred_location,
    prf.candidate_education, prf.candidate_work_experience, prf.candidate_skill, prf.candidate_language
    TO talentra_app;

RESET ROLE;
