\set ON_ERROR_STOP on
\pset pager off

SET ROLE macsad_owner;
BEGIN TRANSACTION READ ONLY;

DO $verify$
DECLARE
  bad_count bigint;
  ledger_count bigint;
  ledger_max bigint;
  database_owner name;
  approved_api oid[];
  api_schema_version bigint;
  expected_api record;
  actual_api record;
BEGIN
  IF current_setting('server_version_num')::integer < 160000
     OR current_setting('server_version_num')::integer >= 170000 THEN
    RAISE EXCEPTION 'MaCSad requires PostgreSQL 16; found %', version();
  END IF;

  SELECT pg_get_userbyid(datdba)
  INTO database_owner
  FROM pg_database
  WHERE datname = current_database();

  IF database_owner IS DISTINCT FROM 'macsad_owner'::name THEN
    RAISE EXCEPTION 'database % is owned by %, expected macsad_owner', current_database(), database_owner;
  END IF;

  SELECT count(*) INTO bad_count
  FROM (VALUES
    ('macsad_owner'::name, false, false),
    ('macsad_migrator'::name, false, false),
    ('macsad_app'::name, false, false),
    ('macsad_reader'::name, false, false),
    ('alejandro'::name, true, false),
    ('macsad_deployer'::name, true, false),
    ('macsad_runtime'::name, true, true),
    ('macsad_viewer'::name, true, true)
  ) AS expected(role_name, can_login, can_inherit)
  LEFT JOIN pg_roles AS actual ON actual.rolname = expected.role_name
  WHERE actual.oid IS NULL
     OR actual.rolcanlogin IS DISTINCT FROM expected.can_login
     OR actual.rolsuper
     OR actual.rolcreatedb
     OR actual.rolcreaterole
     OR actual.rolreplication
     OR actual.rolbypassrls
     OR actual.rolinherit IS DISTINCT FROM expected.can_inherit;

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'required role attributes are missing or unsafe';
  END IF;

  IF NOT pg_has_role('alejandro', 'macsad_owner', 'MEMBER')
     OR NOT pg_has_role('alejandro', 'macsad_migrator', 'MEMBER')
     OR NOT pg_has_role('macsad_deployer', 'macsad_owner', 'MEMBER')
     OR NOT pg_has_role('macsad_deployer', 'macsad_migrator', 'MEMBER')
     OR NOT pg_has_role('macsad_migrator', 'macsad_owner', 'MEMBER') THEN
    RAISE EXCEPTION 'migration role membership graph is incomplete';
  END IF;

  SELECT count(*) INTO bad_count
  FROM (VALUES
    ('alejandro'::name, 'macsad_migrator'::name),
    ('macsad_deployer'::name, 'macsad_migrator'::name),
    ('macsad_migrator'::name, 'macsad_owner'::name)
  ) AS expected(member_name, role_name)
  LEFT JOIN pg_auth_members AS membership
    ON pg_get_userbyid(membership.member) = expected.member_name
   AND pg_get_userbyid(membership.roleid) = expected.role_name
  WHERE membership.oid IS NULL
     OR membership.admin_option
     OR membership.inherit_option
     OR NOT membership.set_option;

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'migration memberships must be SET-only, non-inherited, and non-admin';
  END IF;

  SELECT count(*) INTO bad_count
  FROM (VALUES
    ('macsad_runtime'::name, 'macsad_app'::name),
    ('macsad_viewer'::name, 'macsad_reader'::name)
  ) AS expected(member_name, role_name)
  LEFT JOIN pg_auth_members AS membership
    ON pg_get_userbyid(membership.member) = expected.member_name
   AND pg_get_userbyid(membership.roleid) = expected.role_name
  WHERE membership.oid IS NULL
     OR membership.admin_option
     OR NOT membership.inherit_option
     OR membership.set_option;

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'service memberships must be inherited, non-settable, and non-admin';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_auth_members AS membership
  WHERE (
      pg_get_userbyid(membership.roleid) = 'macsad_owner'
      AND pg_get_userbyid(membership.member) <> 'macsad_migrator'
    )
     OR (
      pg_get_userbyid(membership.roleid) = 'macsad_migrator'
      AND pg_get_userbyid(membership.member) NOT IN ('alejandro', 'macsad_deployer')
    )
     OR (
      pg_get_userbyid(membership.roleid) = 'macsad_app'
      AND pg_get_userbyid(membership.member) <> 'macsad_runtime'
    )
     OR (
      pg_get_userbyid(membership.roleid) = 'macsad_reader'
      AND pg_get_userbyid(membership.member) <> 'macsad_viewer'
    )
     OR pg_get_userbyid(membership.roleid) IN (
      'alejandro', 'macsad_deployer', 'macsad_runtime', 'macsad_viewer'
    )
     OR (
      pg_get_userbyid(membership.member) IN (
        'alejandro', 'macsad_deployer', 'macsad_runtime', 'macsad_viewer'
      )
      AND NOT (
        (pg_get_userbyid(membership.member) = 'alejandro'
          AND pg_get_userbyid(membership.roleid) = 'macsad_migrator')
        OR (pg_get_userbyid(membership.member) = 'macsad_deployer'
          AND pg_get_userbyid(membership.roleid) = 'macsad_migrator')
        OR (pg_get_userbyid(membership.member) = 'macsad_runtime'
          AND pg_get_userbyid(membership.roleid) = 'macsad_app')
        OR (pg_get_userbyid(membership.member) = 'macsad_viewer'
          AND pg_get_userbyid(membership.roleid) = 'macsad_reader')
      )
    );

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'an unexpected role can administer or migrate MaCSad';
  END IF;

  WITH expected(role_name, database_scope, setting) AS (
    VALUES
      ('<database>', current_database(), 'search_path=pg_catalog'),
      ('macsad_owner', current_database(), 'search_path=macsad, macsad_meta, pg_catalog'),
      ('macsad_migrator', current_database(), 'search_path=macsad, macsad_meta, pg_catalog'),
      ('macsad_app', current_database(), 'search_path=macsad, pg_catalog'),
      ('macsad_reader', current_database(), 'search_path=macsad, pg_catalog'),
      ('alejandro', current_database(), 'search_path=pg_catalog'),
      ('macsad_deployer', current_database(), 'search_path=pg_catalog'),
      ('macsad_runtime', current_database(), 'search_path=macsad, pg_catalog'),
      ('macsad_viewer', current_database(), 'search_path=macsad, pg_catalog'),
      ('macsad_viewer', current_database(), 'default_transaction_read_only=on'),
      ('macsad_viewer', current_database(), 'statement_timeout=30s'),
      ('macsad_viewer', current_database(), 'lock_timeout=5s'),
      ('macsad_viewer', current_database(), 'idle_in_transaction_session_timeout=30s')
  ), actual AS (
    SELECT
      COALESCE(role_record.rolname::text, '<database>') AS role_name,
      COALESCE(database_record.datname::text, '<all>') AS database_scope,
      setting
    FROM pg_db_role_setting AS role_setting
    LEFT JOIN pg_roles AS role_record ON role_record.oid = role_setting.setrole
    LEFT JOIN pg_database AS database_record ON database_record.oid = role_setting.setdatabase
    CROSS JOIN LATERAL unnest(role_setting.setconfig) AS setting
    WHERE (
      role_setting.setdatabase = (
        SELECT oid FROM pg_database WHERE datname = current_database()
      )
      AND (
        role_setting.setrole = 0
        OR role_record.rolname IN (
          'macsad_owner', 'macsad_migrator', 'macsad_app', 'macsad_reader',
          'alejandro', 'macsad_deployer', 'macsad_runtime', 'macsad_viewer'
        )
      )
    )
       OR (
         role_setting.setdatabase = 0
         AND role_record.rolname IN (
           'macsad_owner', 'macsad_migrator', 'macsad_app', 'macsad_reader',
           'alejandro', 'macsad_deployer', 'macsad_runtime', 'macsad_viewer'
         )
       )
  )
  SELECT count(*) INTO bad_count
  FROM (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) AS setting_drift;

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'MaCSad role or database settings have drifted';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_namespace
  WHERE nspname IN ('macsad', 'macsad_meta')
    AND pg_get_userbyid(nspowner) <> 'macsad_owner';

  IF bad_count <> 0
     OR to_regnamespace('macsad') IS NULL
     OR to_regnamespace('macsad_meta') IS NULL THEN
    RAISE EXCEPTION 'MaCSad schemas are missing or have the wrong owner';
  END IF;

  IF NOT has_schema_privilege('macsad_app', 'macsad', 'USAGE')
     OR has_schema_privilege('macsad_app', 'macsad', 'CREATE')
     OR has_schema_privilege('macsad_app', 'macsad_meta', 'USAGE')
     OR NOT has_schema_privilege('macsad_reader', 'macsad', 'USAGE')
     OR has_schema_privilege('macsad_reader', 'macsad', 'CREATE') THEN
    RAISE EXCEPTION 'application or reader schema grants have drifted';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_database AS d
  CROSS JOIN LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) AS acl
  WHERE d.datname = current_database()
    AND acl.grantee = 0
    AND acl.privilege_type IN ('CONNECT', 'TEMPORARY', 'CREATE');

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'PUBLIC retains privileges on database %', current_database();
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_namespace AS n
  CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) AS acl
  WHERE n.nspname = 'public'
    AND acl.grantee = 0
    AND acl.privilege_type IN ('USAGE', 'CREATE');

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'PUBLIC retains USAGE or CREATE on schema public';
  END IF;

  IF (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'public')
       IS DISTINCT FROM 'pg_database_owner'::name THEN
    RAISE EXCEPTION 'schema public is not owned by pg_database_owner';
  END IF;

  SELECT count(*) INTO bad_count
  FROM (
    SELECT c.oid
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
    UNION ALL
    SELECT p.oid
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
    UNION ALL
    SELECT t.oid
    FROM pg_type AS t
    JOIN pg_namespace AS n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typtype IN ('c', 'd', 'e', 'm', 'r')
  ) AS public_object;

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'objects exist in schema public';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_constraint AS constraint_record
  JOIN pg_namespace AS n ON n.oid = constraint_record.connamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND NOT constraint_record.convalidated;

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% MaCSad constraint(s) are NOT VALID', bad_count;
  END IF;

  SELECT count(*) INTO bad_count
  FROM (
    SELECT pg_get_userbyid(c.relowner) AS owner_name
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('macsad', 'macsad_meta')
      AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
    UNION ALL
    SELECT pg_get_userbyid(p.proowner)
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('macsad', 'macsad_meta')
    UNION ALL
    SELECT pg_get_userbyid(t.typowner)
    FROM pg_type AS t
    JOIN pg_namespace AS n ON n.oid = t.typnamespace
    WHERE n.nspname IN ('macsad', 'macsad_meta')
      AND t.typtype IN ('c', 'd', 'e', 'm', 'r')
  ) AS owned_object
  WHERE owner_name <> 'macsad_owner';

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% MaCSad object(s) are not owned by macsad_owner', bad_count;
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault(CASE c.relkind WHEN 'S' THEN 's'::"char" ELSE 'r'::"char" END, c.relowner))) AS acl
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND acl.grantee = 0;

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'PUBLIC retains privileges on MaCSad relations';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) AS acl
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND acl.grantee = 0
    AND acl.privilege_type = 'EXECUTE';

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'PUBLIC retains EXECUTE on MaCSad routines';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND (
      has_table_privilege('macsad_app', c.oid, 'DELETE')
      OR has_table_privilege('macsad_app', c.oid, 'TRUNCATE')
      OR has_table_privilege('macsad_app', c.oid, 'REFERENCES')
      OR has_table_privilege('macsad_app', c.oid, 'TRIGGER')
    );

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'macsad_app has destructive relation privileges';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'macsad'
    AND c.relkind IN ('v', 'm')
    AND (
      has_table_privilege('macsad_app', c.oid, 'INSERT')
      OR has_table_privilege('macsad_app', c.oid, 'UPDATE')
    );

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'macsad_app has a write privilege on a read-model view';
  END IF;

  IF has_table_privilege('macsad_app', 'macsad.budget_entry', 'INSERT')
     OR has_table_privilege('macsad_app', 'macsad.budget_entry', 'UPDATE')
     OR has_table_privilege('macsad_app', 'macsad.budget_entry', 'DELETE')
     OR has_table_privilege('macsad_app', 'macsad.budget_account', 'UPDATE') THEN
    RAISE EXCEPTION 'macsad_app can bypass the budget ledger API';
  END IF;

  IF has_table_privilege('macsad_app', 'macsad.audit_stream', 'INSERT')
     OR has_table_privilege('macsad_app', 'macsad.audit_stream', 'UPDATE')
     OR has_table_privilege('macsad_app', 'macsad.audit_stream', 'DELETE') THEN
    RAISE EXCEPTION 'macsad_app can bypass the serialized audit stream API';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_attribute AS attribute
  WHERE attribute.attrelid = 'macsad.tool_repository_revision'::regclass
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped
    AND has_column_privilege(
      'macsad_app', attribute.attrelid, attribute.attname, 'UPDATE'
    ) IS DISTINCT FROM (
      attribute.attname = ANY(ARRAY[
        'operation_count', 'operation_catalog_digest',
        'operations_sealed_by_actor_id', 'operations_sealed_at'
      ]::name[])
    );

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'tool revision sealing column grants have drifted';
  END IF;

  SELECT count(*) INTO bad_count
  FROM unnest(ARRAY[
    'workspace_snapshot', 'tool_operation_manifest',
    'policy_member_profile', 'policy_process', 'policy_node', 'policy_transition',
    'policy_node_tool_operation', 'problem_revision', 'research_case_tool_revision',
    'task_transition', 'message', 'message_mention', 'blob', 'artifact',
    'execution_artifact', 'claim', 'attestation', 'attestation_artifact',
    'model_usage_observation', 'budget_entry', 'publication_dossier',
    'publication_item', 'domain_event'
  ]::text[]) AS immutable(table_name)
  WHERE has_table_privilege(
      'macsad_app', pg_catalog.to_regclass(pg_catalog.format('macsad.%I', table_name)), 'UPDATE')
     OR has_table_privilege(
      'macsad_app', pg_catalog.to_regclass(pg_catalog.format('macsad.%I', table_name)), 'DELETE')
     OR NOT EXISTS (
       SELECT 1
       FROM pg_trigger AS trigger_record
       WHERE trigger_record.tgrelid = pg_catalog.to_regclass(pg_catalog.format('macsad.%I', table_name))
         AND trigger_record.tgfoid = 'macsad.reject_mutation()'::regprocedure
         AND NOT trigger_record.tgisinternal
         AND trigger_record.tgenabled IN ('O', 'A')
          AND pg_get_triggerdef(trigger_record.oid, true) LIKE '%BEFORE%UPDATE%'
          AND pg_get_triggerdef(trigger_record.oid, true) LIKE '%BEFORE%DELETE%'
     );

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% immutable table(s) lack grant or trigger protection', bad_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger AS trigger_record
    WHERE trigger_record.tgrelid = 'macsad_meta.schema_migration'::regclass
      AND trigger_record.tgfoid = 'macsad.reject_mutation()'::regprocedure
      AND NOT trigger_record.tgisinternal
      AND trigger_record.tgenabled IN ('O', 'A')
      AND pg_get_triggerdef(trigger_record.oid, true) LIKE '%BEFORE%UPDATE%'
      AND pg_get_triggerdef(trigger_record.oid, true) LIKE '%BEFORE%DELETE%'
  ) THEN
    RAISE EXCEPTION 'migration ledger lacks append-only trigger protection';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND c.relkind IN ('r', 'p')
    AND NOT EXISTS (
      SELECT 1
      FROM pg_trigger AS trigger_record
      WHERE trigger_record.tgrelid = c.oid
        AND trigger_record.tgfoid = 'macsad.reject_mutation()'::regprocedure
        AND NOT trigger_record.tgisinternal
        AND trigger_record.tgenabled IN ('O', 'A')
        AND pg_get_triggerdef(trigger_record.oid, true) LIKE '%DELETE%'
    );

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% table(s) lack no-delete lifecycle protection', bad_count;
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND (
      has_table_privilege('macsad_reader', c.oid, 'INSERT')
      OR has_table_privilege('macsad_reader', c.oid, 'UPDATE')
      OR has_table_privilege('macsad_reader', c.oid, 'DELETE')
      OR has_table_privilege('macsad_reader', c.oid, 'TRUNCATE')
      OR has_table_privilege('macsad_reader', c.oid, 'REFERENCES')
      OR has_table_privilege('macsad_reader', c.oid, 'TRIGGER')
    );

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'macsad_reader has a write-capable relation privilege';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'macsad'
    AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND (
      NOT has_table_privilege('macsad_app', c.oid, 'SELECT')
      OR NOT has_table_privilege('macsad_reader', c.oid, 'SELECT')
    );

  IF bad_count <> 0
     OR NOT has_table_privilege('macsad_reader', 'macsad_meta.schema_migration', 'SELECT') THEN
    RAISE EXCEPTION 'required application or reader SELECT grants are missing';
  END IF;

  IF to_regclass('macsad.schema_version_v') IS NULL
     OR NOT has_table_privilege('macsad_app', 'macsad.schema_version_v', 'SELECT') THEN
    RAISE EXCEPTION 'application schema compatibility view or grant is missing';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'macsad'
    AND c.relkind IN ('r', 'p')
    AND c.relname NOT IN ('budget_entry', 'audit_stream')
    AND NOT has_table_privilege('macsad_app', c.oid, 'INSERT');

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'macsad_app is missing an expected append/create grant';
  END IF;

  SELECT count(*) INTO bad_count
  FROM unnest(ARRAY[
    'workspace', 'tool_repository', 'policy_revision', 'actor', 'actor_identity',
    'membership', 'capability_grant', 'research_case', 'task', 'thread',
    'task_assignment', 'execution', 'execution_tool_use', 'model_call',
    'publication_batch', 'publication_attempt', 'publication_head',
    'command_receipt', 'inbound_delivery', 'outbox_message'
  ]::text[]) AS expected_update(table_name)
  WHERE NOT has_table_privilege(
    'macsad_app', pg_catalog.to_regclass(pg_catalog.format('macsad.%I', table_name)), 'UPDATE');

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'macsad_app is missing an expected state-transition grant';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'macsad'
    AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND has_table_privilege('macsad_app', c.oid, 'UPDATE')
    AND c.relname <> ALL (ARRAY[
      'workspace', 'tool_repository', 'policy_revision', 'actor', 'actor_identity',
      'membership', 'capability_grant', 'research_case', 'task', 'thread',
      'task_assignment', 'execution', 'execution_tool_use', 'model_call',
      'publication_batch', 'publication_attempt', 'publication_head',
      'command_receipt', 'inbound_delivery', 'outbox_message'
    ]::name[]);

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'macsad_app has UPDATE outside the approved state-bearing tables';
  END IF;

  -- Versioned, exact API identities: missing expected routines fail closed.
  approved_api := ARRAY[to_regprocedure(
    'macsad.record_budget_entry(uuid,macsad.budget_entry_kind,numeric,text,macsad.sha256_digest,uuid,uuid,uuid,uuid,uuid,text)'
  )::oid];
  IF approved_api[1] IS NULL THEN
    RAISE EXCEPTION 'approved budget API is missing';
  END IF;
  SELECT max(version) INTO api_schema_version FROM macsad_meta.schema_migration;
  IF api_schema_version >= 2 THEN
    FOR expected_api IN SELECT * FROM (VALUES
      ('macsad.lean_digest(jsonb)', 'macsad.sha256_digest', 'sql', 'i', 'search_path=pg_catalog'),
      ('macsad.lean_begin_command(uuid,uuid,text,text,text,jsonb)', 'macsad.command_receipt', 'plpgsql', 'v', 'search_path=pg_catalog, macsad'),
      ('macsad.lean_finish_command(uuid,uuid,jsonb,boolean)', 'jsonb', 'plpgsql', 'v', 'search_path=pg_catalog, macsad'),
      ('macsad.lean_submit(uuid,uuid,uuid,bigint,text,uuid,text,uuid,macsad.sha256_digest,jsonb,macsad.sha256_digest)', 'jsonb', 'plpgsql', 'v', 'search_path=pg_catalog, macsad'),
      ('macsad.lean_advance(uuid,uuid,uuid,bigint,text,text,bigint,integer,jsonb,uuid[],macsad.sha256_digest)', 'jsonb', 'plpgsql', 'v', 'search_path=pg_catalog, macsad')
    ) AS required(signature, return_type, language_name, volatility, search_path_setting)
    LOOP
      SELECT p.*, language.lanname INTO actual_api
      FROM pg_proc p JOIN pg_language language ON language.oid=p.prolang
      WHERE p.oid=to_regprocedure(expected_api.signature);
      IF NOT FOUND THEN
        RAISE EXCEPTION 'approved Lean API is missing: %', expected_api.signature;
      END IF;
      IF actual_api.prosecdef OR actual_api.prokind <> 'f'
         OR actual_api.proowner <> 'macsad_owner'::regrole
         OR actual_api.prorettype <> to_regtype(expected_api.return_type)
         OR actual_api.lanname <> expected_api.language_name
         OR actual_api.provolatile::text <> expected_api.volatility
         OR actual_api.proconfig IS DISTINCT FROM ARRAY[expected_api.search_path_setting]
         OR NOT has_function_privilege('macsad_app',actual_api.oid,'EXECUTE')
         OR NOT has_function_privilege('macsad_migrator',actual_api.oid,'EXECUTE')
         OR has_function_privilege('macsad_reader',actual_api.oid,'EXECUTE') THEN
        RAISE EXCEPTION 'approved Lean API contract differs: %', expected_api.signature;
      END IF;
      approved_api := array_append(approved_api,actual_api.oid);
    END LOOP;
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND has_function_privilege('macsad_app', p.oid, 'EXECUTE')
    AND NOT (p.oid = ANY(approved_api));

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'macsad_app can execute a routine outside the approved API';
  END IF;

  SELECT count(*) INTO bad_count
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND has_function_privilege('macsad_reader', p.oid, 'EXECUTE');

  IF bad_count <> 0 THEN
    RAISE EXCEPTION 'macsad_reader can execute a MaCSad routine';
  END IF;

  IF to_regprocedure(
      'macsad.record_budget_entry(uuid,macsad.budget_entry_kind,numeric,text,macsad.sha256_digest,uuid,uuid,uuid,uuid,uuid,text)'
     ) IS NULL
     OR NOT has_function_privilege(
       'macsad_app',
       'macsad.record_budget_entry(uuid,macsad.budget_entry_kind,numeric,text,macsad.sha256_digest,uuid,uuid,uuid,uuid,uuid,text)',
       'EXECUTE'
     )
     OR EXISTS (
       SELECT 1
       FROM pg_proc AS budget_function
       WHERE budget_function.oid = to_regprocedure(
         'macsad.record_budget_entry(uuid,macsad.budget_entry_kind,numeric,text,macsad.sha256_digest,uuid,uuid,uuid,uuid,uuid,text)'
       )
         AND (
           NOT budget_function.prosecdef
           OR NOT EXISTS (
             SELECT 1
             FROM unnest(COALESCE(budget_function.proconfig, ARRAY[]::text[])) AS setting
             WHERE replace(setting, ' ', '') = 'search_path=pg_catalog,macsad'
           )
         )
     ) THEN
    RAISE EXCEPTION 'macsad_app budget API grant is missing or has the wrong signature';
  END IF;

  SELECT count(*) INTO bad_count
  FROM macsad.budget_account AS account
  LEFT JOIN (
    SELECT
      budget_account_id,
      COALESCE(sum(quantity) FILTER (WHERE kind = 'reserve'), 0)
        - COALESCE(sum(reservation_released_quantity), 0) AS expected_reserved,
      COALESCE(sum(quantity) FILTER (WHERE kind IN ('commit', 'spend_adjustment')), 0)
        AS expected_spent,
      COALESCE(sum(quantity) FILTER (WHERE kind = 'limit_adjustment'), 0) AS limit_adjustment
    FROM macsad.budget_entry
    GROUP BY budget_account_id
  ) AS ledger ON ledger.budget_account_id = account.id
  WHERE account.reserved_quantity IS DISTINCT FROM COALESCE(ledger.expected_reserved, 0)
     OR account.spent_quantity IS DISTINCT FROM COALESCE(ledger.expected_spent, 0)
     OR account.spending_limit IS DISTINCT FROM
       account.initial_spending_limit + COALESCE(ledger.limit_adjustment, 0);

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% budget account projection(s) drift from the immutable ledger', bad_count;
  END IF;

  SELECT count(*) INTO bad_count
  FROM macsad.budget_balance_v
  WHERE projection_is_consistent IS DISTINCT FROM true
     OR spending_limit IS DISTINCT FROM ledger_spending_limit
     OR reserved_quantity IS DISTINCT FROM ledger_reserved_quantity
     OR spent_quantity IS DISTINCT FROM ledger_spent_quantity
     OR spend_variance IS DISTINCT FROM spending_limit - spent_quantity
     OR overrun_quantity IS DISTINCT FROM greatest(spent_quantity - spending_limit, 0::numeric)
     OR available_to_reserve IS DISTINCT FROM
       greatest(spending_limit - spent_quantity - reserved_quantity, 0::numeric)
     OR can_reserve IS DISTINCT FROM (spent_quantity + reserved_quantity < spending_limit);

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% budget balance row(s) violate view arithmetic', bad_count;
  END IF;

  SELECT count(*) INTO bad_count
  FROM macsad.model_cost_variance_v AS variance
  WHERE recorded_spend_quantity IS DISTINCT FROM
      CASE WHEN settlement_kind = 'commit'
        THEN settled_quantity + COALESCE(spend_adjustment_quantity, 0::numeric)
        ELSE COALESCE(spend_adjustment_quantity, 0::numeric) END
     OR reservation_variance IS DISTINCT FROM
      CASE WHEN settlement_kind = 'commit' AND reserved_quantity IS NOT NULL
        THEN settled_quantity + COALESCE(spend_adjustment_quantity, 0::numeric)
          - reserved_quantity END
     OR reconciliation_variance IS DISTINCT FROM
      CASE WHEN (settlement_kind = 'commit' OR EXISTS (
          SELECT 1
          FROM macsad.budget_entry AS adjustment
          WHERE adjustment.model_call_id = variance.model_call_id
            AND adjustment.kind = 'spend_adjustment'
        ))
          AND billed_amount IS NOT NULL
          AND budget_currency = billed_currency
        THEN COALESCE(settled_quantity, 0::numeric)
          + COALESCE(spend_adjustment_quantity, 0::numeric) - billed_amount END
     OR usage_needs_reconciliation IS DISTINCT FROM
      (latest_usage_observation_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM macsad.budget_entry AS usage_entry
        WHERE usage_entry.model_usage_observation_id = latest_usage_observation_id
      ))
     OR exceeded_reservation IS DISTINCT FROM
      (settlement_kind = 'commit' AND reserved_quantity IS NOT NULL
        AND settled_quantity + COALESCE(spend_adjustment_quantity, 0::numeric)
          > reserved_quantity);

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% model cost variance row(s) violate reconciliation arithmetic', bad_count;
  END IF;

  SELECT count(*) INTO bad_count
  FROM macsad.audit_stream AS stream
  WHERE (stream.last_workspace_sequence = 0 AND stream.last_event_hash IS NOT NULL)
     OR (stream.last_workspace_sequence > 0 AND NOT EXISTS (
       SELECT 1 FROM macsad.domain_event AS event
       WHERE event.workspace_id = stream.workspace_id
         AND event.workspace_sequence_no = stream.last_workspace_sequence
         AND event.event_hash = stream.last_event_hash
     ));

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% workspace audit stream head(s) do not resolve to the exact event', bad_count;
  END IF;

  SELECT count(*) INTO bad_count
  FROM macsad.tool_repository_revision AS revision
  WHERE revision.operations_sealed_at IS NOT NULL
    AND revision.operation_count IS DISTINCT FROM (
      SELECT count(*)::integer
      FROM macsad.tool_operation_manifest AS operation
      WHERE operation.tool_repository_revision_id = revision.id
    );

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% sealed tool operation catalog(s) have count drift', bad_count;
  END IF;

  SELECT count(*) INTO bad_count
  FROM macsad.model_call AS call
  LEFT JOIN LATERAL (
    SELECT observation.id
    FROM macsad.model_usage_observation AS observation
    WHERE observation.model_call_id = call.id
    ORDER BY observation.observation_sequence DESC
    LIMIT 1
  ) AS latest_usage ON true
  WHERE call.state = 'reconciled'
    AND (
      latest_usage.id IS NULL
      OR NOT EXISTS (
        SELECT 1 FROM macsad.budget_entry AS usage_entry
        WHERE usage_entry.model_call_id = call.id
          AND usage_entry.model_usage_observation_id = latest_usage.id
      )
      OR NOT EXISTS (
        SELECT 1
        FROM macsad.budget_entry AS reservation
        JOIN macsad.budget_entry AS settlement
          ON settlement.related_reservation_entry_id = reservation.id
         AND settlement.model_call_id = call.id
         AND settlement.kind = 'commit'
        WHERE reservation.model_call_id = call.id
          AND reservation.kind = 'reserve'
      )
    );

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% reconciled model call(s) lack exact latest-usage settlement', bad_count;
  END IF;

  SELECT count(*) INTO bad_count
  FROM macsad.publication_head AS head
  LEFT JOIN macsad.publication_batch AS batch
    ON batch.id = head.publication_batch_id
   AND batch.workspace_id = head.workspace_id
  LEFT JOIN macsad.publication_attempt AS attempt
    ON attempt.id = head.publication_attempt_id
   AND attempt.workspace_id = head.workspace_id
   AND attempt.publication_batch_id = head.publication_batch_id
  WHERE batch.state NOT IN ('published', 'superseded')
     OR attempt.state <> 'succeeded';

  IF bad_count <> 0 THEN
    RAISE EXCEPTION '% publication head(s) do not resolve to successful published deployments', bad_count;
  END IF;

  IF to_regclass('macsad_meta.schema_migration') IS NULL THEN
    RAISE EXCEPTION 'migration ledger is missing';
  END IF;

  SELECT count(*), max(version)
  INTO ledger_count, ledger_max
  FROM macsad_meta.schema_migration;

  IF (SELECT current_version FROM macsad.schema_version_v)
       IS DISTINCT FROM ledger_max THEN
    RAISE EXCEPTION 'application schema version view does not match the migration ledger';
  END IF;

  IF ledger_count = 0
     OR ledger_max <> ledger_count
     OR EXISTS (
       SELECT 1
       FROM macsad_meta.schema_migration
       WHERE version <= 0
          OR name !~ '^[0-9]{4}_[a-z0-9_]+$'
          OR left(name, 4)::integer <> version
          OR octet_length(script_sha256) <> 32
          OR postgresql_version < 160000
          OR postgresql_version >= 170000
          OR applied_by::text = ''
     ) THEN
    RAISE EXCEPTION 'migration ledger is empty, non-contiguous, or contains an unverified row';
  END IF;
