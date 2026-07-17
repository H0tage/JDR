-- Keep only two publication states in the application. Existing staged rows
-- remain private: removing the intermediate state must never reveal content.

update public.journal_entries
set visibility = 'gm_only'
where visibility::text = 'ready';

update public.contacts
set visibility = 'gm_only'
where visibility::text = 'ready';

update public.faction_relationships
set visibility = 'gm_only'
where visibility::text = 'ready';

-- Existing projects already have resolve_reputation_milestone installed.
-- Recreate that function from PostgreSQL's canonical definition, changing
-- only its generated journal visibility from the retired state to GM-only.
do $migration$
declare
  function_definition text;
begin
  select pg_get_functiondef(
    'public.resolve_reputation_milestone(uuid,text,text,jsonb)'::regprocedure
  ) into function_definition;

  if position('''ready''' in function_definition) > 0 then
    execute replace(function_definition, '''ready''', '''gm_only''');
  end if;
end
$migration$;
