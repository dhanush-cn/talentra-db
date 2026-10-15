-- 999_attach_audit_foreign_keys.sql
-- Purpose : runs last, after every module. Points every created_by / updated_by /
--           deleted_by column at adm.user_account (Rule 2: every foreign key enforced).
--           Idempotent: only adds constraints that are missing.
-- Owner   : Dhanush (core)

SET ROLE talentra_owner;
SELECT core.attach_audit_foreign_keys();
RESET ROLE;
