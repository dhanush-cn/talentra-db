-- 001_core_framework.sql
-- Purpose : standard domains (Rule 3), actor identity, audit columns (Rule 4),
--           append-only enforcement (Rules 4 and 10) and soft-delete helpers.
-- Owner   : Dhanush (conventions)
-- Every module calls these helpers instead of hand-writing the same DDL.

SET ROLE talentra_owner;

-- ===========================================================================
-- 1. Standard domains (Rule group 3)
--    Each domain enforces its rule wherever it is used, so a column cannot
--    silently drift from the standard. Rule 5 sentinels ('', 'NA', 'N/A',
--    'NULL', 'NONE', '-') are rejected by every text domain.
-- ===========================================================================

CREATE FUNCTION core.is_sentinel(p_value text)
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT btrim(p_value) = ''
        OR upper(btrim(p_value)) IN ('NA', 'N/A', 'N.A.', 'NULL', 'NONE', 'NIL', '-', '--');
$$;
COMMENT ON FUNCTION core.is_sentinel(text) IS
    'True for values that would mean "missing" (Rule 5). Missing data must be NULL plus a reason, never a sentinel.';

-- Person name: up to 150 characters, any script, no assumption about word order.
CREATE DOMAIN core.person_name AS varchar(150)
    CHECK (NOT core.is_sentinel(VALUE) AND VALUE = btrim(VALUE));

-- Bounded free text. Pick the smallest that fits; the length is the stated maximum.
CREATE DOMAIN core.text_100  AS varchar(100)  CHECK (NOT core.is_sentinel(VALUE));
CREATE DOMAIN core.text_255  AS varchar(255)  CHECK (NOT core.is_sentinel(VALUE));
CREATE DOMAIN core.text_1000 AS varchar(1000) CHECK (NOT core.is_sentinel(VALUE));
CREATE DOMAIN core.text_4000 AS varchar(4000) CHECK (NOT core.is_sentinel(VALUE));
-- Unbounded text: only for job descriptions, resume bodies and similar.
-- Every column using it must carry an [unbounded: reason] tag in its comment (checked by the linter).
CREATE DOMAIN core.long_text AS text          CHECK (NOT core.is_sentinel(VALUE));

