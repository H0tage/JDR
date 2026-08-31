import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const sourcePath = resolve("supabase/reference/undead-creatures.csv");
const migrationPath = resolve("supabase/migrations/20260830170000_campaign_slug_words.sql");

function parseCsv(text) {
  const rows = [];
  let row = [];
  let value = "";
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (character === '"') {
      if (quoted && text[index + 1] === '"') { value += '"'; index += 1; }
      else quoted = !quoted;
    } else if (character === "," && !quoted) {
      row.push(value); value = "";
    } else if ((character === "\n" || character === "\r") && !quoted) {
      if (character === "\r" && text[index + 1] === "\n") index += 1;
      row.push(value); value = "";
      if (row.some((cell) => cell !== "")) rows.push(row);
      row = [];
    } else value += character;
  }
  if (value || row.length) { row.push(value); rows.push(row); }
  const [headers, ...records] = rows;
  return records.map((record) => Object.fromEntries(headers.map((header, index) => [header, record[index] ?? ""])));
}

function sql(value) {
  return `'${value.replaceAll("'", "''")}'`;
}

const creatures = parseCsv(readFileSync(sourcePath, "utf8"));
if (creatures.length < 2) throw new Error("Le référentiel doit contenir au moins deux créatures.");
if (creatures.some((item, index) => Number(item.id) !== index + 1)) throw new Error("Les IDs doivent être continus et commencer à 1.");
if (creatures.some((item) => !/^[a-z0-9]+$/.test(item.slug))) throw new Error("Chaque slug doit contenir uniquement a-z et 0-9.");
if (new Set(creatures.map((item) => item.slug)).size !== creatures.length) throw new Error("Les slugs doivent être uniques.");

const values = creatures
  .map((item) => `  (${Number(item.id)}, ${sql(item.creature)}, ${sql(item.slug)}, ${sql(item.univers_categorie)})`)
  .join(",\n");

const migration = `-- Généré par scripts/generate-campaign-slug-migration.mjs depuis
-- supabase/reference/undead-creatures.csv. Ne pas modifier les INSERT à la main.
--
-- Les mots internes sont déjà normalisés (ex. Bone Golem -> bonegolem). Le
-- tiret ne sert qu'à séparer les deux ou trois créatures dans l'URL finale.

create table public.campaign_slug_words (
  id integer primary key,
  creature text not null,
  slug text not null unique check (slug ~ '^[a-z0-9]+$'),
  universe_category text not null
);

insert into public.campaign_slug_words (id, creature, slug, universe_category) values
${values};

alter table public.campaign_slug_words enable row level security;

comment on table public.campaign_slug_words is
  'Référentiel versionné de noms de morts-vivants servant à composer les identifiants publics des campagnes.';

create or replace function public.generate_available_campaign_slug()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  candidate text;
begin
  -- Les paires sont ordonnées : vampire-bonegolem et bonegolem-vampire sont
  -- deux identifiants différents. random() répartit les nouvelles campagnes.
  select first_word.slug || '-' || second_word.slug
  into candidate
  from public.campaign_slug_words first_word
  cross join public.campaign_slug_words second_word
  where first_word.id <> second_word.id
    and not exists (
      select 1 from public.campaigns campaign
      where campaign.slug = first_word.slug || '-' || second_word.slug
    )
  order by random()
  limit 1;

  if candidate is not null then
    return candidate;
  end if;

  -- Ce parcours n'est atteint qu'après épuisement de toutes les paires. Sans
  -- ORDER BY random(), PostgreSQL peut s'arrêter dès le premier triplet libre.
  select first_word.slug || '-' || second_word.slug || '-' || third_word.slug
  into candidate
  from public.campaign_slug_words first_word
  cross join public.campaign_slug_words second_word
  cross join public.campaign_slug_words third_word
  where first_word.id <> second_word.id
    and first_word.id <> third_word.id
    and second_word.id <> third_word.id
    and not exists (
      select 1 from public.campaigns campaign
      where campaign.slug = first_word.slug || '-' || second_word.slug || '-' || third_word.slug
    )
  order by first_word.id, second_word.id, third_word.id
  limit 1;

  if candidate is null then
    raise exception 'Aucune combinaison de noms de campagne n’est encore disponible';
  end if;
  return candidate;
end;
$$;

revoke all on table public.campaign_slug_words from public, anon, authenticated;
revoke all on function public.generate_available_campaign_slug() from public, anon, authenticated;
`;

writeFileSync(migrationPath, migration, "utf8");
console.log(`Migration générée avec ${creatures.length} créatures : ${migrationPath}`);
