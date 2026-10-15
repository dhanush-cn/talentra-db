-- tools/lint_schema.sql
-- Schema compliance linter: checks the live database against the Section 5 data standards.
-- Run:  make lint      (fails the build if any ERROR row is returned)
--
-- Each row = one violation: rule group, severity, object, message.
-- ERROR rows must be fixed or recorded as a justified deviation in docs/deviations.md
-- and added to the allow-list at the bottom of this file.

\set QUIET on
\pset footer off

CREATE TEMP TABLE lint_result (rule_group text, severity text, object_name text, message text);

-- Objects in scope: tables and partitioned parents in module schemas (not partitions).
CREATE TEMP VIEW lint_table AS
SELECT c.oid, n.nspname AS schema_name, c.relname AS table_name,
       n.nspname || '.' || c.relname AS qualified_name,
       coalesce(obj_description(c.oid, 'pg_class'), '') AS table_comment
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND NOT c.relispartition
  AND n.nspname IN ('mst', 'prf', 'job', 'adm', 'org', 'gig', 'lic', 'src', 'pay', 'ntf', 'ana');

CREATE TEMP VIEW lint_column AS
SELECT t.oid AS table_oid, t.schema_name, t.table_name, t.qualified_name, t.table_comment,
       a.attname AS column_name, a.attnum, a.attnotnull AS is_not_null,
       a.atthasdef AS has_default, a.attgenerated <> '' AS is_generated,
       format_type(a.atttypid, a.atttypmod) AS declared_type,
       CASE WHEN ty.typtype = 'd' THEN tn.nspname || '.' || ty.typname END AS domain_name,
       format_type(coalesce(nullif(ty.typbasetype, 0), a.atttypid), NULL) AS base_type,
       coalesce(col_description(t.oid, a.attnum), '') AS column_comment
FROM lint_table t
JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum > 0 AND NOT a.attisdropped
JOIN pg_type ty ON ty.oid = a.atttypid
JOIN pg_namespace tn ON tn.oid = ty.typnamespace;

-- MySQL 8 reserved words most likely to collide with column names (Rule 1 reserved keyword check).
CREATE TEMP TABLE mysql_reserved (word text PRIMARY KEY);
INSERT INTO mysql_reserved VALUES
 ('accessible'),('add'),('all'),('alter'),('analyze'),('and'),('as'),('asc'),('before'),('between'),('both'),('by'),
 ('call'),('cascade'),('case'),('change'),('check'),('collate'),('column'),('condition'),('constraint'),('continue'),
 ('convert'),('create'),('cross'),('cube'),('cume_dist'),('current_date'),('current_time'),('current_timestamp'),
 ('current_user'),('cursor'),('database'),('databases'),('default'),('delayed'),('delete'),('dense_rank'),('desc'),
 ('describe'),('distinct'),('div'),('drop'),('dual'),('each'),('else'),('elseif'),('empty'),('enclosed'),('escaped'),
 ('except'),('exists'),('exit'),('explain'),('false'),('fetch'),('first_value'),('for'),('force'),('foreign'),('from'),
 ('fulltext'),('function'),('generated'),('get'),('grant'),('group'),('grouping'),('groups'),('having'),('if'),
 ('ignore'),('in'),('index'),('inner'),('inout'),('insert'),('int'),('interval'),('into'),('is'),('iterate'),('join'),
 ('json_table'),('key'),('keys'),('kill'),('lag'),('last_value'),('lateral'),('lead'),('leading'),('leave'),('left'),
 ('like'),('limit'),('linear'),('lines'),('load'),('localtime'),('localtimestamp'),('lock'),('long'),('loop'),('match'),
 ('maxvalue'),('mod'),('modifies'),('natural'),('not'),('nth_value'),('ntile'),('null'),('numeric'),('of'),('on'),
 ('optimize'),('option'),('optionally'),('or'),('order'),('out'),('outer'),('over'),('partition'),('percent_rank'),
 ('precision'),('primary'),('procedure'),('purge'),('range'),('rank'),('read'),('reads'),('real'),('recursive'),
 ('references'),('regexp'),('release'),('rename'),('repeat'),('replace'),('require'),('resignal'),('restrict'),
 ('return'),('revoke'),('right'),('rlike'),('row'),('row_number'),('rows'),('schema'),('schemas'),('select'),
 ('separator'),('set'),('show'),('signal'),('spatial'),('specific'),('sql'),('sqlexception'),('sqlstate'),
 ('sqlwarning'),('starting'),('stored'),('straight_join'),('system'),('table'),('terminated'),('then'),('to'),
 ('trailing'),('trigger'),('true'),('undo'),('union'),('unique'),('unlock'),('unsigned'),('update'),('usage'),('use'),
 ('using'),('utc_date'),('utc_time'),('utc_timestamp'),('values'),('varying'),('virtual'),('when'),('where'),
 ('while'),('window'),('with'),('write'),('xor'),('zerofill');