-- Email: up to 254 characters, stored lowercase.
CREATE DOMAIN core.email_address AS varchar(254)
    CHECK (VALUE = lower(VALUE) AND VALUE ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$');

-- Phone: E.164 with country code. The country is a separate column (country_id).
CREATE DOMAIN core.phone_e164 AS varchar(16)
    CHECK (VALUE ~ '^\+[1-9][0-9]{6,14}$');

-- Money: fixed precision, never floating point. Always paired with a currency_id column.
CREATE DOMAIN core.money_amount AS numeric(18, 2);

-- Percentage 0–100 and ratio 0–1.
CREATE DOMAIN core.percentage AS numeric(5, 2) CHECK (VALUE BETWEEN 0 AND 100);
CREATE DOMAIN core.ratio      AS numeric(7, 6) CHECK (VALUE BETWEEN 0 AND 1);

-- Coordinates: 6 decimal places (about 0.11 m). Source recorded in a coordinate_source code column.
CREATE DOMAIN core.latitude  AS numeric(9, 6) CHECK (VALUE BETWEEN -90 AND 90);
CREATE DOMAIN core.longitude AS numeric(9, 6) CHECK (VALUE BETWEEN -180 AND 180);

-- Machine codes and keys.
CREATE DOMAIN core.code      AS varchar(50)  CHECK (VALUE ~ '^[A-Z][A-Z0-9_]*$');
CREATE DOMAIN core.label_key AS varchar(150) CHECK (VALUE ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$');
CREATE DOMAIN core.iana_time_zone AS varchar(64) CHECK (VALUE ~ '^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$');

-- Counts and limits (Rule 9: licence limits are positive integers).
CREATE DOMAIN core.positive_int     AS integer CHECK (VALUE > 0);
CREATE DOMAIN core.non_negative_int AS integer CHECK (VALUE >= 0);

-- Sort order for lookup tables.
CREATE DOMAIN core.sort_order AS smallint CHECK (VALUE >= 0);

-- ===========================================================================
-- 2. Actor identity
--    Every session must say who is acting (SET app.user_id = '<id>').
--    The application does this per transaction with SET LOCAL; seed and
--    migration scripts use the system account (id 1).
--    No actor = the write fails. This is what makes created_by/updated_by trustworthy.
-- ===========================================================================

CREATE FUNCTION core.current_actor_id()
RETURNS bigint
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_raw text := current_setting('app.user_id', true);
BEGIN
    IF v_raw IS NULL OR v_raw = '' THEN
        RAISE EXCEPTION 'app.user_id is not set: every session must identify its actor'
            USING ERRCODE = 'insufficient_privilege',
                  HINT = 'Run SET LOCAL app.user_id = ''<user_account id>'' at the start of the transaction.';
    END IF;
    RETURN v_raw::bigint;
END $$;
COMMENT ON FUNCTION core.current_actor_id() IS
    'Acting user for audit columns and RLS. Raises if the session has not set app.user_id.';

-- ===========================================================================
-- 3. Audit columns (Rule group 4)
--    core.add_audit_columns(table) adds created_at/by and updated_at/by and a
--    trigger that keeps them correct. created_* can never be changed after insert.
--    Foreign keys from created_by/updated_by to adm.user_account are attached
--    later by core.attach_audit_foreign_keys(), once the Administration module exists.
-- ===========================================================================

CREATE FUNCTION core.trg_set_audit_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := now();
        NEW.created_by := coalesce(NEW.created_by, core.current_actor_id());
        NEW.updated_at := NEW.created_at;
        NEW.updated_by := NEW.created_by;
    ELSE
        NEW.created_at := OLD.created_at;      -- creation facts are immutable
        NEW.created_by := OLD.created_by;
        NEW.updated_at := now();
        NEW.updated_by := core.current_actor_id();
    END IF;
    RETURN NEW;
END $$;

CREATE FUNCTION core.add_audit_columns(p_table regclass)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_table text := (SELECT relname FROM pg_class WHERE oid = p_table);
BEGIN
    EXECUTE format($f$
        ALTER TABLE %1$s
            ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
            ADD COLUMN IF NOT EXISTS created_by bigint      NOT NULL DEFAULT core.current_actor_id(),
            ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
            ADD COLUMN IF NOT EXISTS updated_by bigint      NOT NULL DEFAULT core.current_actor_id()
    $f$, p_table);

    EXECUTE format('COMMENT ON COLUMN %s.created_at IS %L', p_table, '[class:internal] When the row was created (UTC).');
    EXECUTE format('COMMENT ON COLUMN %s.created_by IS %L', p_table, '[class:internal] user_account that created the row.');
    EXECUTE format('COMMENT ON COLUMN %s.updated_at IS %L', p_table, '[class:internal] When the row was last changed (UTC).');
    EXECUTE format('COMMENT ON COLUMN %s.updated_by IS %L', p_table, '[class:internal] user_account that last changed the row.');

    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s', 'trg_' || v_table || '_audit', p_table);
    EXECUTE format(
        'CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION core.trg_set_audit_columns()',
        'trg_' || v_table || '_audit', p_table);
END $$;
COMMENT ON FUNCTION core.add_audit_columns(regclass) IS
    'Adds the four Rule 4 audit columns and the trigger that maintains them.';

-- Append-only tables (audit trail, ledgers, download/view history) have no updated_* columns:
-- they are never updated. They get created_at/created_by only.
CREATE FUNCTION core.add_creation_columns(p_table regclass)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format($f$
        ALTER TABLE %1$s
            ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
            ADD COLUMN IF NOT EXISTS created_by bigint      NOT NULL DEFAULT core.current_actor_id()
    $f$, p_table);
    EXECUTE format('COMMENT ON COLUMN %s.created_at IS %L', p_table, '[class:internal] When the row was recorded (UTC).');
    EXECUTE format('COMMENT ON COLUMN %s.created_by IS %L', p_table, '[class:internal] user_account that recorded the row.');
END $$;

-- ===========================================================================
-- 4. Append-only enforcement (Rule 4 audit, Rule 10 ledgers and history)
--    Two independent layers:
--      a) privilege: talentra_app is never granted UPDATE or DELETE;
--      b) trigger: rejects UPDATE, DELETE and TRUNCATE even for privileged roles.
--    A correction is a new row that references the original.
-- ===========================================================================

CREATE FUNCTION core.trg_reject_modification()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION '% on %.% is not allowed: the table is append-only',
        TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME
        USING ERRCODE = 'insufficient_privilege',
              HINT = 'Record a correction as a new entry that references the original.';
END $$;

CREATE FUNCTION core.make_append_only(p_table regclass)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_table text := (SELECT relname FROM pg_class WHERE oid = p_table);
BEGIN
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s', 'trg_' || v_table || '_append_only', p_table);
    EXECUTE format(
        'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION core.trg_reject_modification()',
        'trg_' || v_table || '_append_only', p_table);

    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s', 'trg_' || v_table || '_no_truncate', p_table);
    EXECUTE format(
        'CREATE TRIGGER %I BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION core.trg_reject_modification()',
        'trg_' || v_table || '_no_truncate', p_table);

    EXECUTE format('REVOKE UPDATE, DELETE, TRUNCATE ON %s FROM talentra_app', p_table);
    EXECUTE format('GRANT SELECT, INSERT ON %s TO talentra_app', p_table);

    EXECUTE format('COMMENT ON TABLE %s IS %L', p_table,
        coalesce(obj_description(p_table, 'pg_class') || ' ', '') || '[lifecycle:append_only]');
END $$;
COMMENT ON FUNCTION core.make_append_only(regclass) IS
    'Makes a table append-only: trigger blocks UPDATE/DELETE/TRUNCATE; talentra_app gets SELECT and INSERT only.';

