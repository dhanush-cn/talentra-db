-- 050_identity_anchors.sql
-- Purpose : the two anchor tables every module points at, created early so Phase 1
--           (Profile, Jobs) can reference them:
--             adm.user_account  : one row per person who can act on the platform
--             org.organisation  : one row per employer, client, consultancy or institution
-- Owners  : adm.user_account -> Administration (Dhanush) extends it with credentials,
--           roles, consent and blocking (migrations 300+).
--           org.organisation  -> Organisation and account (Bhargav) extends it with
--           hierarchy, locations, tax identifiers and verification (migrations 400+).
-- Only identity-level columns live here; everything else is added by the owning module.

SET ROLE talentra_owner;
SET LOCAL app.user_id = '1';

SELECT mst.define_enumeration('USER_TYPE', 'User type', 'ADM',
    'Primary persona of an account. Fine-grained permissions come from roles (Administration module).',
    ARRAY['SYSTEM', 'SUPER_ADMIN', 'ADMIN', 'ACCOUNT_ADMIN', 'CANDIDATE', 'GIG_WORKER', 'EMPLOYER',
          'RECRUITER', 'CONSULTANT', 'PLACEMENT_OFFICER', 'GUEST'],
    ARRAY['System', 'Super admin', 'Admin', 'Account admin', 'Candidate', 'Gig worker', 'Employer',
          'Recruiter', 'Consultant', 'Placement officer (TPO)', 'Guest']);

SELECT mst.define_enumeration('ACCOUNT_STATUS', 'Account status', 'ADM',
    'Lifecycle state of a user account or organisation account.',
    ARRAY['PENDING_VERIFICATION', 'ACTIVE', 'SUSPENDED', 'LOCKED', 'DEACTIVATED'],
    ARRAY['Pending verification', 'Active', 'Suspended', 'Locked', 'Deactivated']);

SELECT mst.define_enumeration('ORGANISATION_TYPE', 'Organisation type', 'ORG',
    'What kind of organisation an account represents.',
    ARRAY['EMPLOYER', 'CLIENT', 'CONSULTANCY', 'EDUCATIONAL_INSTITUTION', 'PLATFORM_OPERATOR'],
    ARRAY['Employer', 'Client', 'Consultancy', 'Educational institution', 'Platform operator']);

SELECT mst.define_enumeration('SOURCE_SYSTEM', 'Source system', 'MST',
    'Where a record originated; with source_record_id it forms the natural key from legacy systems.',
    ARRAY['DIRECT', 'LEGACY_ATS', 'LEGACY_CRM', 'BULK_IMPORT', 'CAMPUS_DRIVE'],
    ARRAY['Registered directly', 'Legacy applicant tracking system', 'Legacy CRM', 'Bulk import', 'Campus drive']);

-- ===========================================================================
-- adm.user_account
-- ===========================================================================
CREATE TABLE adm.user_account (
    id                    bigint GENERATED ALWAYS AS IDENTITY,
    public_id             uuid   NOT NULL DEFAULT gen_random_uuid(),
    preferred_language_id bigint NOT NULL,
    last_login_at         timestamptz,
    CONSTRAINT pk_user_account PRIMARY KEY (id),
    CONSTRAINT uq_user_account_public_id UNIQUE (public_id),
    CONSTRAINT fk_user_account_preferred_language_id FOREIGN KEY (preferred_language_id)
        REFERENCES mst.language (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('adm.user_account', 'user_type', 'USER_TYPE');
SELECT core.add_ref_code_column('adm.user_account', 'account_status', 'ACCOUNT_STATUS');
SELECT core.add_audit_columns('adm.user_account');
SELECT core.enable_soft_delete('adm.user_account');

COMMENT ON TABLE  adm.user_account IS 'Anyone who can act on the platform. Credentials, roles and consent are attached by the Administration module. [lifecycle:soft_delete] [retention: anonymised 30 days after an erasure request] [owner:adm]';
COMMENT ON COLUMN adm.user_account.id IS '[class:internal] Surrogate key. Never exposed outside the platform.';
COMMENT ON COLUMN adm.user_account.public_id IS '[class:internal] Identifier used in URLs and APIs.';
COMMENT ON COLUMN adm.user_account.preferred_language_id IS '[class:internal] UI language.';
COMMENT ON COLUMN adm.user_account.last_login_at IS '[class:internal] [null: account has never signed in] Most recent successful sign-in (UTC).';

-- System account: id 1. Migrations, seeds and scheduled jobs act as this account.
INSERT INTO adm.user_account (preferred_language_id, user_type_ref_code_id, account_status_ref_code_id)
VALUES ((SELECT id FROM mst.language WHERE is_default),
        mst.ref_code_id('USER_TYPE', 'SYSTEM'),
        mst.ref_code_id('ACCOUNT_STATUS', 'ACTIVE'));

DO $$
BEGIN
    IF (SELECT max(id) FROM adm.user_account) <> 1 THEN
        RAISE EXCEPTION 'system account must be user_account id 1';
    END IF;
END $$;

-- ===========================================================================
-- org.organisation
-- ===========================================================================
CREATE TABLE org.organisation (
    id           bigint GENERATED ALWAYS AS IDENTITY,
    public_id    uuid          NOT NULL DEFAULT gen_random_uuid(),
    legal_name   core.text_255 NOT NULL,
    display_name core.text_255 NOT NULL,
    country_id   bigint        NOT NULL,
    CONSTRAINT pk_organisation PRIMARY KEY (id),
    CONSTRAINT uq_organisation_public_id UNIQUE (public_id),
    CONSTRAINT fk_organisation_country_id FOREIGN KEY (country_id)
        REFERENCES mst.country (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('org.organisation', 'organisation_type', 'ORGANISATION_TYPE');
SELECT core.add_ref_code_column('org.organisation', 'account_status', 'ACCOUNT_STATUS');
CREATE INDEX idx_organisation_country_id ON org.organisation (country_id);
CREATE INDEX idx_organisation_display_name_trgm ON org.organisation USING gin (display_name gin_trgm_ops);
SELECT core.add_audit_columns('org.organisation');
SELECT core.enable_soft_delete('org.organisation');

COMMENT ON TABLE  org.organisation IS 'Employers, clients, consultancies and institutions. Hierarchy, locations, tax identifiers and verification are added by the Organisation module. [lifecycle:soft_delete] [retention: kept while any job or invoice references it] [owner:org]';
COMMENT ON COLUMN org.organisation.id IS '[class:internal] Surrogate key.';
COMMENT ON COLUMN org.organisation.public_id IS '[class:public] Identifier used in URLs and APIs.';
COMMENT ON COLUMN org.organisation.legal_name IS '[class:public] Registered legal name.';
COMMENT ON COLUMN org.organisation.display_name IS '[class:public] Name shown on job posts.';
COMMENT ON COLUMN org.organisation.country_id IS '[class:public] Country of registration.';

GRANT SELECT, INSERT, UPDATE ON adm.user_account, org.organisation TO talentra_app;

RESET ROLE;
