-- 002_master_lookup_framework.sql
-- Purpose : languages, the generic enumeration (ref_code) model with per-language
--           display names, UI label translations, and the helper every module uses
--           to add an enumeration column with an enforced composite foreign key.
-- Owner   : Master data (whole team, Phase 1)
-- Rule refs: Rule 3 (enumeration, UI label), Rule 7 (multilingual)

SET ROLE talentra_owner;

-- ===========================================================================
-- language
-- ===========================================================================
CREATE TABLE mst.language (
    id               bigint GENERATED ALWAYS AS IDENTITY,
    iso_code         varchar(10)     NOT NULL,
    english_name     core.text_100   NOT NULL,
    native_name      core.text_100   NOT NULL,
    is_default       boolean         NOT NULL DEFAULT false,
    is_ui_supported  boolean         NOT NULL DEFAULT false,
    is_active        boolean         NOT NULL DEFAULT true,
    sort_order       core.sort_order NOT NULL DEFAULT 0,
    CONSTRAINT pk_language PRIMARY KEY (id),
    CONSTRAINT uq_language_iso_code UNIQUE (iso_code),
    CONSTRAINT ck_language_iso_code CHECK (iso_code ~ '^[a-z]{2,3}(-[A-Z]{2})?$'),
    CONSTRAINT ck_language_default_is_ui CHECK (NOT is_default OR (is_ui_supported AND is_active))
);
-- Exactly one default language: the fallback for every translation (Rule 7).
CREATE UNIQUE INDEX uq_language_is_default ON mst.language (is_default) WHERE is_default;
SELECT core.add_audit_columns('mst.language');

COMMENT ON TABLE  mst.language IS 'Languages for UI and user content. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.language.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.language.iso_code IS '[class:public] ISO 639-1/639-3 code with optional region, e.g. en, kn, en-IN.';
COMMENT ON COLUMN mst.language.english_name IS '[class:public] Name in English.';
COMMENT ON COLUMN mst.language.native_name IS '[class:public] Name in its own script, e.g. ಕನ್ನಡ.';
COMMENT ON COLUMN mst.language.is_default IS '[class:public] Fallback language for missing translations. Exactly one row is true. Default false.';
COMMENT ON COLUMN mst.language.is_ui_supported IS '[class:public] UI strings are maintained in this language. Default false.';
COMMENT ON COLUMN mst.language.is_active IS '[class:public] Available for selection. Default true.';
COMMENT ON COLUMN mst.language.sort_order IS '[class:public] Display order in pickers.';

-- ===========================================================================
-- code_type: one row per enumeration (APPLICATION_STATUS, WORK_TYPE, ...)
-- ===========================================================================
CREATE TABLE mst.code_type (
    id           bigint GENERATED ALWAYS AS IDENTITY,
    code         core.code      NOT NULL,
    english_name core.text_100  NOT NULL,
    description  core.text_1000,
    owning_module core.code     NOT NULL,
    CONSTRAINT pk_code_type PRIMARY KEY (id),
    CONSTRAINT uq_code_type_code UNIQUE (code)
);
SELECT core.add_audit_columns('mst.code_type');

COMMENT ON TABLE  mst.code_type IS 'Catalogue of enumerations. Each fixed value list in any module is one row here. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.code_type.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.code_type.code IS '[class:public] Stable machine name, e.g. APPLICATION_STATUS.';
COMMENT ON COLUMN mst.code_type.english_name IS '[class:public] Name for administrators.';
COMMENT ON COLUMN mst.code_type.description IS '[class:public] [null: optional explanation for administrators] What the list is used for.';
COMMENT ON COLUMN mst.code_type.owning_module IS '[class:internal] Module responsible for the list, e.g. JOB, GIG.';

