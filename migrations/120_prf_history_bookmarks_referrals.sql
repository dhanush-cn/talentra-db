-- 120_prf_history_bookmarks_referrals.sql
-- Purpose : Profile module, part 3: append-only history and relationships around a profile.
--             profile_view_event        who viewed which profile, when (monthly partitions)
--             candidate_activity_event  login, profile update, resume download ... (monthly partitions)
--             candidate_bookmark        recruiter/employer saved candidates (current state)
--             candidate_bookmark_event  bookmark history, written automatically by trigger
--             referral                  referral codes and their progress
-- Owner   : Profile (whole team, Phase 1)
-- Partitioning: high-volume event tables are range-partitioned by month so retention is a
-- DROP PARTITION, and "last 30 days" queries touch one or two partitions. Their primary key
-- is (id, <timestamp>) because PostgreSQL requires the partition key in every unique
-- constraint (deviation D-04).

SET ROLE talentra_owner;
SET LOCAL app.user_id = '1';

SELECT mst.define_enumeration('VIEW_SOURCE', 'Profile view source', 'PRF', 'Where a profile view started.',
    ARRAY['SEARCH', 'APPLICATION', 'RECOMMENDATION', 'SHORTLIST', 'DIRECT_LINK'],
    ARRAY['Search results', 'Job application', 'Recommendation', 'Shortlist', 'Direct link']);
SELECT mst.define_enumeration('ACTIVITY_TYPE', 'Candidate activity type', 'PRF', 'Events in the candidate activity log.',
    ARRAY['LOGIN', 'LOGOUT', 'PROFILE_UPDATE', 'RESUME_UPLOAD', 'RESUME_DOWNLOAD', 'CONTACT_VERIFIED', 'PASSWORD_CHANGE'],
    ARRAY['Signed in', 'Signed out', 'Updated profile', 'Uploaded resume', 'Downloaded resume', 'Verified contact', 'Changed password']);
SELECT mst.define_enumeration('BOOKMARK_ACTION', 'Bookmark action', 'PRF', 'Change recorded in bookmark history.',
    ARRAY['ADDED', 'NOTE_CHANGED', 'REMOVED'], ARRAY['Added', 'Note changed', 'Removed']);
SELECT mst.define_enumeration('REFERRAL_STATUS', 'Referral status', 'PRF', 'Progress of a referral.',
    ARRAY['INVITED', 'REGISTERED', 'APPLIED', 'HIRED', 'EXPIRED'],
    ARRAY['Invited', 'Registered', 'Applied', 'Hired', 'Expired']);

-- ===========================================================================
-- profile_view_event (append-only, monthly partitions)
-- ===========================================================================
CREATE TABLE prf.profile_view_event (
    id                     bigint GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id   bigint      NOT NULL,
    viewer_user_account_id bigint      NOT NULL,
    viewer_organisation_id bigint,
    viewed_at              timestamptz NOT NULL,
    CONSTRAINT pk_profile_view_event PRIMARY KEY (id, viewed_at),
    CONSTRAINT fk_profile_view_event_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_profile_view_event_viewer_user_account_id FOREIGN KEY (viewer_user_account_id)
        REFERENCES adm.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_profile_view_event_viewer_organisation_id FOREIGN KEY (viewer_organisation_id)
        REFERENCES org.organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT
) PARTITION BY RANGE (viewed_at);
SELECT core.add_ref_code_column('prf.profile_view_event', 'view_source', 'VIEW_SOURCE');
SELECT core.create_monthly_partitions('prf.profile_view_event', DATE '2024-01-01', DATE '2026-12-01');
CREATE INDEX idx_profile_view_event_candidate_profile_id ON prf.profile_view_event (candidate_profile_id, viewed_at DESC);
CREATE INDEX idx_profile_view_event_viewer_organisation_id ON prf.profile_view_event (viewer_organisation_id, viewed_at DESC);
CREATE INDEX idx_profile_view_event_viewer_user_account_id ON prf.profile_view_event (viewer_user_account_id);
SELECT core.add_creation_columns('prf.profile_view_event');
COMMENT ON TABLE prf.profile_view_event IS 'Every view of a candidate profile by an employer, recruiter or consultant. [retention: 24 months, then drop partition] [owner:team]';
SELECT core.make_append_only('prf.profile_view_event');

COMMENT ON COLUMN prf.profile_view_event.id IS '[class:internal] Surrogate key (unique with viewed_at).';
COMMENT ON COLUMN prf.profile_view_event.candidate_profile_id IS '[class:internal] Profile viewed (the subject).';
COMMENT ON COLUMN prf.profile_view_event.viewer_user_account_id IS '[class:internal] Who viewed it (the actor).';
COMMENT ON COLUMN prf.profile_view_event.viewer_organisation_id IS '[class:internal] [null: viewer was not acting for an organisation, e.g. an independent consultant] Organisation the viewer acted for.';
COMMENT ON COLUMN prf.profile_view_event.viewed_at IS '[class:internal] When it was viewed (UTC); partition key.';

