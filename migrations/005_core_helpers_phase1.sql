-- 005_core_helpers_phase1.sql
-- Purpose : helpers every module needs from Phase 1 on:
--           enumeration definition, ref_code lookup, monthly/hash partition creation,
--           PII encryption, blind-index HMAC and masking.
--           Also the institution master table (needed by education and campus hiring).
-- Owner   : Dhanush (core), Master data (team)

SET ROLE talentra_owner;

-- ===========================================================================
-- Enumeration helpers
-- ===========================================================================

-- Defines a code type and its values (sort order 10, 20, ...) with English display names.
--   SELECT mst.define_enumeration('GENDER', 'Gender', 'PRF', 'Self-described gender.',
--          ARRAY['FEMALE','MALE'], ARRAY['Female','Male']);
CREATE FUNCTION mst.define_enumeration(
    p_code         text,
    p_english_name text,
    p_module       text,
    p_description  text,
    p_codes        text[],
    p_names        text[])
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_code_type_id bigint;
    v_language_id  bigint := (SELECT id FROM mst.language WHERE is_default);
    i int;
BEGIN
    IF array_length(p_codes, 1) IS DISTINCT FROM array_length(p_names, 1) THEN
        RAISE EXCEPTION 'enumeration %: codes and names arrays differ in length', p_code;
    END IF;

    INSERT INTO mst.code_type (code, english_name, description, owning_module)
    VALUES (p_code, p_english_name, p_description, p_module)
    RETURNING id INTO v_code_type_id;

    FOR i IN 1 .. array_length(p_codes, 1) LOOP
        WITH rc AS (
            INSERT INTO mst.ref_code (code_type_id, code, sort_order)
            VALUES (v_code_type_id, p_codes[i], i * 10)
            RETURNING id)
        INSERT INTO mst.ref_code_translation (ref_code_id, language_id, display_name)
        SELECT rc.id, v_language_id, p_names[i] FROM rc;
    END LOOP;
    RETURN v_code_type_id;
END $$;
COMMENT ON FUNCTION mst.define_enumeration(text, text, text, text, text[], text[]) IS
    'Creates a code type with its values and English display names in one call.';

-- id of one enumeration value; used in migrations to build CHECK constraints and seeds.
CREATE FUNCTION mst.ref_code_id(p_code_type text, p_code text)
RETURNS bigint
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_id bigint;
BEGIN
    SELECT rc.id INTO v_id
    FROM mst.ref_code rc JOIN mst.code_type ct ON ct.id = rc.code_type_id
    WHERE ct.code = p_code_type AND rc.code = p_code;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'unknown enumeration value %.%', p_code_type, p_code;
    END IF;
    RETURN v_id;
END $$;

-- ===========================================================================
-- Partition helpers (Rule 8 naming: <parent>_pYYYYMM, <parent>_hNN, <parent>_default)
-- ===========================================================================

CREATE FUNCTION core.create_monthly_partitions(p_parent regclass, p_from date, p_to date)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_schema text;
    v_table  text;
    v_month  date := date_trunc('month', p_from)::date;
    v_count  integer := 0;
BEGIN
    SELECT n.nspname, c.relname INTO v_schema, v_table
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.oid = p_parent;

    WHILE v_month <= p_to LOOP
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %s FOR VALUES FROM (%L) TO (%L)',
            v_schema, v_table || '_p' || to_char(v_month, 'YYYYMM'), p_parent,
            v_month, (v_month + interval '1 month')::date);
        v_month := (v_month + interval '1 month')::date;
        v_count := v_count + 1;
    END LOOP;

    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %s DEFAULT',
        v_schema, v_table || '_default', p_parent);
    RETURN v_count;
END $$;
COMMENT ON FUNCTION core.create_monthly_partitions(regclass, date, date) IS
    'Creates monthly range partitions <parent>_pYYYYMM for [from, to] plus <parent>_default.';

CREATE FUNCTION core.create_hash_partitions(p_parent regclass, p_modulus integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_schema text;
    v_table  text;
    i integer;
BEGIN
    SELECT n.nspname, c.relname INTO v_schema, v_table
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.oid = p_parent;

    FOR i IN 0 .. p_modulus - 1 LOOP
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %s FOR VALUES WITH (MODULUS %s, REMAINDER %s)',
            v_schema, v_table || '_h' || lpad(i::text, 2, '0'), p_parent, p_modulus, i);
    END LOOP;
    RETURN p_modulus;
END $$;
COMMENT ON FUNCTION core.create_hash_partitions(regclass, integer) IS
    'Creates hash partitions <parent>_h00 .. <parent>_hNN.';

-- ===========================================================================
-- PII protection (Rule 6, section 8 of the conventions)
--   pii_encrypt / pii_decrypt : pgcrypto symmetric encryption, key from app.pii_key
--   pii_hmac                  : deterministic blind index for exact-match lookup,
--                               uniqueness and duplicate detection, key from app.hmac_key
--   mask_email / mask_phone   : what a recruiter sees before a profile download
-- Keys come from session settings supplied by the application's secret store,
-- never from the database. Day 4 replaces the single key with per-user data keys
-- (crypto-shredding); the function signatures stay the same.
-- ===========================================================================

