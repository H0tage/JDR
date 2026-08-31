/** Build public, spoiler-free migrations from the local private campaign package. */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const privateRoot = resolve(root, 'private-references/campaign-data/blood-lords/supabase-migrations');
const publicRoot = resolve(root, 'supabase/migrations');
const read = (name) => readFileSync(resolve(privateRoot, name), 'utf8');
const write = (name, content) => writeFileSync(resolve(publicRoot, name), `${content.trimEnd()}\n`, 'utf8');

write('20260717120000_initial_schema.sql', read('20260717120000_initial_schema.sql')
  .replace('-- Blood Lords factions manager', '-- Campaign factions manager'));

write('20260717121000_seed_blood_lords.sql', `-- No campaign content is stored in the public repository.
-- Install a private campaign package separately when a GM needs reference data.`);
for (const name of [
  '20260717122000_seed_dossiers.sql',
  '20260717130000_update_faction_names.sql',
  '20260718100000_enrich_bilateral_dossiers.sql',
]) write(name, '-- Private campaign content intentionally omitted from the public repository.');

for (const name of ['20260717131000_relation_text_overrides.sql', '20260717132000_relationship_color_overrides.sql']) {
  write(name, read(name));
}

const progression = read('20260717133000_progression_overhaul.sql');
write('20260717133000_progression_overhaul.sql', `${progression.slice(0, progression.indexOf('-- Official story milestones.'))}
-- Private campaign milestones intentionally omitted.`);

write('20260717134000_remove_ready_visibility.sql', read('20260717134000_remove_ready_visibility.sql'));

const archives = read('20260719120000_archives_and_loot.sql');
const prefix = archives.slice(0, archives.indexOf('insert into public.archive_character_templates'))
  .replace('-- Archives MJ et registre de butin Blood Lords.', '-- Archives MJ et registre de butin de campagne.');
let suffix = archives.slice(archives.indexOf('create or replace function public.seed_campaign_reference_data'));
suffix = suffix.slice(0, suffix.indexOf('do $$ begin'));
write('20260719120000_archives_and_loot.sql', `${prefix}
-- Private archive and loot templates intentionally omitted.

${suffix}`);