-- ===========================================================================
-- candidate_activity_event (append-only, monthly partitions)
-- ===========================================================================
CREATE TABLE prf.candidate_activity_event (
    id                   bigint GENERATED ALWAYS AS IDENTITY,
    user_account_id      bigint        NOT NULL,
    candidate_profile_id bigint,
    occurred_at          timestamptz   NOT NULL,
    detail               core.text_255,
    CONSTRAINT pk_candidate_activity_event PRIMARY KEY (id, occurred_at),
    CONSTRAINT fk_candidate_activity_event_user_account_id FOREIGN KEY (user_account_id)
        REFERENCES adm.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_activity_event_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT
) PARTITION BY RANGE (occurred_at);
SELECT core.add_ref_code_column('prf.candidate_activity_event', 'activity_type', 'ACTIVITY_TYPE');
SELECT core.create_monthly_partitions('prf.candidate_activity_event', DATE '2024-01-01', DATE '2026-12-01');
CREATE INDEX idx_candidate_activity_event_user_account_id ON prf.candidate_activity_event (user_account_id, occurred_at DESC);
CREATE INDEX idx_candidate_activity_event_candidate_profile_id ON prf.candidate_activity_event (candidate_profile_id, occurred_at DESC);
SELECT core.add_creation_columns('prf.candidate_activity_event');
COMMENT ON TABLE prf.candidate_activity_event IS 'Candidate activity log: sign-ins, profile updates, resume uploads and downloads. [retention: 24 months, then drop partition] [owner:team]';
SELECT core.make_append_only('prf.candidate_activity_event');

COMMENT ON COLUMN prf.candidate_activity_event.id IS '[class:internal] Surrogate key (unique with occurred_at).';
COMMENT ON COLUMN prf.candidate_activity_event.user_account_id IS '[class:internal] Account that acted.';
COMMENT ON COLUMN prf.candidate_activity_event.candidate_profile_id IS '[class:internal] [null: account had no candidate profile yet, e.g. first sign-in] Profile affected.';
COMMENT ON COLUMN prf.candidate_activity_event.occurred_at IS '[class:internal] When it happened (UTC); partition key.';
COMMENT ON COLUMN prf.candidate_activity_event.detail IS '[class:internal] [null: event type says everything] Short machine-readable detail, never personal data.';