CREATE FUNCTION core.pii_key(p_name text)
RETURNS text
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_key text := current_setting(p_name, true);
BEGIN
    IF v_key IS NULL OR length(v_key) < 16 THEN
        RAISE EXCEPTION '% is not set (min 16 characters); PII cannot be processed', p_name
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN v_key;
END $$;

CREATE FUNCTION core.pii_encrypt(p_value text)
RETURNS bytea
LANGUAGE sql VOLATILE
AS $$
    SELECT CASE WHEN p_value IS NULL THEN NULL
                ELSE pgp_sym_encrypt(p_value, core.pii_key('app.pii_key'), 'cipher-algo=aes256') END;
$$;

CREATE FUNCTION core.pii_decrypt(p_value bytea)
RETURNS text
LANGUAGE sql STABLE
AS $$
    SELECT CASE WHEN p_value IS NULL THEN NULL
                ELSE pgp_sym_decrypt(p_value, core.pii_key('app.pii_key')) END;
$$;

-- Normalise before hashing so "Priya@Gmail.com " and "priya@gmail.com" match.
CREATE FUNCTION core.pii_hmac(p_value text)
RETURNS bytea
LANGUAGE sql STABLE
AS $$
    SELECT CASE WHEN p_value IS NULL THEN NULL
                ELSE hmac(lower(btrim(p_value)), core.pii_key('app.hmac_key'), 'sha256') END;
$$;

CREATE FUNCTION core.mask_email(p_email text)
RETURNS varchar
LANGUAGE sql IMMUTABLE
AS $$
    SELECT left(split_part(p_email, '@', 1), 2) || '***@' || split_part(p_email, '@', 2);
$$;

CREATE FUNCTION core.mask_phone(p_phone text)
RETURNS varchar
LANGUAGE sql IMMUTABLE
AS $$
    SELECT left(p_phone, 3) || repeat('*', greatest(length(p_phone) - 7, 0)) || right(p_phone, 4);
$$;

REVOKE ALL ON FUNCTION core.pii_decrypt(bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.pii_decrypt(bytea) TO talentra_app;

-- ===========================================================================
-- Master data addition: institution (colleges, universities, ITIs)
-- ===========================================================================
SELECT mst.define_enumeration('INSTITUTION_TYPE', 'Institution type', 'MST',
    'Kind of education provider.',
    ARRAY['UNIVERSITY', 'COLLEGE', 'POLYTECHNIC', 'ITI', 'SCHOOL', 'TRAINING_PROVIDER'],
    ARRAY['University', 'College', 'Polytechnic', 'Industrial Training Institute', 'School', 'Training provider']);

CREATE TABLE mst.institution (
    id           bigint GENERATED ALWAYS AS IDENTITY,
    english_name core.text_255 NOT NULL,
    city_id      bigint,
    is_active    boolean NOT NULL DEFAULT true,
    CONSTRAINT pk_institution PRIMARY KEY (id),
    CONSTRAINT uq_institution_english_name_city_id UNIQUE NULLS NOT DISTINCT (english_name, city_id),
    CONSTRAINT fk_institution_city_id FOREIGN KEY (city_id)
        REFERENCES mst.city (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_ref_code_column('mst.institution', 'institution_type', 'INSTITUTION_TYPE');
CREATE INDEX idx_institution_city_id ON mst.institution (city_id);
CREATE INDEX idx_institution_english_name_trgm ON mst.institution USING gin (english_name gin_trgm_ops);
SELECT core.add_audit_columns('mst.institution');

COMMENT ON TABLE  mst.institution IS 'Education providers; used by candidate education and campus hiring. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.institution.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.institution.english_name IS '[class:public] Official name.';
COMMENT ON COLUMN mst.institution.city_id IS '[class:public] [null: online or multi-campus provider] City of the main campus.';
COMMENT ON COLUMN mst.institution.is_active IS '[class:public] Selectable. Default true.';

SET LOCAL app.user_id = '1';
INSERT INTO mst.institution (english_name, city_id, institution_type_ref_code_id)
SELECT v.name, c.id, mst.ref_code_id('INSTITUTION_TYPE', v.kind)
FROM (VALUES
    ('JSS Academy of Technical Education', 'Bengaluru', 'COLLEGE'),
    ('Visvesvaraya Technological University', 'Belagavi', 'UNIVERSITY'),
    ('Indian Institute of Science', 'Bengaluru', 'UNIVERSITY'),
    ('Bangalore University', 'Bengaluru', 'UNIVERSITY'),
    ('Anna University', 'Chennai', 'UNIVERSITY'),
    ('University of Mumbai', 'Mumbai', 'UNIVERSITY'),
    ('University of Delhi', 'New Delhi', 'UNIVERSITY'),
    ('Osmania University', 'Hyderabad', 'UNIVERSITY'),
    ('Government Polytechnic Pune', 'Pune', 'POLYTECHNIC'),
    ('Government ITI Bengaluru', 'Bengaluru', 'ITI')
) AS v(name, city, kind)
JOIN mst.city c ON c.english_name = v.city;

GRANT SELECT ON mst.institution TO talentra_app;

RESET ROLE;
