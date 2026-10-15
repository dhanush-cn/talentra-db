-- 110_prf_resume_projects_assessments.sql
-- Purpose : Profile module, part 2:
--             resume_template, candidate_resume (versioned)
--             candidate_project (profile and gig projects: role, duration, outcome)
--             assessment, candidate_assessment_result (append-only scores)
--             course, candidate_course_enrolment
--             profile_completion_rule + prf.refresh_completion()
-- Owner   : Profile (whole team, Phase 1)

SET ROLE talentra_owner;
SET LOCAL app.user_id = '1';

SELECT mst.define_enumeration('PROJECT_KIND', 'Project kind', 'PRF', 'Context a profile project was done in.',
    ARRAY['ACADEMIC', 'PERSONAL', 'PROFESSIONAL', 'GIG'],
    ARRAY['Academic', 'Personal', 'Professional', 'Gig']);
SELECT mst.define_enumeration('ASSESSMENT_TYPE', 'Assessment type', 'PRF', 'Who sets and scores an assessment.',
    ARRAY['SELF', 'PLATFORM_TEST', 'EMPLOYER_TEST'],
    ARRAY['Self-assessment', 'Platform test', 'Employer test']);
SELECT mst.define_enumeration('ASSESSMENT_RESULT', 'Assessment result', 'PRF', 'Outcome of one assessment attempt.',
    ARRAY['PASSED', 'FAILED', 'INCOMPLETE'], ARRAY['Passed', 'Failed', 'Incomplete']);
SELECT mst.define_enumeration('ENROLMENT_STATUS', 'Enrolment status', 'PRF', 'Progress in a course.',
    ARRAY['ENROLLED', 'IN_PROGRESS', 'COMPLETED', 'DROPPED'],
    ARRAY['Enrolled', 'In progress', 'Completed', 'Dropped']);
SELECT mst.define_enumeration('PROFILE_SECTION', 'Profile section', 'PRF', 'Sections scored for profile completion.',
    ARRAY['BASIC_DETAILS', 'CONTACT', 'HEADLINE_SUMMARY', 'EDUCATION', 'WORK_EXPERIENCE', 'SKILLS',
          'LANGUAGES', 'RESUME', 'PROJECTS', 'PREFERRED_LOCATION'],
    ARRAY['Basic details', 'Verified contact', 'Headline and summary', 'Education', 'Work experience', 'Skills',
          'Languages', 'Resume', 'Projects', 'Preferred locations']);

-- ===========================================================================
-- resume_template
-- ===========================================================================
CREATE TABLE prf.resume_template (
    id           bigint GENERATED ALWAYS AS IDENTITY,
    template_code core.code     NOT NULL,
    english_name core.text_100  NOT NULL,
    description  core.text_1000,
    is_active    boolean        NOT NULL DEFAULT true,
    CONSTRAINT pk_resume_template PRIMARY KEY (id),
    CONSTRAINT uq_resume_template_template_code UNIQUE (template_code)
);
SELECT core.add_audit_columns('prf.resume_template');

COMMENT ON TABLE  prf.resume_template IS 'Layouts the resume builder can render. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN prf.resume_template.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN prf.resume_template.template_code IS '[class:public] Stable code used by the renderer.';
COMMENT ON COLUMN prf.resume_template.english_name IS '[class:public] Name shown in the template picker.';
COMMENT ON COLUMN prf.resume_template.description IS '[class:public] [null: no description written] Who the template suits.';
COMMENT ON COLUMN prf.resume_template.is_active IS '[class:public] Offered for new resumes. Default true.';

INSERT INTO prf.resume_template (template_code, english_name, description) VALUES
    ('CLASSIC', 'Classic', 'Single column, suits most roles.'),
    ('MODERN_TECH', 'Modern technical', 'Skills-first layout for technical roles.'),
    ('FRESHER', 'Fresher', 'Education and projects first, for campus and fresher hiring.');

