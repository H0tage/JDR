-- Audit only: no grants, updates or data modification.
begin read only;

-- Unexpected administrative table privileges exposed to application roles.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and grantee in ('anon', 'authenticated')
  and privilege_type in ('TRUNCATE', 'TRIGGER', 'REFERENCES')
order by grantee, table_name, privilege_type;

-- Base tables reachable without row-level security.
select n.nspname as schema_name, c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
  and (has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE'))
order by c.relname;

-- Review role scope and expressions, without returning campaign content.
select tablename, policyname, roles, cmd, qual, with_check
from pg_policies where schemaname = 'public' order by tablename, policyname;

-- SECURITY DEFINER entry points exposed to anonymous callers.
select p.proname, pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and has_function_privilege('anon', p.oid, 'EXECUTE')
order by p.proname;
rollback;