-- ===========================================================================
-- ref_code: the values of every enumeration
-- ===========================================================================
CREATE TABLE mst.ref_code (
    id            bigint GENERATED ALWAYS AS IDENTITY,
    code_type_id  bigint          NOT NULL,
    code          core.code       NOT NULL,
    sort_order    core.sort_order NOT NULL DEFAULT 0,
    is_active     boolean         NOT NULL DEFAULT true,
    CONSTRAINT pk_ref_code PRIMARY KEY (id),
    CONSTRAINT uq_ref_code_code_type_id_code UNIQUE (code_type_id, code),
    -- Target of the composite foreign keys: (type, value) must belong together.
    CONSTRAINT uq_ref_code_code_type_id_id UNIQUE (code_type_id, id),
    CONSTRAINT fk_ref_code_code_type_id FOREIGN KEY (code_type_id)
        REFERENCES mst.code_type (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
SELECT core.add_audit_columns('mst.ref_code');

COMMENT ON TABLE  mst.ref_code IS 'Values of every enumeration. Never deleted; retired values set is_active = false. [lifecycle:deactivate] [owner:team]';
COMMENT ON COLUMN mst.ref_code.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.ref_code.code_type_id IS '[class:public] Enumeration this value belongs to.';
COMMENT ON COLUMN mst.ref_code.code IS '[class:public] Stable machine value, e.g. SHORTLISTED. Never shown to users.';
COMMENT ON COLUMN mst.ref_code.sort_order IS '[class:public] Display and pipeline order.';
COMMENT ON COLUMN mst.ref_code.is_active IS '[class:public] Selectable for new rows. Default true.';

-- ===========================================================================
-- ref_code_translation: display name per language (Rule 3 enumeration)
-- ===========================================================================
CREATE TABLE mst.ref_code_translation (
    id           bigint GENERATED ALWAYS AS IDENTITY,
    ref_code_id  bigint         NOT NULL,
    language_id  bigint         NOT NULL,
    display_name core.text_255  NOT NULL,
    CONSTRAINT pk_ref_code_translation PRIMARY KEY (id),
    CONSTRAINT uq_ref_code_translation_ref_code_id_language_id UNIQUE (ref_code_id, language_id),
    CONSTRAINT fk_ref_code_translation_ref_code_id FOREIGN KEY (ref_code_id)
        REFERENCES mst.ref_code (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_ref_code_translation_language_id FOREIGN KEY (language_id)
        REFERENCES mst.language (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_ref_code_translation_language_id ON mst.ref_code_translation (language_id);
SELECT core.add_audit_columns('mst.ref_code_translation');

COMMENT ON TABLE  mst.ref_code_translation IS 'Display name of each enumeration value per language. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN mst.ref_code_translation.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.ref_code_translation.ref_code_id IS '[class:public] Value being translated.';
COMMENT ON COLUMN mst.ref_code_translation.language_id IS '[class:public] Language of display_name.';
COMMENT ON COLUMN mst.ref_code_translation.display_name IS '[class:public] Text shown to users.';

-- ===========================================================================
-- ui_label and ui_label_translation (Rule 3 UI label, Rule 7)
-- ===========================================================================
CREATE TABLE mst.ui_label (
    id          bigint GENERATED ALWAYS AS IDENTITY,
    label_key   core.label_key NOT NULL,
    description core.text_1000,
    CONSTRAINT pk_ui_label PRIMARY KEY (id),
    CONSTRAINT uq_ui_label_label_key UNIQUE (label_key)
);
SELECT core.add_audit_columns('mst.ui_label');

COMMENT ON TABLE  mst.ui_label IS 'UI string keys. Keys are never displayed to users. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN mst.ui_label.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.ui_label.label_key IS '[class:public] Dotted key, e.g. job.apply.button.';
COMMENT ON COLUMN mst.ui_label.description IS '[class:public] [null: optional context for translators] Where and how the string appears.';

CREATE TABLE mst.ui_label_translation (
    id          bigint GENERATED ALWAYS AS IDENTITY,
    ui_label_id bigint         NOT NULL,
    language_id bigint         NOT NULL,
    label_text  core.text_1000 NOT NULL,
    CONSTRAINT pk_ui_label_translation PRIMARY KEY (id),
    CONSTRAINT uq_ui_label_translation_ui_label_id_language_id UNIQUE (ui_label_id, language_id),
    CONSTRAINT fk_ui_label_translation_ui_label_id FOREIGN KEY (ui_label_id)
        REFERENCES mst.ui_label (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_ui_label_translation_language_id FOREIGN KEY (language_id)
        REFERENCES mst.language (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
CREATE INDEX idx_ui_label_translation_language_id ON mst.ui_label_translation (language_id);
SELECT core.add_audit_columns('mst.ui_label_translation');

COMMENT ON TABLE  mst.ui_label_translation IS 'One row per UI key and language. [lifecycle:hard_delete] [owner:team]';
COMMENT ON COLUMN mst.ui_label_translation.id IS '[class:public] Surrogate key.';
COMMENT ON COLUMN mst.ui_label_translation.ui_label_id IS '[class:public] Key being translated.';
COMMENT ON COLUMN mst.ui_label_translation.language_id IS '[class:public] Language of label_text.';
COMMENT ON COLUMN mst.ui_label_translation.label_text IS '[class:public] Text shown to users.';

-- ===========================================================================
-- Translation lookups with fallback to the default language (Rule 7)
-- ===========================================================================
CREATE FUNCTION mst.ref_code_display_name(p_ref_code_id bigint, p_language_iso varchar)
RETURNS varchar
LANGUAGE sql STABLE
AS $$
    SELECT t.display_name
    FROM mst.ref_code_translation t
    JOIN mst.language l ON l.id = t.language_id
    WHERE t.ref_code_id = p_ref_code_id
      AND (l.iso_code = p_language_iso OR l.is_default)
    ORDER BY (l.iso_code = p_language_iso) DESC
    LIMIT 1;
$$;
COMMENT ON FUNCTION mst.ref_code_display_name(bigint, varchar) IS
    'Display name in the requested language, falling back to the default language.';

CREATE FUNCTION mst.ui_label_text(p_label_key varchar, p_language_iso varchar)
RETURNS varchar
LANGUAGE sql STABLE
AS $$
    SELECT t.label_text
    FROM mst.ui_label k
    JOIN mst.ui_label_translation t ON t.ui_label_id = k.id
    JOIN mst.language l ON l.id = t.language_id
    WHERE k.label_key = p_label_key
      AND (l.iso_code = p_language_iso OR l.is_default)
    ORDER BY (l.iso_code = p_language_iso) DESC
    LIMIT 1;
$$;
COMMENT ON FUNCTION mst.ui_label_text(varchar, varchar) IS
    'UI string in the requested language, falling back to the default language. Never returns the key itself.';

-- ===========================================================================
-- Helper: add an enumeration column to any table
--
--   SELECT core.add_ref_code_column('job.application', 'application_status', 'APPLICATION_STATUS', false);
--
-- adds   application_status_code_type_id  bigint NOT NULL  (fixed to APPLICATION_STATUS)
--        application_status_ref_code_id   bigint [NOT] NULL
-- and a composite FK (code_type_id, ref_code_id) -> mst.ref_code (code_type_id, id),
-- so a column can only ever hold a value of its own enumeration.
-- ===========================================================================
CREATE FUNCTION core.add_ref_code_column(
    p_table       regclass,
    p_role        text,
    p_code_type   text,
    p_is_nullable boolean DEFAULT false,
    p_null_reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_table        text   := (SELECT relname FROM pg_class WHERE oid = p_table);
    v_code_type_id bigint;
    v_type_col     text   := p_role || '_code_type_id';
    v_value_col    text   := p_role || '_ref_code_id';
BEGIN
    SELECT id INTO v_code_type_id FROM mst.code_type WHERE code = p_code_type;
    IF v_code_type_id IS NULL THEN
        RAISE EXCEPTION 'code_type % does not exist; insert it into mst.code_type first', p_code_type;
    END IF;
    IF p_is_nullable AND p_null_reason IS NULL THEN
        RAISE EXCEPTION 'nullable enumeration %.% needs a null reason (Rule 5)', v_table, v_value_col;
    END IF;

    EXECUTE format(
        'ALTER TABLE %s ADD COLUMN %I bigint NOT NULL DEFAULT %s, ADD COLUMN %I bigint %s',
        p_table, v_type_col, v_code_type_id, v_value_col,
        CASE WHEN p_is_nullable THEN 'NULL' ELSE 'NOT NULL' END);

    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK (%I = %s)',
        p_table, left('ck_' || v_table || '_' || v_type_col, 63), v_type_col, v_code_type_id);

    EXECUTE format(
        'ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (%I, %I) REFERENCES mst.ref_code (code_type_id, id) '
        'ON UPDATE RESTRICT ON DELETE RESTRICT',
        p_table, left('fk_' || v_table || '_' || v_value_col, 63), v_type_col, v_value_col);

    EXECUTE format('COMMENT ON COLUMN %s.%I IS %L', p_table, v_type_col,
        format('[class:internal] Fixed to code_type %s; makes the composite FK type-safe.', p_code_type));
    EXECUTE format('COMMENT ON COLUMN %s.%I IS %L', p_table, v_value_col,
        format('[class:internal] %s[enum:%s] Value from mst.ref_code.',
               CASE WHEN p_is_nullable THEN '[null: ' || p_null_reason || '] ' ELSE '' END,
               p_code_type));
END $$;
COMMENT ON FUNCTION core.add_ref_code_column(regclass, text, text, boolean, text) IS
    'Adds a type-safe enumeration column pair with a composite FK to mst.ref_code.';

-- Read access for the application.
GRANT SELECT ON mst.language, mst.code_type, mst.ref_code, mst.ref_code_translation,
                mst.ui_label, mst.ui_label_translation TO talentra_app;

RESET ROLE;