-- ---------------------------------------------------------------------------
-- Rule 1: naming conventions
-- ---------------------------------------------------------------------------
INSERT INTO lint_result
SELECT '1', 'ERROR', qualified_name, 'table name is not snake_case'
FROM lint_table WHERE table_name !~ '^[a-z][a-z0-9]*(_[a-z0-9]+)*$';

INSERT INTO lint_result
SELECT '1', 'WARN', qualified_name, 'table name may be plural; table names are singular nouns'
FROM lint_table
WHERE table_name ~ 's$' AND table_name !~ '(ss|us|is|status)$';

INSERT INTO lint_result
SELECT '1', 'ERROR', qualified_name || '.' || column_name, 'column name is not snake_case'
FROM lint_column WHERE column_name !~ '^[a-z][a-z0-9]*(_[a-z0-9]+)*$';

INSERT INTO lint_result
SELECT '1', 'ERROR', t.qualified_name, 'table name is a reserved word in PostgreSQL or MySQL'
FROM lint_table t
WHERE t.table_name IN (SELECT word FROM pg_get_keywords() WHERE catcode IN ('R', 'T'))
   OR t.table_name IN (SELECT word FROM mysql_reserved);

INSERT INTO lint_result
SELECT '1', 'ERROR', qualified_name || '.' || column_name, 'column name is a reserved word in PostgreSQL or MySQL'
FROM lint_column
WHERE column_name IN (SELECT word FROM pg_get_keywords() WHERE catcode IN ('R', 'T'))
   OR column_name IN (SELECT word FROM mysql_reserved);

-- Internal constraints PostgreSQL creates for foreign keys to partitioned tables (conparentid <> 0) are skipped.
-- Constraint names: pk_<table>, uq_<table>_..., fk_<table>_..., ck_<table>_..., ex_<table>_...
INSERT INTO lint_result
SELECT '1', 'ERROR', t.qualified_name || ' / ' || con.conname,
       format('constraint name must start with %s', expected)
FROM lint_table t
JOIN pg_constraint con ON con.conrelid = t.oid AND con.conparentid = 0
CROSS JOIN LATERAL (SELECT CASE con.contype
        WHEN 'p' THEN 'pk_' || t.table_name
        WHEN 'u' THEN 'uq_' || t.table_name || '_'
        WHEN 'f' THEN 'fk_' || t.table_name || '_'
        WHEN 'c' THEN 'ck_' || t.table_name || '_'
        WHEN 'x' THEN 'ex_' || t.table_name || '_'
    END AS expected) e
WHERE con.contype IN ('p', 'u', 'f', 'c', 'x')
  AND left(con.conname, length(e.expected)) <> left(e.expected, 63);

-- Index names: idx_<table>_... (or uq_<table>_... for unique indexes); constraint-backed indexes skipped.
INSERT INTO lint_result
SELECT '1', 'ERROR', t.qualified_name || ' / ' || ic.relname,
       'index name must start with idx_' || t.table_name || '_ (or uq_' || t.table_name || '_ if unique)'
FROM lint_table t
JOIN pg_index i ON i.indrelid = t.oid
JOIN pg_class ic ON ic.oid = i.indexrelid
WHERE NOT EXISTS (SELECT 1 FROM pg_constraint con WHERE con.conindid = i.indexrelid)
  AND ic.relname NOT LIKE 'idx\_' || replace(t.table_name, '_', '\_') || '\_%'
  AND NOT (i.indisunique AND ic.relname LIKE 'uq\_' || replace(t.table_name, '_', '\_') || '\_%');

