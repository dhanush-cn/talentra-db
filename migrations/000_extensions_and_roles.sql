-- 000_extensions_and_roles.sql
-- Purpose : extensions, database roles and the per-module schemas.
-- Owner   : Dhanush (conventions)
-- Rule refs: Rule 1 (naming), Rule 8 (physical objects), Section 3 (privileges enforced in the DB)

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;    -- encryption, HMAC blind indexes, password hashing
CREATE EXTENSION IF NOT EXISTS pg_trgm;     -- fuzzy name matching, duplicate detection, search
CREATE EXTENSION IF NOT EXISTS btree_gist;  -- exclusion constraints mixing "=" and "&&" (no-overlap rules)

-- pg_stat_statements needs shared_preload_libraries; created only when it is preloaded
-- (docker-compose.yml preloads it; plain local installs may not).
DO $$
BEGIN
    IF current_setting('shared_preload_libraries') LIKE '%pg_stat_statements%' THEN
        CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Roles (cluster-wide, so created idempotently)
--   talentra_owner    owns every object; runs migrations. Never used by the application.
--   talentra_app      the application runtime. Subject to RLS. No UPDATE/DELETE on append-only tables.
--   talentra_readonly analytics and reporting; SELECT on the ana schema only.
--   talentra_auditor  read access to audit and history tables for compliance staff.
-- RLS does not apply to table owners or superusers, so every access test MUST run as talentra_app.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    r text;
BEGIN
    FOREACH r IN ARRAY ARRAY['talentra_owner', 'talentra_app', 'talentra_readonly', 'talentra_auditor']
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- Schemas: one per module (codes defined in docs/conventions.md)
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS core AUTHORIZATION talentra_owner;  -- shared domains, functions, triggers
CREATE SCHEMA IF NOT EXISTS mst  AUTHORIZATION talentra_owner;  -- Master data
CREATE SCHEMA IF NOT EXISTS prf  AUTHORIZATION talentra_owner;  -- Profile
CREATE SCHEMA IF NOT EXISTS job  AUTHORIZATION talentra_owner;  -- Jobs and Applications
CREATE SCHEMA IF NOT EXISTS adm  AUTHORIZATION talentra_owner;  -- Administration
CREATE SCHEMA IF NOT EXISTS org  AUTHORIZATION talentra_owner;  -- Organisation and account
CREATE SCHEMA IF NOT EXISTS gig  AUTHORIZATION talentra_owner;  -- Gig marketplace
CREATE SCHEMA IF NOT EXISTS lic  AUTHORIZATION talentra_owner;  -- Licences, seats, devices and sessions
CREATE SCHEMA IF NOT EXISTS src  AUTHORIZATION talentra_owner;  -- Sourcing and consultant requests
CREATE SCHEMA IF NOT EXISTS pay  AUTHORIZATION talentra_owner;  -- Subscriptions, wallet, payments, download history
CREATE SCHEMA IF NOT EXISTS ntf  AUTHORIZATION talentra_owner;  -- Notifications, preferences and community
CREATE SCHEMA IF NOT EXISTS ana  AUTHORIZATION talentra_owner;  -- Analytics layer and reporting marts

COMMENT ON SCHEMA core IS 'Shared standard domains, helper functions and triggers used by every module.';
COMMENT ON SCHEMA mst  IS 'Master data module.';
COMMENT ON SCHEMA prf  IS 'Profile module.';
COMMENT ON SCHEMA job  IS 'Jobs and Applications module.';
COMMENT ON SCHEMA adm  IS 'Administration module.';
COMMENT ON SCHEMA org  IS 'Organisation and account module.';
COMMENT ON SCHEMA gig  IS 'Gig marketplace module.';
COMMENT ON SCHEMA lic  IS 'Licences, seats, devices and sessions module.';
COMMENT ON SCHEMA src  IS 'Sourcing and consultant requests module.';
COMMENT ON SCHEMA pay  IS 'Subscriptions, wallet, payments and download history module.';
COMMENT ON SCHEMA ntf  IS 'Notifications, preferences and community module.';
COMMENT ON SCHEMA ana  IS 'Analytics layer and reporting marts (analytical objects only).';

-- Runtime roles can see the operational schemas; table-level grants are given per table.
GRANT USAGE ON SCHEMA core, mst, prf, job, adm, org, gig, lic, src, pay, ntf TO talentra_app;
GRANT USAGE ON SCHEMA ana TO talentra_readonly;
GRANT USAGE ON SCHEMA core, adm TO talentra_auditor;
