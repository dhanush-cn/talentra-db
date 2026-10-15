-- 003_master_reference_tables.sql
-- Purpose : geography, currency, skills, qualifications, industries and job roles.
-- Owner   : Master data (whole team, Phase 1)
-- Lifecycle: master rows are never deleted. Retire with is_active = false;
--            ON DELETE RESTRICT on every referencing FK guarantees this.

SET ROLE talentra_owner;

-- Code types used by the tables below must exist before core.add_ref_code_column runs.
SET LOCAL app.user_id = '1';
INSERT INTO mst.code_type (code, english_name, description, owning_module) VALUES
    ('COORDINATE_SOURCE',   'Coordinate source',   'Where a latitude/longitude pair came from.', 'MST'),
    ('SKILL_CATEGORY',      'Skill category',      'Broad grouping of skills.', 'MST'),
    ('QUALIFICATION_LEVEL', 'Qualification level', 'Education level of a qualification.', 'MST');

-- ===========================================================================
-- currency
-- ===========================================================================
CREATE TABLE mst.currency (
    id          bigint GENERATED ALWAYS AS IDENTITY,
    iso_code    varchar(3)      NOT NULL,
    english_name core.text_100  NOT NULL,
    minor_unit  smallint        NOT NULL,
    is_active   boolean         NOT NULL DEFAULT true,
    sort_order  core.sort_order NOT NULL DEFAULT 0,
    CONSTRAINT pk_currency PRIMARY KEY (id),
    CONSTRAINT uq_currency_iso_code UNIQUE (iso_code),
    CONSTRAINT ck_currency_iso_code CHECK (iso_code ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_currency_minor_unit CHECK (minor_unit BETWEEN 0 AND 4)
);
SELECT core.add_audit_columns('mst.currency');

COMMENT ON TABLE  mst.currency IS 'ISO 4217 currencies. Every money column pairs with a currency_id. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.currency.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.currency.iso_code IS '[class:public] ISO 4217 code, e.g. INR.';
COMMENT ON COLUMN mst.currency.english_name IS '[class:public] Name in English.';
COMMENT ON COLUMN mst.currency.minor_unit IS '[class:public] Decimal places used by the currency (0–4).';
COMMENT ON COLUMN mst.currency.is_active IS '[class:public] Accepted for new transactions. Default true.';
COMMENT ON COLUMN mst.currency.sort_order IS '[class:public] Display order.';

-- ===========================================================================
-- country
-- ===========================================================================
CREATE TABLE mst.country (
    id                  bigint GENERATED ALWAYS AS IDENTITY,
    iso2_code           varchar(2)      NOT NULL,
    iso3_code           varchar(3)      NOT NULL,
    english_name        core.text_100   NOT NULL,
    phone_calling_code  varchar(4)      NOT NULL,
    currency_id         bigint          NOT NULL,
    is_active           boolean         NOT NULL DEFAULT true,
    CONSTRAINT pk_country PRIMARY KEY (id),
    CONSTRAINT uq_country_iso2_code UNIQUE (iso2_code),
    CONSTRAINT uq_country_iso3_code UNIQUE (iso3_code),
    CONSTRAINT ck_country_iso2_code CHECK (iso2_code ~ '^[A-Z]{2}$'),
    CONSTRAINT ck_country_iso3_code CHECK (iso3_code ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_country_phone_calling_code CHECK (phone_calling_code ~ '^[1-9][0-9]{0,3}$'),
    CONSTRAINT fk_country_currency_id FOREIGN KEY (currency_id)
        REFERENCES mst.currency (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_country_currency_id ON mst.country (currency_id);
SELECT core.add_audit_columns('mst.country');

COMMENT ON TABLE  mst.country IS 'ISO 3166-1 countries. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.country.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.country.iso2_code IS '[class:public] ISO 3166-1 alpha-2, e.g. IN.';
COMMENT ON COLUMN mst.country.iso3_code IS '[class:public] ISO 3166-1 alpha-3, e.g. IND.';
COMMENT ON COLUMN mst.country.english_name IS '[class:public] Name in English.';
COMMENT ON COLUMN mst.country.phone_calling_code IS '[class:public] E.164 country calling code without +, e.g. 91.';
COMMENT ON COLUMN mst.country.currency_id IS '[class:public] Default currency.';
COMMENT ON COLUMN mst.country.is_active IS '[class:public] Selectable. Default true.';

-- ===========================================================================
-- state (state, province or union territory)
-- ===========================================================================
CREATE TABLE mst.state (
    id           bigint GENERATED ALWAYS AS IDENTITY,
    country_id   bigint        NOT NULL,
    iso_code     varchar(10)   NOT NULL,
    english_name core.text_100 NOT NULL,
    is_union_territory boolean NOT NULL DEFAULT false,
    is_active    boolean       NOT NULL DEFAULT true,
    CONSTRAINT pk_state PRIMARY KEY (id),
    CONSTRAINT uq_state_iso_code UNIQUE (iso_code),
    CONSTRAINT ck_state_iso_code CHECK (iso_code ~ '^[A-Z]{2}-[A-Z0-9]{1,3}$'),
    CONSTRAINT fk_state_country_id FOREIGN KEY (country_id)
        REFERENCES mst.country (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_state_country_id ON mst.state (country_id);
SELECT core.add_audit_columns('mst.state');

COMMENT ON TABLE  mst.state IS 'First-level subdivisions (ISO 3166-2). [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.state.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.state.country_id IS '[class:public] Country the subdivision belongs to.';
COMMENT ON COLUMN mst.state.iso_code IS '[class:public] ISO 3166-2 code, e.g. IN-KA.';
COMMENT ON COLUMN mst.state.english_name IS '[class:public] Name in English.';
COMMENT ON COLUMN mst.state.is_union_territory IS '[class:public] Union territory rather than state. Default false.';
COMMENT ON COLUMN mst.state.is_active IS '[class:public] Selectable. Default true.';

-- ===========================================================================
-- city
-- ===========================================================================
CREATE TABLE mst.city (
    id           bigint GENERATED ALWAYS AS IDENTITY,
    state_id     bigint        NOT NULL,
    english_name core.text_100 NOT NULL,
    latitude     core.latitude,
    longitude    core.longitude,
    is_active    boolean       NOT NULL DEFAULT true,
    CONSTRAINT pk_city PRIMARY KEY (id),
    CONSTRAINT uq_city_state_id_english_name UNIQUE (state_id, english_name),
    CONSTRAINT ck_city_coordinates_pair CHECK ((latitude IS NULL) = (longitude IS NULL)),
    CONSTRAINT fk_city_state_id FOREIGN KEY (state_id)
        REFERENCES mst.state (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('mst.city', 'coordinate_source', 'COORDINATE_SOURCE', true, 'city not geocoded yet');
ALTER TABLE mst.city ADD CONSTRAINT ck_city_coordinate_source
    CHECK ((latitude IS NULL) = (coordinate_source_ref_code_id IS NULL));
CREATE INDEX idx_city_english_name_trgm ON mst.city USING gin (english_name gin_trgm_ops);
SELECT core.add_audit_columns('mst.city');

COMMENT ON TABLE  mst.city IS 'Cities and towns. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.city.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.city.state_id IS '[class:public] State the city is in. Covered by uq_city_state_id_english_name.';
COMMENT ON COLUMN mst.city.english_name IS '[class:public] Name in English.';
COMMENT ON COLUMN mst.city.latitude IS '[class:public] [null: city not geocoded yet] WGS84 latitude, 6 decimals.';
COMMENT ON COLUMN mst.city.longitude IS '[class:public] [null: city not geocoded yet] WGS84 longitude, 6 decimals.';
COMMENT ON COLUMN mst.city.is_active IS '[class:public] Selectable. Default true.';

-- ===========================================================================
-- skill
-- ===========================================================================
CREATE TABLE mst.skill (
    id              bigint GENERATED ALWAYS AS IDENTITY,
    english_name    core.text_100 NOT NULL,
    normalized_name varchar(100) NOT NULL GENERATED ALWAYS AS (lower(btrim(english_name))) STORED,
    is_active       boolean       NOT NULL DEFAULT true,
    CONSTRAINT pk_skill PRIMARY KEY (id),
    CONSTRAINT uq_skill_normalized_name UNIQUE (normalized_name)
);
SELECT core.add_ref_code_column('mst.skill', 'skill_category', 'SKILL_CATEGORY');
CREATE INDEX idx_skill_english_name_trgm ON mst.skill USING gin (english_name gin_trgm_ops);
SELECT core.add_audit_columns('mst.skill');

COMMENT ON TABLE  mst.skill IS 'Skill catalogue shared by candidates, jobs and gigs. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.skill.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.skill.english_name IS '[class:public] Canonical name, e.g. PostgreSQL.';
COMMENT ON COLUMN mst.skill.normalized_name IS '[class:public] Lowercased, trimmed name; prevents duplicates such as "Java" and "java ".';
COMMENT ON COLUMN mst.skill.is_active IS '[class:public] Selectable. Default true.';

-- ===========================================================================
-- qualification
-- ===========================================================================
CREATE TABLE mst.qualification (
    id           bigint GENERATED ALWAYS AS IDENTITY,
    english_name core.text_255 NOT NULL,
    short_name   core.text_100 NOT NULL,
    is_active    boolean       NOT NULL DEFAULT true,
    CONSTRAINT pk_qualification PRIMARY KEY (id),
    CONSTRAINT uq_qualification_english_name UNIQUE (english_name)
);
SELECT core.add_ref_code_column('mst.qualification', 'qualification_level', 'QUALIFICATION_LEVEL');
SELECT core.add_audit_columns('mst.qualification');

COMMENT ON TABLE  mst.qualification IS 'Degrees, diplomas and certificates. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.qualification.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.qualification.english_name IS '[class:public] Full name, e.g. Bachelor of Engineering.';
COMMENT ON COLUMN mst.qualification.short_name IS '[class:public] Abbreviation shown in lists, e.g. B.E.';
COMMENT ON COLUMN mst.qualification.is_active IS '[class:public] Selectable. Default true.';

-- ===========================================================================
-- industry (two-level hierarchy)
-- ===========================================================================
CREATE TABLE mst.industry (
    id                 bigint GENERATED ALWAYS AS IDENTITY,
    parent_industry_id bigint,
    english_name       core.text_255 NOT NULL,
    is_active          boolean       NOT NULL DEFAULT true,
    CONSTRAINT pk_industry PRIMARY KEY (id),
    CONSTRAINT uq_industry_english_name UNIQUE (english_name),
    CONSTRAINT ck_industry_not_own_parent CHECK (parent_industry_id IS DISTINCT FROM id),
    CONSTRAINT fk_industry_parent_industry_id FOREIGN KEY (parent_industry_id)
        REFERENCES mst.industry (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_industry_parent_industry_id ON mst.industry (parent_industry_id);
SELECT core.add_audit_columns('mst.industry');

COMMENT ON TABLE  mst.industry IS 'Industry classification with optional parent. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.industry.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.industry.parent_industry_id IS '[class:public] [null: top-level industry] Parent industry.';
COMMENT ON COLUMN mst.industry.english_name IS '[class:public] Name in English.';
COMMENT ON COLUMN mst.industry.is_active IS '[class:public] Selectable. Default true.';

-- ===========================================================================
-- job_role
-- ===========================================================================
CREATE TABLE mst.job_role (
    id           bigint GENERATED ALWAYS AS IDENTITY,
    industry_id  bigint        NOT NULL,
    english_name core.text_255 NOT NULL,
    is_active    boolean       NOT NULL DEFAULT true,
    CONSTRAINT pk_job_role PRIMARY KEY (id),
    CONSTRAINT uq_job_role_industry_id_english_name UNIQUE (industry_id, english_name),
    CONSTRAINT fk_job_role_industry_id FOREIGN KEY (industry_id)
        REFERENCES mst.industry (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_job_role_english_name_trgm ON mst.job_role USING gin (english_name gin_trgm_ops);
SELECT core.add_audit_columns('mst.job_role');

COMMENT ON TABLE  mst.job_role IS 'Standard job roles used to classify jobs and candidate experience. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.job_role.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.job_role.industry_id IS '[class:public] Industry the role belongs to. Covered by uq_job_role_industry_id_english_name.';
COMMENT ON COLUMN mst.job_role.english_name IS '[class:public] Name in English, e.g. Backend Engineer.';
COMMENT ON COLUMN mst.job_role.is_active IS '[class:public] Selectable. Default true.';

GRANT SELECT ON mst.currency, mst.country, mst.state, mst.city, mst.skill,
                mst.qualification, mst.industry, mst.job_role TO talentra_app;

RESET ROLE;