-- ---------------------------------------------------------------------------
-- Rule 2: keys and constraints
-- ---------------------------------------------------------------------------
INSERT INTO lint_result
SELECT '2', 'ERROR', t.qualified_name, 'table has no primary key'
FROM lint_table t
WHERE NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = t.oid AND c.contype = 'p');

-- Partitioned tables (deviation D-04) may append their partition key: PRIMARY KEY (id, <partition key>).
INSERT INTO lint_result
SELECT '2', 'ERROR', t.qualified_name,
       'primary key must be the single bigint column "id" (partitioned tables: id followed by the partition key)'
FROM lint_table t
JOIN pg_class tc ON tc.oid = t.oid
JOIN pg_constraint c ON c.conrelid = t.oid AND c.contype = 'p'
WHERE t.schema_name <> 'ana'
  AND NOT (
        (SELECT attname FROM pg_attribute WHERE attrelid = t.oid AND attnum = c.conkey[1]) = 'id'
        AND (SELECT atttypid FROM pg_attribute WHERE attrelid = t.oid AND attnum = c.conkey[1]) = 'bigint'::regtype
        AND (array_length(c.conkey, 1) = 1
             OR (tc.relkind = 'p'
                 AND c.conkey[2:] <@ (SELECT pt.partattrs::int2[] FROM pg_partitioned_table pt WHERE pt.partrelid = t.oid)
                 AND (SELECT pt.partattrs::int2[] FROM pg_partitioned_table pt WHERE pt.partrelid = t.oid) <@ c.conkey[2:])));

-- Single-column FK columns end with <referenced_table>_id (a role prefix is allowed: parent_industry_id).
INSERT INTO lint_result
SELECT '2', 'ERROR', t.qualified_name || '.' || a.attname,
       format('foreign key column should end with %s_id', rt.relname)
FROM lint_table t
JOIN pg_constraint c ON c.conrelid = t.oid AND c.contype = 'f' AND c.conparentid = 0 AND array_length(c.conkey, 1) = 1
JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = c.conkey[1]
JOIN pg_class rt ON rt.oid = c.confrelid
WHERE a.attname NOT IN ('created_by', 'updated_by', 'deleted_by')
  AND a.attname NOT LIKE '%' || rt.relname || '_id';

-- Every FK states its delete rule explicitly (NO ACTION means nobody decided).
INSERT INTO lint_result
SELECT '2', 'ERROR', t.qualified_name || ' / ' || c.conname, 'foreign key has no stated ON DELETE rule (NO ACTION)'
FROM lint_table t
JOIN pg_constraint c ON c.conrelid = t.oid AND c.contype = 'f' AND c.conparentid = 0
WHERE c.confdeltype = 'a';

-- Foreign keys without a supporting index. References to master data that is never deleted
-- ([lifecycle:deactivate]) are skipped: an index there only serves deletes that cannot happen.
INSERT INTO lint_result
SELECT '2', 'WARN', t.qualified_name || ' / ' || c.conname, 'foreign key has no index starting with its column(s)'
FROM lint_table t
JOIN pg_constraint c ON c.conrelid = t.oid AND c.contype = 'f' AND c.conparentid = 0
WHERE coalesce(obj_description(c.confrelid, 'pg_class'), '') NOT LIKE '%[lifecycle:deactivate]%'
  AND (SELECT attname FROM pg_attribute WHERE attrelid = t.oid AND attnum = c.conkey[1])
        NOT IN ('created_by', 'updated_by', 'deleted_by')
  AND (SELECT attname FROM pg_attribute WHERE attrelid = t.oid AND attnum = c.conkey[1]) NOT LIKE '%_code_type_id'
  AND NOT EXISTS (
        SELECT 1 FROM pg_index i
        WHERE i.indrelid = t.oid
          AND (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] @> c.conkey
          AND (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] <@ c.conkey);

-- ---------------------------------------------------------------------------
-- Rule 3: standard domains
-- ---------------------------------------------------------------------------
INSERT INTO lint_result
SELECT '3', 'ERROR', qualified_name || '.' || column_name, 'floating point or money type is not allowed: use numeric or core.money_amount'
FROM lint_column WHERE base_type IN ('real', 'double precision', 'money');