-- ===========================================================================
-- 5. Soft delete (Rule 4)
--    Adds deleted_at/deleted_by and a RESTRICTIVE row-level-security policy so
--    the application role never sees deleted rows by default. Restrictive means
--    it is ANDed with every other policy (company scoping, blocking) the module adds.
--    Hard-deleted tables simply never call this.
-- ===========================================================================

CREATE FUNCTION core.enable_soft_delete(p_table regclass)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_table text := (SELECT relname FROM pg_class WHERE oid = p_table);
BEGIN
    EXECUTE format($f$
        ALTER TABLE %1$s
            ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
            ADD COLUMN IF NOT EXISTS deleted_by bigint,
            ADD CONSTRAINT %2$I CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
    $f$, p_table, 'ck_' || v_table || '_deleted_pair');

    EXECUTE format('COMMENT ON COLUMN %s.deleted_at IS %L', p_table,
        '[class:internal] [null: row is live] When the row was soft-deleted (UTC).');
    EXECUTE format('COMMENT ON COLUMN %s.deleted_by IS %L', p_table,
        '[class:internal] [null: row is live] user_account that soft-deleted the row.');

    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', p_table);

    -- RLS denies everything unless at least one PERMISSIVE policy matches. This baseline
    -- allows all live rows. A module that adds its own scoping policy (company, blocking)
    -- MUST drop pol_<table>_default_allow, otherwise "true OR scope" disables the scoping.
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = p_table AND polpermissive) THEN
        EXECUTE format('CREATE POLICY %I ON %s AS PERMISSIVE FOR ALL TO talentra_app USING (true) WITH CHECK (true)',
            'pol_' || v_table || '_default_allow', p_table);
    END IF;

    -- Reads never see deleted rows.
    EXECUTE format('DROP POLICY IF EXISTS %I ON %s', 'pol_' || v_table || '_hide_deleted', p_table);
    EXECUTE format(
        'CREATE POLICY %I ON %s AS RESTRICTIVE FOR SELECT TO talentra_app USING (deleted_at IS NULL)',
        'pol_' || v_table || '_hide_deleted', p_table);
    -- Updates may only touch live rows, but the new row may be deleted (that is how a soft delete happens).
    EXECUTE format('DROP POLICY IF EXISTS %I ON %s', 'pol_' || v_table || '_update_live', p_table);
    EXECUTE format(
        'CREATE POLICY %I ON %s AS RESTRICTIVE FOR UPDATE TO talentra_app USING (deleted_at IS NULL) WITH CHECK (true)',
        'pol_' || v_table || '_update_live', p_table);
    -- The application never hard-deletes a soft-delete table.
    EXECUTE format('REVOKE DELETE, TRUNCATE ON %s FROM talentra_app', p_table);

    EXECUTE format('COMMENT ON TABLE %s IS %L', p_table,
        coalesce(obj_description(p_table, 'pg_class') || ' ', '') || '[lifecycle:soft_delete]');
END $$;
COMMENT ON FUNCTION core.enable_soft_delete(regclass) IS
    'Adds deleted_at/deleted_by and a restrictive RLS policy hiding deleted rows from talentra_app.';

-- ===========================================================================
-- 6. Late-bound audit foreign keys
--    Called once adm.user_account exists (Administration module migration).
--    NOT VALID skips re-checking existing rows; new rows are checked.
-- ===========================================================================

CREATE FUNCTION core.attach_audit_foreign_keys()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
    v_count integer := 0;
BEGIN
    IF to_regclass('adm.user_account') IS NULL THEN
        RAISE EXCEPTION 'adm.user_account does not exist yet';
    END IF;

    FOR r IN
        SELECT c.table_schema, c.table_name, c.column_name, t.relkind
        FROM information_schema.columns c
        JOIN pg_class t ON t.relname = c.table_name
        JOIN pg_namespace n ON n.oid = t.relnamespace AND n.nspname = c.table_schema
        WHERE c.column_name IN ('created_by', 'updated_by', 'deleted_by')
          AND c.table_schema IN ('mst', 'prf', 'job', 'adm', 'org', 'gig', 'lic', 'src', 'pay', 'ntf')
          AND t.relkind IN ('r', 'p')
          AND NOT t.relispartition
          AND NOT EXISTS (
                SELECT 1 FROM information_schema.key_column_usage k
                JOIN information_schema.table_constraints tc
                  ON tc.constraint_name = k.constraint_name AND tc.constraint_schema = k.constraint_schema
                WHERE tc.constraint_type = 'FOREIGN KEY'
                  AND k.table_schema = c.table_schema AND k.table_name = c.table_name
                  AND k.column_name = c.column_name)
    LOOP
        EXECUTE format(
            'ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES adm.user_account (id) '
            'ON UPDATE RESTRICT ON DELETE RESTRICT' || CASE WHEN r.relkind = 'p' THEN '' ELSE ' NOT VALID' END,
            r.table_schema, r.table_name,
            left('fk_' || r.table_name || '_' || r.column_name, 63),
            r.column_name);
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END $$;

RESET ROLE;
