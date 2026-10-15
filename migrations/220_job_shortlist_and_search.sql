-- 220_job_shortlist_and_search.sql
-- Purpose : Jobs and Applications, part 3:
--             job_shortlist_entry  candidates shortlisted for a specific job, applied or not
--                                  (the Sourcing module adds sourced candidates here)
--             job_shortlist_event  shortlist history, written by trigger (append-only)
--             job_search_event     candidate job-search history (monthly partitions, append-only)
-- Owner   : Jobs and Applications (whole team, Phase 1)

SET ROLE talentra_owner;
SET LOCAL app.user_id = '1';

SELECT mst.define_enumeration('SHORTLIST_SOURCE', 'Shortlist source', 'JOB', 'How a candidate reached a job shortlist.',
    ARRAY['APPLICATION', 'SEARCH', 'SOURCING_REQUEST', 'CONSULTANT', 'REFERRAL', 'BOOKMARK'],
    ARRAY['From an application', 'From candidate search', 'From a sourcing request', 'Submitted by a consultant', 'Referral', 'From saved candidates']);

-- ===========================================================================
-- job_shortlist_entry
-- ===========================================================================
CREATE TABLE job.job_shortlist_entry (
    id                             bigint GENERATED ALWAYS AS IDENTITY,
    job_requirement_id             bigint         NOT NULL,
    candidate_profile_id           bigint         NOT NULL,
    shortlisted_by_user_account_id bigint         NOT NULL,
    application_id                 bigint,
    note                           core.text_1000,
    CONSTRAINT pk_job_shortlist_entry PRIMARY KEY (id),
    CONSTRAINT fk_job_shortlist_entry_job_requirement_id FOREIGN KEY (job_requirement_id)
        REFERENCES job.job_requirement (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_shortlist_entry_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_shortlist_entry_shortlisted_by_user_account_id FOREIGN KEY (shortlisted_by_user_account_id)
        REFERENCES adm.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_shortlist_entry_application FOREIGN KEY (application_id, job_requirement_id)
        REFERENCES job.application (id, job_requirement_id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('job.job_shortlist_entry', 'shortlist_source', 'SHORTLIST_SOURCE');
SELECT core.add_audit_columns('job.job_shortlist_entry');
SELECT core.enable_soft_delete('job.job_shortlist_entry');
CREATE UNIQUE INDEX uq_job_shortlist_entry_job_candidate ON job.job_shortlist_entry (job_requirement_id, candidate_profile_id)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_job_shortlist_entry_candidate_profile_id ON job.job_shortlist_entry (candidate_profile_id);
CREATE INDEX idx_job_shortlist_entry_shortlisted_by_user_account_id ON job.job_shortlist_entry (shortlisted_by_user_account_id);
CREATE INDEX idx_job_shortlist_entry_application_id ON job.job_shortlist_entry (application_id, job_requirement_id)
    WHERE application_id IS NOT NULL;

COMMENT ON TABLE  job.job_shortlist_entry IS 'Candidates shortlisted for a job, whether or not they applied. One live entry per candidate per job. [lifecycle:soft_delete] [owner:team]';
COMMENT ON COLUMN job.job_shortlist_entry.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.job_shortlist_entry.job_requirement_id IS '[class:internal] Job.';
COMMENT ON COLUMN job.job_shortlist_entry.candidate_profile_id IS '[class:internal] Candidate.';
COMMENT ON COLUMN job.job_shortlist_entry.shortlisted_by_user_account_id IS '[class:internal] Recruiter, employer or consultant who shortlisted.';
COMMENT ON COLUMN job.job_shortlist_entry.application_id IS '[class:internal] [null: candidate has not applied, e.g. sourced from search] Matching application.';
COMMENT ON COLUMN job.job_shortlist_entry.note IS '[class:internal] [null: no note] Reviewer note.';

CREATE TABLE job.job_shortlist_event (
    id                     bigint GENERATED ALWAYS AS IDENTITY,
    job_shortlist_entry_id bigint NOT NULL,
    CONSTRAINT pk_job_shortlist_event PRIMARY KEY (id),
    CONSTRAINT fk_job_shortlist_event_job_shortlist_entry_id FOREIGN KEY (job_shortlist_entry_id)
        REFERENCES job.job_shortlist_entry (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('job.job_shortlist_event', 'shortlist_action', 'BOOKMARK_ACTION');
CREATE INDEX idx_job_shortlist_event_job_shortlist_entry_id ON job.job_shortlist_event (job_shortlist_entry_id);
SELECT core.add_creation_columns('job.job_shortlist_event');
COMMENT ON TABLE job.job_shortlist_event IS 'Shortlist history for employers and recruiters, written by trigger. [retention: kept with the shortlist entry] [owner:team]';
SELECT core.make_append_only('job.job_shortlist_event');

COMMENT ON COLUMN job.job_shortlist_event.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN job.job_shortlist_event.job_shortlist_entry_id IS '[class:internal] Shortlist entry that changed.';

CREATE FUNCTION job.trg_record_shortlist_event()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_action text;
BEGIN
    v_action := CASE
        WHEN TG_OP = 'INSERT' THEN 'ADDED'
        WHEN NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN 'REMOVED'
        WHEN NEW.note IS DISTINCT FROM OLD.note THEN 'NOTE_CHANGED'
    END;
    IF v_action IS NOT NULL THEN
        INSERT INTO job.job_shortlist_event (job_shortlist_entry_id, shortlist_action_ref_code_id)
        VALUES (NEW.id, mst.ref_code_id('BOOKMARK_ACTION', v_action));
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_job_shortlist_entry_history
    AFTER INSERT OR UPDATE ON job.job_shortlist_entry
    FOR EACH ROW EXECUTE FUNCTION job.trg_record_shortlist_event();

-- ===========================================================================
-- job_search_event (append-only, monthly partitions)
-- ===========================================================================
CREATE TABLE job.job_search_event (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    user_account_id      bigint,
    candidate_profile_id bigint,
    search_text          core.text_255,
    city_id              bigint,
    skill_id             bigint,
    job_role_id          bigint,
    min_salary_amount    core.money_amount,
    salary_currency_id   bigint,
    results_count        core.non_negative_int NOT NULL,
    searched_at          timestamptz           NOT NULL,
    CONSTRAINT pk_job_search_event PRIMARY KEY (id, searched_at),
    CONSTRAINT ck_job_search_event_salary_currency CHECK ((min_salary_amount IS NULL) = (salary_currency_id IS NULL)),
    CONSTRAINT ck_job_search_event_candidate_needs_account CHECK (candidate_profile_id IS NULL OR user_account_id IS NOT NULL),
    CONSTRAINT fk_job_search_event_user_account_id FOREIGN KEY (user_account_id)
        REFERENCES adm.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_search_event_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_search_event_city_id FOREIGN KEY (city_id)
        REFERENCES mst.city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_search_event_skill_id FOREIGN KEY (skill_id)
        REFERENCES mst.skill (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_search_event_job_role_id FOREIGN KEY (job_role_id)
        REFERENCES mst.job_role (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_job_search_event_salary_currency_id FOREIGN KEY (salary_currency_id)
        REFERENCES mst.currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT
) PARTITION BY RANGE (searched_at);
SELECT core.create_monthly_partitions('job.job_search_event', DATE '2024-01-01', DATE '2026-12-01');
CREATE INDEX idx_job_search_event_candidate_profile_id ON job.job_search_event (candidate_profile_id, searched_at DESC);
CREATE INDEX idx_job_search_event_user_account_id ON job.job_search_event (user_account_id, searched_at DESC);
SELECT core.add_creation_columns('job.job_search_event');
COMMENT ON TABLE job.job_search_event IS 'Candidate job-search history, one row per search, with the main filters as columns (feeds job alerts and trending-job analytics). [retention: 12 months, then drop partition] [owner:team]';
SELECT core.make_append_only('job.job_search_event');

COMMENT ON COLUMN job.job_search_event.id IS '[class:internal] Surrogate key (unique with searched_at).';
COMMENT ON COLUMN job.job_search_event.user_account_id IS '[class:internal] [null: guest search without an account] Who searched.';
COMMENT ON COLUMN job.job_search_event.candidate_profile_id IS '[class:internal] [null: searcher has no candidate profile, e.g. guest] Candidate who searched.';
COMMENT ON COLUMN job.job_search_event.search_text IS '[class:internal] [null: filter-only search] Keywords typed.';
COMMENT ON COLUMN job.job_search_event.city_id IS '[class:internal] [null: no location filter] Location filter.';
COMMENT ON COLUMN job.job_search_event.skill_id IS '[class:internal] [null: no skill filter] Skill filter.';
COMMENT ON COLUMN job.job_search_event.job_role_id IS '[class:internal] [null: no role filter] Role filter.';
COMMENT ON COLUMN job.job_search_event.min_salary_amount IS '[class:internal] [null: no salary filter] Minimum salary filter.';
COMMENT ON COLUMN job.job_search_event.salary_currency_id IS '[class:internal] [null: no salary filter] Currency of the salary filter.';
COMMENT ON COLUMN job.job_search_event.results_count IS '[class:internal] Number of jobs returned.';
COMMENT ON COLUMN job.job_search_event.searched_at IS '[class:internal] When the search ran (UTC); partition key.';

GRANT SELECT, INSERT, UPDATE ON job.job_shortlist_entry TO talentra_app;
GRANT SELECT, INSERT ON job.job_shortlist_event, job.job_search_event TO talentra_app;

RESET ROLE;