-- ===========================================================================
-- candidate_bookmark and candidate_bookmark_event
-- ===========================================================================
CREATE TABLE prf.candidate_bookmark (
    id                    bigint GENERATED ALWAYS AS IDENTITY,
    owner_user_account_id bigint         NOT NULL,
    organisation_id       bigint,
    candidate_profile_id  bigint         NOT NULL,
    note                  core.text_1000,
    CONSTRAINT pk_candidate_bookmark PRIMARY KEY (id),
    CONSTRAINT fk_candidate_bookmark_owner_user_account_id FOREIGN KEY (owner_user_account_id)
        REFERENCES adm.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_bookmark_organisation_id FOREIGN KEY (organisation_id)
        REFERENCES org.organisation (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_bookmark_candidate_profile_id FOREIGN KEY (candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_audit_columns('prf.candidate_bookmark');
SELECT core.enable_soft_delete('prf.candidate_bookmark');
CREATE UNIQUE INDEX uq_candidate_bookmark_owner_candidate ON prf.candidate_bookmark (owner_user_account_id, candidate_profile_id)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_candidate_bookmark_candidate_profile_id ON prf.candidate_bookmark (candidate_profile_id);
CREATE INDEX idx_candidate_bookmark_organisation_id ON prf.candidate_bookmark (organisation_id);

COMMENT ON TABLE  prf.candidate_bookmark IS 'Candidates saved by an employer, recruiter or consultant (current state). History is in candidate_bookmark_event. [lifecycle:soft_delete] [owner:team]';
COMMENT ON COLUMN prf.candidate_bookmark.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_bookmark.owner_user_account_id IS '[class:internal] Who saved the candidate.';
COMMENT ON COLUMN prf.candidate_bookmark.organisation_id IS '[class:internal] [null: saved by an independent consultant] Organisation the owner acted for.';
COMMENT ON COLUMN prf.candidate_bookmark.candidate_profile_id IS '[class:internal] Candidate saved.';
COMMENT ON COLUMN prf.candidate_bookmark.note IS '[class:internal] [null: no note] Private note by the owner.';

CREATE TABLE prf.candidate_bookmark_event (
    id                    bigint GENERATED ALWAYS AS IDENTITY,
    candidate_bookmark_id bigint NOT NULL,
    CONSTRAINT pk_candidate_bookmark_event PRIMARY KEY (id),
    CONSTRAINT fk_candidate_bookmark_event_candidate_bookmark_id FOREIGN KEY (candidate_bookmark_id)
        REFERENCES prf.candidate_bookmark (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('prf.candidate_bookmark_event', 'bookmark_action', 'BOOKMARK_ACTION');
CREATE INDEX idx_candidate_bookmark_event_candidate_bookmark_id ON prf.candidate_bookmark_event (candidate_bookmark_id);
SELECT core.add_creation_columns('prf.candidate_bookmark_event');
COMMENT ON TABLE prf.candidate_bookmark_event IS 'Bookmark and shortlist history for employers and recruiters, written by trigger. [retention: kept with the bookmark] [owner:team]';
SELECT core.make_append_only('prf.candidate_bookmark_event');

COMMENT ON COLUMN prf.candidate_bookmark_event.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.candidate_bookmark_event.candidate_bookmark_id IS '[class:internal] Bookmark that changed.';

CREATE FUNCTION prf.trg_record_bookmark_event()
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
        INSERT INTO prf.candidate_bookmark_event (candidate_bookmark_id, bookmark_action_ref_code_id)
        VALUES (NEW.id, mst.ref_code_id('BOOKMARK_ACTION', v_action));
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_candidate_bookmark_history
    AFTER INSERT OR UPDATE ON prf.candidate_bookmark
    FOR EACH ROW EXECUTE FUNCTION prf.trg_record_bookmark_event();

-- ===========================================================================
-- referral
-- ===========================================================================
CREATE TABLE prf.referral (
    id                            bigint GENERATED ALWAYS AS IDENTITY,
    referrer_user_account_id      bigint        NOT NULL,
    referral_code                 varchar(16)   NOT NULL,
    referred_contact_hmac         bytea,
    referred_candidate_profile_id bigint,
    job_requirement_id            bigint,
    invited_at                    timestamptz   NOT NULL,
    expires_at                    timestamptz   NOT NULL,
    CONSTRAINT pk_referral PRIMARY KEY (id),
    CONSTRAINT uq_referral_referral_code UNIQUE (referral_code),
    CONSTRAINT ck_referral_referral_code CHECK (referral_code ~ '^[A-Z0-9]{8,16}$'),
    CONSTRAINT ck_referral_dates CHECK (expires_at > invited_at),
    CONSTRAINT fk_referral_referrer_user_account_id FOREIGN KEY (referrer_user_account_id)
        REFERENCES adm.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_referral_referred_candidate_profile_id FOREIGN KEY (referred_candidate_profile_id)
        REFERENCES prf.candidate_profile (id) ON UPDATE RESTRICT ON DELETE RESTRICT
    -- fk to job.job_requirement is added in 200_job_requirement.sql
);
SELECT core.add_ref_code_column('prf.referral', 'referral_status', 'REFERRAL_STATUS');
DO $$
BEGIN
    EXECUTE format('ALTER TABLE prf.referral ADD CONSTRAINT ck_referral_registered_has_candidate
        CHECK (referral_status_ref_code_id IN (%s, %s) OR referred_candidate_profile_id IS NOT NULL)',
        mst.ref_code_id('REFERRAL_STATUS', 'INVITED'), mst.ref_code_id('REFERRAL_STATUS', 'EXPIRED'));
END $$;
CREATE INDEX idx_referral_referrer_user_account_id ON prf.referral (referrer_user_account_id);
CREATE INDEX idx_referral_referred_candidate_profile_id ON prf.referral (referred_candidate_profile_id);
CREATE INDEX idx_referral_job_requirement_id ON prf.referral (job_requirement_id);
SELECT core.add_audit_columns('prf.referral');
SELECT core.enable_soft_delete('prf.referral');

COMMENT ON TABLE  prf.referral IS 'Referral codes issued by users and how far each referral progressed. Referral reward events are in the Notifications module. [lifecycle:soft_delete] [owner:team]';
COMMENT ON COLUMN prf.referral.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN prf.referral.referrer_user_account_id IS '[class:internal] Who referred.';
COMMENT ON COLUMN prf.referral.referral_code IS '[class:public] Code shared with the invitee, 8–16 uppercase letters or digits.';
COMMENT ON COLUMN prf.referral.referred_contact_hmac IS '[class:personal] [null: open link with no named invitee] Blind index of the invitee''s email or phone; the contact itself is not stored.';
COMMENT ON COLUMN prf.referral.referred_candidate_profile_id IS '[class:internal] [null: invitee has not registered yet] Candidate who registered with the code.';
COMMENT ON COLUMN prf.referral.job_requirement_id IS '[class:internal] [null: general referral, not for a specific job] Job the referral is for.';
COMMENT ON COLUMN prf.referral.invited_at IS '[class:internal] When the code was issued (UTC).';
COMMENT ON COLUMN prf.referral.expires_at IS '[class:internal] When the code stops working (UTC).';

GRANT SELECT, INSERT ON prf.profile_view_event, prf.candidate_activity_event, prf.candidate_bookmark_event TO talentra_app;
GRANT SELECT, INSERT, UPDATE ON prf.candidate_bookmark, prf.referral TO talentra_app;

RESET ROLE;