-- ===========================================================================
-- candidate_resume (versioned: a new version is a new row; old versions are kept)
-- ===========================================================================
CREATE TABLE prf.candidate_resume (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id bigint           NOT NULL,
    version_number       core.positive_int NOT NULL,
    title                core.text_255    NOT NULL,
    resume_template_id   bigint,
    body                 core.long_text,
    content_language_id  bigint,
    file_storage_key     core.text_1000,
    file_sha256          bytea,
    file_mime_type       core.text_100,
    file_size_bytes      bigint,
    is_default           boolean          NOT NULL DEFAULT false,
    CONSTRAINT pk_candidate_resume PRIMARY KEY (id),
    CONSTRAINT uq_candidate_resume_candidate_profile_id_version_number UNIQUE (candidate_profile_id, version_number),
    CONSTRAINT ck_candidate_resume_has_content CHECK (body IS NOT NULL OR file_storage_key IS NOT NULL),
    CONSTRAINT ck_candidate_resume_file_fields CHECK (
        (file_storage_key IS NULL) = (file_sha256 IS NULL)
        AND (file_storage_key IS NULL) = (file_mime_type IS NULL)
        AND (file_storage_key IS NULL) = (file_size_bytes IS NULL)),
    CONSTRAINT ck_candidate_resume_file_size CHECK (file_size_bytes BETWEEN 1 AND 10485760),
    CONSTRAINT ck_candidate_resume_sha256_length CHECK (length(file_sha256) = 32),
    CONSTRAINT fk_candidate_resume_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_resume_resume_template_id FOREIGN KEY (resume_template_id)
        REFERENCES prf.resume_template (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_resume_content_language_id FOREIGN KEY (content_language_id)
        REFERENCES mst.language (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_audit_columns('prf.candidate_resume');
SELECT core.enable_soft_delete('prf.candidate_resume');
CREATE UNIQUE INDEX uq_candidate_resume_one_default ON prf.candidate_resume (candidate_profile_id)
    WHERE is_default AND deleted_at IS NULL;

COMMENT ON TABLE  prf.candidate_resume IS 'Resume versions, built in the platform or uploaded. [lifecycle:soft_delete] [retention: deleted with the profile] [owner:team]';
COMMENT ON COLUMN prf.candidate_resume.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_resume.candidate_profile_id IS '[class:internal] Candidate.';
COMMENT ON COLUMN prf.candidate_resume.version_number IS '[class:internal] 1, 2, 3 ... per candidate; never reused.';
COMMENT ON COLUMN prf.candidate_resume.title IS '[class:personal] Candidate''s label for the version, e.g. Backend roles.';
COMMENT ON COLUMN prf.candidate_resume.resume_template_id IS '[class:internal] [null: uploaded file, not generated from a template] Template used.';
COMMENT ON COLUMN prf.candidate_resume.body IS '[class:personal] [null: uploaded file only] [unbounded: full resume text authored in the builder; size limited by the application to 64 KB] Resume content as entered.';
COMMENT ON COLUMN prf.candidate_resume.content_language_id IS '[class:internal] [null: language not detected] Language of the resume (Rule 7).';
COMMENT ON COLUMN prf.candidate_resume.file_storage_key IS '[class:personal] [null: built in the platform, no file] Object-storage key of the uploaded file.';
COMMENT ON COLUMN prf.candidate_resume.file_sha256 IS '[class:internal] [null: no file] SHA-256 of the file; detects duplicate uploads.';
COMMENT ON COLUMN prf.candidate_resume.file_mime_type IS '[class:internal] [null: no file] MIME type of the file.';
COMMENT ON COLUMN prf.candidate_resume.file_size_bytes IS '[class:internal] [null: no file] File size, 1 byte to 10 MB.';
COMMENT ON COLUMN prf.candidate_resume.is_default IS '[class:internal] Sent with applications by default; at most one live default per candidate. Default false.';

-- ===========================================================================
-- candidate_project
-- ===========================================================================
CREATE TABLE prf.candidate_project (
    id                           bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id         bigint         NOT NULL,
    title                        core.text_255  NOT NULL,
    role_description             core.text_255  NOT NULL,
    start_date                   date           NOT NULL,
    end_date                     date,
    outcome                      core.text_1000,
    project_url                  core.text_1000,
    candidate_work_experience_id bigint,
    CONSTRAINT pk_candidate_project PRIMARY KEY (id),
    CONSTRAINT ck_candidate_project_dates CHECK (end_date >= start_date),
    CONSTRAINT ck_candidate_project_url CHECK (project_url ~ '^https?://'),
    CONSTRAINT fk_candidate_project_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_project_candidate_work_experience_id FOREIGN KEY (candidate_work_experience_id)
        REFERENCES prf.candidate_work_experience (id) ON UPDATE RESTRICT ON DELETE SET NULL
);
SELECT core.add_ref_code_column('prf.candidate_project', 'project_kind', 'PROJECT_KIND');
CREATE INDEX idx_candidate_project_candidate_profile_id ON prf.candidate_project (candidate_profile_id);
CREATE INDEX idx_candidate_project_candidate_work_experience_id ON prf.candidate_project (candidate_work_experience_id);
SELECT core.add_audit_columns('prf.candidate_project');

COMMENT ON TABLE  prf.candidate_project IS 'Projects on a profile, including gig projects (the Gig module links completed assignments here). [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN prf.candidate_project.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_project.candidate_profile_id IS '[class:internal] Candidate.';
COMMENT ON COLUMN prf.candidate_project.title IS '[class:public] Project name.';
COMMENT ON COLUMN prf.candidate_project.role_description IS '[class:public] Candidate''s role on the project.';
COMMENT ON COLUMN prf.candidate_project.start_date IS '[class:public] Start date.';
COMMENT ON COLUMN prf.candidate_project.end_date IS '[class:public] [null: project ongoing] End date; duration = end - start.';
COMMENT ON COLUMN prf.candidate_project.outcome IS '[class:public] [null: not written] What the project achieved.';
COMMENT ON COLUMN prf.candidate_project.project_url IS '[class:public] [null: no public link] Link to the project.';
COMMENT ON COLUMN prf.candidate_project.candidate_work_experience_id IS '[class:internal] [null: not done for an employer on the profile; set to null if that experience is removed] Job the project was done in.';

-- ===========================================================================
-- assessment and candidate_assessment_result
-- ===========================================================================
CREATE TABLE prf.assessment (
    id              bigint GENERATED ALWAYS AS IDENTITY,
    title           core.text_255  NOT NULL,
    description     core.text_1000,
    skill_id        bigint,
    organisation_id bigint,
    max_score       numeric(7, 2)  NOT NULL,
    pass_score      numeric(7, 2),
    is_active       boolean        NOT NULL DEFAULT true,
    CONSTRAINT pk_assessment PRIMARY KEY (id),
    CONSTRAINT ck_assessment_scores CHECK (max_score > 0 AND pass_score BETWEEN 0 AND max_score),
    CONSTRAINT fk_assessment_skill_id FOREIGN KEY (skill_id)
        REFERENCES mst.skill (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_assessment_organisation_id FOREIGN KEY (organisation_id)
        REFERENCES org.organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('prf.assessment', 'assessment_type', 'ASSESSMENT_TYPE');
DO $$
BEGIN
    EXECUTE format('ALTER TABLE prf.assessment ADD CONSTRAINT ck_assessment_employer_owner
        CHECK ((organisation_id IS NOT NULL) = (assessment_type_ref_code_id = %s))',
        mst.ref_code_id('ASSESSMENT_TYPE', 'EMPLOYER_TEST'));
END $$;
CREATE INDEX idx_assessment_skill_id ON prf.assessment (skill_id);
CREATE INDEX idx_assessment_organisation_id ON prf.assessment (organisation_id);
SELECT core.add_audit_columns('prf.assessment');

COMMENT ON TABLE  prf.assessment IS 'Self-assessments, platform tests and employer tests. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN prf.assessment.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN prf.assessment.title IS '[class:public] Assessment name.';
COMMENT ON COLUMN prf.assessment.description IS '[class:public] [null: no description written] What it measures.';
COMMENT ON COLUMN prf.assessment.skill_id IS '[class:public] [null: general aptitude, not tied to one skill] Skill assessed.';
COMMENT ON COLUMN prf.assessment.organisation_id IS '[class:internal] [null: not an employer test] Employer that owns the test.';
COMMENT ON COLUMN prf.assessment.max_score IS '[class:public] Highest possible score (> 0).';
COMMENT ON COLUMN prf.assessment.pass_score IS '[class:public] [null: no pass mark, e.g. self-assessment] Minimum passing score.';
COMMENT ON COLUMN prf.assessment.is_active IS '[class:public] Available to take. Default true.';

CREATE TABLE prf.candidate_assessment_result (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id bigint          NOT NULL,
    assessment_id        bigint          NOT NULL,
    score_value          numeric(7, 2)   NOT NULL,
    score_percent        core.percentage NOT NULL,
    attempted_at         timestamptz     NOT NULL,
    duration_seconds     core.positive_int,
    CONSTRAINT pk_candidate_assessment_result PRIMARY KEY (id),
    CONSTRAINT ck_candidate_assessment_result_score CHECK (score_value >= 0),
    CONSTRAINT fk_candidate_assessment_result_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_assessment_result_assessment_id FOREIGN KEY (assessment_id)
        REFERENCES prf.assessment (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('prf.candidate_assessment_result', 'assessment_result', 'ASSESSMENT_RESULT');
CREATE INDEX idx_candidate_assessment_result_candidate_profile_id
    ON prf.candidate_assessment_result (candidate_profile_id, attempted_at DESC);
CREATE INDEX idx_candidate_assessment_result_assessment_id ON prf.candidate_assessment_result (assessment_id);
SELECT core.add_creation_columns('prf.candidate_assessment_result');
COMMENT ON TABLE  prf.candidate_assessment_result IS 'Every assessment attempt and its score. Retakes are new rows. [retention: anonymised with the profile] [owner:team]';
SELECT core.make_append_only('prf.candidate_assessment_result');

COMMENT ON COLUMN prf.candidate_assessment_result.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_assessment_result.candidate_profile_id IS '[class:internal] Candidate.';
COMMENT ON COLUMN prf.candidate_assessment_result.assessment_id IS '[class:internal] Assessment taken.';
COMMENT ON COLUMN prf.candidate_assessment_result.score_value IS '[class:personal] Raw score.';
COMMENT ON COLUMN prf.candidate_assessment_result.score_percent IS '[class:personal] Score as a percentage of max_score.';
COMMENT ON COLUMN prf.candidate_assessment_result.attempted_at IS '[class:internal] When the attempt was made (UTC).';
COMMENT ON COLUMN prf.candidate_assessment_result.duration_seconds IS '[class:internal] [null: not timed, e.g. self-assessment] Time taken.';

-- ===========================================================================
-- course and candidate_course_enrolment
-- ===========================================================================
CREATE TABLE prf.course (
    id             bigint GENERATED ALWAYS AS IDENTITY,
    title          core.text_255  NOT NULL,
    provider_name  core.text_255  NOT NULL,
    course_url     core.text_1000,
    skill_id       bigint,
    duration_hours core.positive_int,
    is_active      boolean        NOT NULL DEFAULT true,
    CONSTRAINT pk_course PRIMARY KEY (id),
    CONSTRAINT uq_course_provider_name_title UNIQUE (provider_name, title),
    CONSTRAINT ck_course_url CHECK (course_url ~ '^https?://'),
    CONSTRAINT fk_course_skill_id FOREIGN KEY (skill_id)
        REFERENCES mst.skill (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_course_skill_id ON prf.course (skill_id);
SELECT core.add_audit_columns('prf.course');

COMMENT ON TABLE  prf.course IS 'Courses candidates can enrol in or list. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN prf.course.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN prf.course.title IS '[class:public] Course name.';
COMMENT ON COLUMN prf.course.provider_name IS '[class:public] Who runs the course.';
COMMENT ON COLUMN prf.course.course_url IS '[class:public] [null: offline course] Course page.';
COMMENT ON COLUMN prf.course.skill_id IS '[class:public] [null: covers several skills] Main skill taught.';
COMMENT ON COLUMN prf.course.duration_hours IS '[class:public] [null: self-paced, no stated duration] Expected hours.';
COMMENT ON COLUMN prf.course.is_active IS '[class:public] Open for enrolment. Default true.';

CREATE TABLE prf.candidate_course_enrolment (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id bigint         NOT NULL,
    course_id            bigint         NOT NULL,
    enrolled_at          timestamptz    NOT NULL,
    completed_at         timestamptz,
    certificate_url      core.text_1000,
    CONSTRAINT pk_candidate_course_enrolment PRIMARY KEY (id),
    CONSTRAINT uq_candidate_course_enrolment_candidate_profile_id_course_id UNIQUE (candidate_profile_id, course_id),
    CONSTRAINT ck_candidate_course_enrolment_dates CHECK (completed_at >= enrolled_at),
    CONSTRAINT ck_candidate_course_enrolment_certificate CHECK (certificate_url IS NULL OR completed_at IS NOT NULL),
    CONSTRAINT fk_candidate_course_enrolment_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_course_enrolment_course_id FOREIGN KEY (course_id)
        REFERENCES prf.course (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('prf.candidate_course_enrolment', 'enrolment_status', 'ENROLMENT_STATUS');
DO $$
BEGIN
    EXECUTE format('ALTER TABLE prf.candidate_course_enrolment ADD CONSTRAINT ck_candidate_course_enrolment_completed
        CHECK ((completed_at IS NOT NULL) = (enrolment_status_ref_code_id = %s))',
        mst.ref_code_id('ENROLMENT_STATUS', 'COMPLETED'));
END $$;
CREATE INDEX idx_candidate_course_enrolment_course_id ON prf.candidate_course_enrolment (course_id);
SELECT core.add_audit_columns('prf.candidate_course_enrolment');

COMMENT ON TABLE  prf.candidate_course_enrolment IS 'Courses a candidate has enrolled in. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN prf.candidate_course_enrolment.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_course_enrolment.candidate_profile_id IS '[class:internal] Candidate.';
COMMENT ON COLUMN prf.candidate_course_enrolment.course_id IS '[class:public] Course.';
COMMENT ON COLUMN prf.candidate_course_enrolment.enrolled_at IS '[class:internal] Enrolment time (UTC).';
COMMENT ON COLUMN prf.candidate_course_enrolment.completed_at IS '[class:public] [null: not completed] Completion time (UTC).';
COMMENT ON COLUMN prf.candidate_course_enrolment.certificate_url IS '[class:public] [null: no certificate issued] Certificate link.';

-- ===========================================================================
-- Profile completion scoring
-- ===========================================================================
CREATE TABLE prf.profile_completion_rule (
    id             bigint GENERATED ALWAYS AS IDENTITY,
    weight_percent core.percentage NOT NULL,
    is_active      boolean         NOT NULL DEFAULT true,
    CONSTRAINT pk_profile_completion_rule PRIMARY KEY (id)
);
SELECT core.add_ref_code_column('prf.profile_completion_rule', 'profile_section', 'PROFILE_SECTION');
ALTER TABLE prf.profile_completion_rule ADD CONSTRAINT uq_profile_completion_rule_profile_section_ref_code_id
    UNIQUE (profile_section_ref_code_id);
SELECT core.add_audit_columns('prf.profile_completion_rule');

COMMENT ON TABLE  prf.profile_completion_rule IS 'Weight of each profile section in the completion score; active weights total 100. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN prf.profile_completion_rule.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.profile_completion_rule.weight_percent IS '[class:internal] Contribution of the section to the score.';
COMMENT ON COLUMN prf.profile_completion_rule.is_active IS '[class:internal] Counted in the score. Default true.';

INSERT INTO prf.profile_completion_rule (profile_section_ref_code_id, weight_percent)
SELECT mst.ref_code_id('PROFILE_SECTION', v.section), v.weight
FROM (VALUES ('BASIC_DETAILS', 10), ('CONTACT', 10), ('HEADLINE_SUMMARY', 10), ('EDUCATION', 15),
             ('WORK_EXPERIENCE', 15), ('SKILLS', 15), ('LANGUAGES', 5), ('RESUME', 10),
             ('PROJECTS', 5), ('PREFERRED_LOCATION', 5)) AS v(section, weight);

-- Recomputes and stores the completion score for one candidate; returns the new score.
-- Called by the application after profile edits and by the nightly refresh job.
CREATE FUNCTION prf.refresh_completion(p_candidate_profile_id bigint)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_score numeric;
BEGIN
    SELECT coalesce(sum(r.weight_percent), 0) INTO v_score
    FROM prf.profile_completion_rule r
    JOIN mst.ref_code s ON s.id = r.profile_section_ref_code_id
    JOIN prf.candidate_profile p ON p.id = p_candidate_profile_id
    WHERE r.is_active
      AND CASE s.code
            WHEN 'BASIC_DETAILS'      THEN p.current_city_id IS NOT NULL AND p.date_of_birth IS NOT NULL
            WHEN 'CONTACT'            THEN EXISTS (SELECT 1 FROM prf.candidate_contact c WHERE c.candidate_profile_id = p.id AND c.is_verified)
            WHEN 'HEADLINE_SUMMARY'   THEN p.headline IS NOT NULL AND p.summary IS NOT NULL
            WHEN 'EDUCATION'          THEN EXISTS (SELECT 1 FROM prf.candidate_education e WHERE e.candidate_profile_id = p.id)
            WHEN 'WORK_EXPERIENCE'    THEN p.is_fresher OR EXISTS (SELECT 1 FROM prf.candidate_work_experience w WHERE w.candidate_profile_id = p.id)
            WHEN 'SKILLS'             THEN (SELECT count(*) FROM prf.candidate_skill k WHERE k.candidate_profile_id = p.id) >= 3
            WHEN 'LANGUAGES'          THEN EXISTS (SELECT 1 FROM prf.candidate_language l WHERE l.candidate_profile_id = p.id)
            WHEN 'RESUME'             THEN EXISTS (SELECT 1 FROM prf.candidate_resume v WHERE v.candidate_profile_id = p.id AND v.deleted_at IS NULL)
            WHEN 'PROJECTS'           THEN EXISTS (SELECT 1 FROM prf.candidate_project j WHERE j.candidate_profile_id = p.id)
            WHEN 'PREFERRED_LOCATION' THEN EXISTS (SELECT 1 FROM prf.candidate_preferred_location x WHERE x.candidate_profile_id = p.id)
            ELSE false
          END;

    UPDATE prf.candidate_profile SET completion_percent = least(v_score, 100) WHERE id = p_candidate_profile_id;
    RETURN least(v_score, 100);
END $$;
COMMENT ON FUNCTION prf.refresh_completion(bigint) IS
    'Recomputes candidate_profile.completion_percent from the active profile_completion_rule weights.';

GRANT SELECT ON prf.resume_template, prf.assessment, prf.course, prf.profile_completion_rule TO talentra_app;
GRANT SELECT, INSERT, UPDATE ON prf.candidate_resume TO talentra_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON prf.candidate_project, prf.candidate_course_enrolment TO talentra_app;

RESET ROLE;