END
$verify$;

WITH catalog_item AS (
  SELECT
    'schema'::text AS item_kind,
    n.nspname::text AS identity,
    concat_ws('|',
      pg_get_userbyid(n.nspowner),
      COALESCE((SELECT string_agg(acl::text, ',' ORDER BY acl::text) FROM unnest(n.nspacl) AS acl), '')
    ) AS definition
  FROM pg_namespace AS n
  WHERE n.nspname IN ('macsad', 'macsad_meta')

  UNION ALL

  SELECT
    'relation',
    format('%I.%I', n.nspname, c.relname),
    concat_ws('|', c.relkind, c.relpersistence, c.relrowsecurity, c.relforcerowsecurity,
      pg_get_userbyid(c.relowner),
      COALESCE((SELECT string_agg(acl::text, ',' ORDER BY acl::text) FROM unnest(c.relacl) AS acl), ''),
      CASE WHEN c.relkind IN ('v', 'm') THEN pg_get_viewdef(c.oid, true) ELSE '' END)
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')

  UNION ALL

  SELECT
    'column',
    format('%I.%I.%I', n.nspname, c.relname, a.attname),
    concat_ws('|', a.attnum, format_type(a.atttypid, a.atttypmod), a.attnotnull,
      a.attidentity, a.attgenerated,
      COALESCE(pg_get_expr(d.adbin, d.adrelid, true), ''))
  FROM pg_attribute AS a
  JOIN pg_class AS c ON c.oid = a.attrelid
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  LEFT JOIN pg_attrdef AS d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND a.attnum > 0
    AND NOT a.attisdropped

  UNION ALL

  SELECT
    'constraint',
    format('%I.%I', n.nspname, con.conname),
    concat_ws('|', con.contype, con.convalidated, con.condeferrable, con.condeferred,
      pg_get_constraintdef(con.oid, true))
  FROM pg_constraint AS con
  JOIN pg_namespace AS n ON n.oid = con.connamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')

  UNION ALL

  SELECT
    'index',
    format('%I.%I', n.nspname, index_class.relname),
    pg_get_indexdef(index_class.oid, 0, true)
  FROM pg_index AS index_record
  JOIN pg_class AS index_class ON index_class.oid = index_record.indexrelid
  JOIN pg_namespace AS n ON n.oid = index_class.relnamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')

  UNION ALL

  SELECT
    'type',
    format('%I.%I', n.nspname, t.typname),
    concat_ws('|', t.typtype, t.typcategory, t.typnotnull,
      format_type(NULLIF(t.typbasetype, '0'::oid), t.typtypmod),
      COALESCE(t.typdefault, ''), pg_get_userbyid(t.typowner),
      COALESCE((SELECT string_agg(acl::text, ',' ORDER BY acl::text) FROM unnest(t.typacl) AS acl), ''))
  FROM pg_type AS t
  JOIN pg_namespace AS n ON n.oid = t.typnamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND t.typtype IN ('c', 'd', 'e', 'm', 'r')

  UNION ALL

  SELECT
    'enum-value',
    format('%I.%I', n.nspname, t.typname),
    concat_ws('|', e.enumsortorder, e.enumlabel)
  FROM pg_enum AS e
  JOIN pg_type AS t ON t.oid = e.enumtypid
  JOIN pg_namespace AS n ON n.oid = t.typnamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')

  UNION ALL

  SELECT
    'routine',
    format('%I.%I(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)),
    concat_ws('|', pg_get_userbyid(p.proowner), p.provolatile, p.proparallel, p.prosecdef,
      COALESCE((SELECT string_agg(acl::text, ',' ORDER BY acl::text) FROM unnest(p.proacl) AS acl), ''),
      pg_get_functiondef(p.oid))
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')

  UNION ALL

  SELECT
    'trigger',
    format('%I.%I.%I', n.nspname, c.relname, trigger_record.tgname),
    pg_get_triggerdef(trigger_record.oid, true)
  FROM pg_trigger AS trigger_record
  JOIN pg_class AS c ON c.oid = trigger_record.tgrelid
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')
    AND NOT trigger_record.tgisinternal

  UNION ALL

  SELECT
    'policy',
    format('%I.%I.%I', n.nspname, c.relname, policy_record.polname),
    concat_ws('|', policy_record.polcmd, policy_record.polpermissive,
      COALESCE((
        SELECT string_agg(
          CASE WHEN role_oid = 0 THEN 'public' ELSE pg_get_userbyid(role_oid) END,
          ',' ORDER BY CASE WHEN role_oid = 0 THEN 'public' ELSE pg_get_userbyid(role_oid) END
        )
        FROM unnest(policy_record.polroles) AS role_oid
      ), ''),
      COALESCE(pg_get_expr(policy_record.polqual, policy_record.polrelid, true), ''),
      COALESCE(pg_get_expr(policy_record.polwithcheck, policy_record.polrelid, true), ''))
  FROM pg_policy AS policy_record
  JOIN pg_class AS c ON c.oid = policy_record.polrelid
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')

  UNION ALL

  SELECT
    'database',
    'current-database',
    concat_ws('|', pg_get_userbyid(d.datdba), pg_encoding_to_char(d.encoding),
      COALESCE((SELECT string_agg(acl::text, ',' ORDER BY acl::text) FROM unnest(d.datacl) AS acl), ''))
  FROM pg_database AS d
  WHERE d.datname = current_database()

  UNION ALL

  SELECT
    'role',
    role_record.rolname,
    concat_ws('|', role_record.rolcanlogin, role_record.rolinherit, role_record.rolsuper,
      role_record.rolcreatedb, role_record.rolcreaterole, role_record.rolreplication,
      role_record.rolbypassrls)
  FROM pg_roles AS role_record
  WHERE role_record.rolname IN (
    'macsad_owner', 'macsad_migrator', 'macsad_app', 'macsad_reader', 'alejandro',
    'macsad_deployer', 'macsad_runtime', 'macsad_viewer'
  )

  UNION ALL

  SELECT
    'role-membership',
    format('%I->%I', pg_get_userbyid(membership.member), pg_get_userbyid(membership.roleid)),
    concat_ws('|', pg_get_userbyid(membership.grantor), membership.admin_option,
      membership.inherit_option, membership.set_option)
  FROM pg_auth_members AS membership
  WHERE pg_get_userbyid(membership.roleid) IN (
    'macsad_owner', 'macsad_migrator', 'macsad_app', 'macsad_reader', 'alejandro',
    'macsad_deployer', 'macsad_runtime', 'macsad_viewer'
  )
     OR (
       pg_get_userbyid(membership.member) IN (
         'macsad_owner', 'macsad_migrator', 'macsad_app', 'macsad_reader', 'alejandro',
         'macsad_deployer', 'macsad_runtime', 'macsad_viewer'
       )
       AND pg_get_userbyid(membership.roleid) IN (
         'macsad_owner', 'macsad_migrator', 'macsad_app', 'macsad_reader', 'alejandro',
         'macsad_deployer', 'macsad_runtime', 'macsad_viewer'
       )
     )

  UNION ALL

  SELECT
    'role-setting',
    format('%s@%s', COALESCE(role_record.rolname::text, '<database>'), CASE
      WHEN role_setting.setdatabase = 0 THEN '<all>'
      WHEN database_record.datname = current_database() THEN '<current-database>'
      ELSE database_record.datname::text
    END),
    setting
  FROM pg_db_role_setting AS role_setting
  LEFT JOIN pg_roles AS role_record ON role_record.oid = role_setting.setrole
  LEFT JOIN pg_database AS database_record ON database_record.oid = role_setting.setdatabase
  CROSS JOIN LATERAL unnest(role_setting.setconfig) AS setting
  WHERE (
    role_setting.setdatabase = (
      SELECT oid FROM pg_database WHERE datname = current_database()
    )
    AND (
      role_setting.setrole = 0
      OR role_record.rolname IN (
        'macsad_owner', 'macsad_migrator', 'macsad_app', 'macsad_reader',
        'alejandro', 'macsad_deployer', 'macsad_runtime', 'macsad_viewer'
      )
    )
  )
     OR (
       role_setting.setdatabase = 0
       AND role_record.rolname IN (
         'macsad_owner', 'macsad_migrator', 'macsad_app', 'macsad_reader',
         'alejandro', 'macsad_deployer', 'macsad_runtime', 'macsad_viewer'
       )
     )

  UNION ALL

  SELECT
    'default-acl',
    concat_ws('.', pg_get_userbyid(default_acl.defaclrole),
      COALESCE(namespace_record.nspname, 'global'), default_acl.defaclobjtype),
    COALESCE((SELECT string_agg(acl::text, ',' ORDER BY acl::text)
      FROM unnest(default_acl.defaclacl) AS acl), '')
  FROM pg_default_acl AS default_acl
  LEFT JOIN pg_namespace AS namespace_record ON namespace_record.oid = default_acl.defaclnamespace
  WHERE pg_get_userbyid(default_acl.defaclrole) = 'macsad_owner'
    AND (namespace_record.nspname IN ('macsad', 'macsad_meta') OR default_acl.defaclnamespace = 0)

  UNION ALL

  SELECT
    'extension',
    format('%I.%I', n.nspname, extension_record.extname),
    extension_record.extversion
  FROM pg_extension AS extension_record
  JOIN pg_namespace AS n ON n.oid = extension_record.extnamespace
  WHERE n.nspname IN ('macsad', 'macsad_meta')
), fingerprint AS (
  SELECT md5(string_agg(
    concat_ws(E'\x1f', item_kind, identity, definition),
    E'\n' ORDER BY item_kind, identity, definition
  )) AS schema_fingerprint
  FROM catalog_item
)
SELECT schema_fingerprint FROM fingerprint
\gset

\echo schema_fingerprint=:schema_fingerprint

\if :{?expected_schema_fingerprint}
  SELECT :'expected_schema_fingerprint' = :'schema_fingerprint' AS fingerprint_matches
  \gset
  \if :fingerprint_matches
  \else
    \echo 'error: live catalog fingerprint does not match the release fingerprint'
    \quit 3
  \endif
\endif

SELECT max(version) AS current_schema_version
FROM macsad_meta.schema_migration
\gset

\if :{?minimum_schema_version}
  SELECT :'current_schema_version'::bigint >= :'minimum_schema_version'::bigint AS minimum_version_ok
  \gset
  \if :minimum_version_ok
  \else
    \echo 'error: database schema is older than this application supports'
    \quit 3
  \endif
\endif

\if :{?maximum_schema_version}
  SELECT :'current_schema_version'::bigint <= :'maximum_schema_version'::bigint AS maximum_version_ok
  \gset
  \if :maximum_version_ok
  \else
    \echo 'error: database schema is newer than this application supports'
    \quit 3
  \endif
\endif

COMMIT;
\echo 'MaCSad PostgreSQL verification passed at schema version' :current_schema_version