INSERT INTO lint_result
SELECT '3', 'ERROR', qualified_name || '.' || column_name, 'timestamp without time zone: use timestamptz (stored in UTC)'
FROM lint_column WHERE base_type = 'timestamp without time zone';

INSERT INTO lint_result
SELECT '3', 'ERROR', qualified_name || '.' || column_name, 'money column must use domain core.money_amount'
FROM lint_column WHERE column_name ~ '_amount$' AND coalesce(domain_name, '') <> 'core.money_amount';

INSERT INTO lint_result
SELECT '3', 'ERROR', m.qualified_name || '.' || m.column_name,
       'money column has no companion currency column (currency_id or <prefix>_currency_id)'
FROM lint_column m
WHERE m.domain_name = 'core.money_amount'
  AND NOT EXISTS (SELECT 1 FROM lint_column c
                  WHERE c.table_oid = m.table_oid AND c.column_name ~ '(^|_)currency_id$');

INSERT INTO lint_result
SELECT '3', 'ERROR', qualified_name || '.' || column_name, 'unbounded text: use a core.text_* domain or core.long_text with an [unbounded: reason] tag'
FROM lint_column WHERE base_type = 'text' AND domain_name IS NULL;

INSERT INTO lint_result
SELECT '3', 'ERROR', qualified_name || '.' || column_name, 'core.long_text column needs an [unbounded: reason] tag in its comment'
FROM lint_column WHERE domain_name = 'core.long_text' AND column_comment !~ '\[unbounded:';

INSERT INTO lint_result
SELECT '3', 'ERROR', qualified_name || '.' || column_name, 'boolean flags must be NOT NULL with a default'
FROM lint_column WHERE base_type = 'boolean' AND (NOT is_not_null OR NOT has_default);

INSERT INTO lint_result
SELECT '3', 'ERROR', qualified_name || '.' || column_name, 'plain-text email column must use core.email_address'
FROM lint_column
WHERE column_name ~ '(^|_)email$' AND base_type = 'character varying'
  AND coalesce(domain_name, '') <> 'core.email_address';

INSERT INTO lint_result
SELECT '3', 'ERROR', qualified_name || '.' || column_name, 'plain-text phone column must use core.phone_e164'
FROM lint_column
WHERE column_name ~ '(^|_)phone(_number)?$' AND base_type = 'character varying'
  AND coalesce(domain_name, '') <> 'core.phone_e164';

-- ---------------------------------------------------------------------------
-- Rule 4: audit and lifecycle
-- ---------------------------------------------------------------------------
INSERT INTO lint_result
SELECT '4', 'ERROR', t.qualified_name, 'missing audit column ' || req.col
FROM lint_table t
CROSS JOIN (VALUES ('created_at'), ('created_by'), ('updated_at'), ('updated_by')) AS req(col)
WHERE t.schema_name <> 'ana'
  AND NOT (t.table_comment LIKE '%[lifecycle:append_only]%' AND req.col IN ('updated_at', 'updated_by'))
  AND NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = req.col AND NOT a.attisdropped);

INSERT INTO lint_result
SELECT '4', 'ERROR', t.qualified_name, 'table comment needs a [lifecycle:soft_delete|hard_delete|append_only|deactivate] tag'
FROM lint_table t
WHERE t.schema_name <> 'ana'
  AND t.table_comment !~ '\[lifecycle:(soft_delete|hard_delete|append_only|deactivate)\]';

INSERT INTO lint_result
SELECT '4', 'ERROR', t.qualified_name, 'append-only table is missing its blocking trigger'
FROM lint_table t
WHERE t.table_comment LIKE '%[lifecycle:append_only]%'
  AND NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid = t.oid AND g.tgname LIKE '%\_append\_only');

INSERT INTO lint_result
SELECT '4', 'ERROR', t.qualified_name, 'soft-delete table is missing deleted_at or its RLS policy'
FROM lint_table t
WHERE t.table_comment LIKE '%[lifecycle:soft_delete]%'
  AND (NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = 'deleted_at')
       OR NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = t.oid AND p.polname LIKE '%\_hide\_deleted'));

-- ---------------------------------------------------------------------------
-- Rule 5: nullability justification
-- ---------------------------------------------------------------------------
INSERT INTO lint_result
SELECT '5', 'ERROR', qualified_name || '.' || column_name, 'nullable column needs a [null: reason] tag in its comment'
FROM lint_column WHERE NOT is_not_null AND column_comment !~ '\[null:';

-- ---------------------------------------------------------------------------
-- Rule 6: sensitive data classification
-- ---------------------------------------------------------------------------
INSERT INTO lint_result
SELECT '6', 'ERROR', qualified_name || '.' || column_name, 'column comment needs a [class:public|internal|personal|sensitive] tag'
FROM lint_column WHERE column_comment !~ '\[class:(public|internal|personal|sensitive)\]';

INSERT INTO lint_result
SELECT '6', 'ERROR', qualified_name || '.' || column_name,
       'sensitive column stored as readable text: encrypt (bytea), tokenise (*_token) or hash (*_hash, *_hmac)'
FROM lint_column
WHERE column_comment LIKE '%[class:sensitive]%'
  AND base_type IN ('text', 'character varying')
  AND column_name !~ '(_token|_hash|_hmac|_masked|_last4)$';

-- ---------------------------------------------------------------------------
-- Rule 8: naming of physical objects (views, materialised views, analytics)
-- ---------------------------------------------------------------------------
INSERT INTO lint_result
SELECT '8', 'ERROR', n.nspname || '.' || c.relname,
       CASE c.relkind WHEN 'v' THEN 'view name must start with v_' ELSE 'materialized view name must start with mv_' END
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('mst', 'prf', 'job', 'adm', 'org', 'gig', 'lic', 'src', 'pay', 'ntf', 'ana')
  AND ((c.relkind = 'v' AND c.relname NOT LIKE 'v\_%') OR (c.relkind = 'm' AND c.relname NOT LIKE 'mv\_%'));

INSERT INTO lint_result
SELECT '8', 'ERROR', qualified_name, 'analytics tables must be prefixed dim_, fct_ or agg_'
FROM lint_table WHERE schema_name = 'ana' AND table_name !~ '^(dim|fct|agg)_';

-- Partitions: <parent>_p<yyyymm> (range by month) or <parent>_h<nn> (hash) or <parent>_default.
INSERT INTO lint_result
SELECT '8', 'ERROR', n.nspname || '.' || c.relname, 'partition name must be <parent>_pYYYYMM, <parent>_hNN or <parent>_default'
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_inherits i ON i.inhrelid = c.oid
JOIN pg_class p ON p.oid = i.inhparent
WHERE c.relispartition AND c.relkind IN ('r', 'p')
  AND c.relname !~ ('^' || p.relname || '_(p[0-9]{6}|h[0-9]{2}|default)$');

-- ---------------------------------------------------------------------------
-- Justified deviations (Rule: "a justified deviation is scored well").
-- Each entry must have a matching paragraph in docs/deviations.md.
-- ---------------------------------------------------------------------------
DELETE FROM lint_result r
USING (VALUES
    -- ('rule', 'object', 'reason recorded in docs/deviations.md')
    ('', '', '')
) AS allow(rule_group, object_name, reason)
WHERE r.rule_group = allow.rule_group AND r.object_name = allow.object_name;

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
\pset format aligned
SELECT rule_group AS rule, severity, object_name AS object, message
FROM lint_result
ORDER BY severity, rule_group, object_name;

SELECT count(*) FILTER (WHERE severity = 'ERROR') AS error_count,
       count(*) FILTER (WHERE severity = 'WARN')  AS warning_count,
       (SELECT count(*) FROM lint_table)         AS tables_checked,
       (SELECT count(*) FROM lint_column)        AS columns_checked
FROM lint_result \gset

\echo
\echo Tables checked: :tables_checked   Columns checked: :columns_checked
\echo Errors: :error_count   Warnings: :warning_count

SELECT (:error_count = 0) AS lint_passed \gset
\if :lint_passed
    \echo Schema lint PASSED
\else
    \echo Schema lint FAILED
    SELECT 'schema lint failed: fix the ERROR rows above' AS failure WHERE 1/0 = 1;
\endif
