-- Nom conseillé dans le SQL Editor : Référentiel d'équipement PF2e AoN Legacy
-- Référentiel global, distinct des objets possédés par les campagnes.

create table if not exists public.pf2e_equipment_references (
  id uuid primary key default gen_random_uuid(),
  source_tab text not null,
  equipment_kind text not null check (equipment_kind in ('weapon', 'armor', 'shield', 'accessory', 'consumable', 'gear', 'other')),
  name_en text not null check (length(btrim(name_en)) between 1 and 240),
  price_label text,
  price_cp bigint check (price_cp is null or price_cp >= 0),
  aon_url text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists pf2e_equipment_references_kind_name_idx
  on public.pf2e_equipment_references (equipment_kind, name_en);

alter table public.pf2e_equipment_references enable row level security;

drop policy if exists "Authenticated users can read PF2e equipment references" on public.pf2e_equipment_references;
create policy "Authenticated users can read PF2e equipment references"
  on public.pf2e_equipment_references for select to authenticated using (true);

with raw_rows as (
  select btrim(replace(line, chr(13), '')) as line
  from regexp_split_to_table($refs$
ws|2|0|Club
ws|3|20|Dagger
ws|4|20|Gauntlet
ws|5|40|Light mace
ws|6|50|Longspear
ws|7|100|Mace
ws|8|100|Morningstar
ws|9|20|Sickle
ws|10|10|Spear
ws|11|30|Spiked gauntlet
ws|12|0|Staff
ws|15|400|Bastard sword
ws|16|100|Battle axe
ws|17|20|Bo staff
ws|18|300|Falchion
ws|19|80|Flail
ws|20|100|Glaive
ws|21|200|Greataxe
ws|22|100|Greatclub
ws|23|100|Greatpick
ws|24|200|Greatsword
ws|25|200|Guisarme
ws|26|200|Halberd
ws|27|40|Hatchet
ws|28|100|Lance
ws|29|30|Light hammer
ws|30|40|Light pick
ws|31|100|Longsword
ws|32|50|Main-gauche
ws|33|300|Maul
ws|34|70|Pick
ws|35|200|Ranseur
ws|36|200|Rapier
ws|37|10|Sap
ws|38|100|Scimitar
ws|39|200|Scythe
ws|40||Shield bash
ws|41|50|Shield boss
ws|42|50|Shield spikes
ws|43|90|Shortsword
ws|44|200|Starknife
ws|127|500|Sword cane
ws|45|100|Trident
ws|46|200|War flail
ws|47|100|Warhammer
ws|48|10|Whip
ws|66|10|Blowgun
ws|67|300|Crossbow
ws|68|1|Dart
ws|69|300|Hand crossbow
ws|70|400|Heavy crossbow
ws|71|10|Javelin
ws|72|0|Sling
ws|432|1200|Arbalest
ws|645|50|Bola
ws|74|2000|Composite longbow
ws|75|1400|Composite shortbow
ws|76|600|Longbow
ws|77|300|Shortbow
we|13||Clan Dagger
we|49||Dogslicer
we|62||Dwarven Waraxe
we|50||Elven Curve Blade
we|51||Filcher's Fork
we|63||Gnome Flickmace
we|52||Gnome Hooked Hammer
we|78||Halfling Sling Staff
we|53||Horsechopper
we|54||Kama
we|55||Katana
we|14||Katar
we|126||Khakkara
we|56||Kukri
we|57||Nunchaku
we|58||Orc Knuckle Dagger
we|64||Orc Necksplitter
we|59||Sai
we|65||Sawtooth Saber
we|79||Shuriken
we|60||Spiked Chain
we|61||Temple Sword
we|129||Wakizashi
we|258||Broadspear
we|125||Daikyu
we|260||Dandpatta
we|261||Donchak
we|262||Gada
we|263||Kalis
we|264||Kris
we|266||Talwar
we|128||Tengu Gale Blade
we|267||Thorn Whip
we|257||Triggerbrand
we|268||Visap
we|269||Zulfikar
we|644||Atlatl
we|657||Barricade Buster
we|608||Battle Saddle
we|609||Bec de Corbin
we|619||Bladed Scarf
we|652||Boomerang
we|659||Bow Staff
we|620||Breaching Pike
we|637||Butterfly Sword
we|638||Chain Sword
we|653||Chakri
we|508||Combat Fishing Pole
we|621||Combat Lure
we|606||Corset Knife
we|660||Crescent Cross
we|610||Dancer's Spear
we|639||Dwarven Dorn-Dergar
we|611||Earthbreaker
we|635||Falcata
we|640||Feng Huo Lun
we|622||Fighting Fan
we|505||Fighting Oar
we|515||Fishing Lure
we|612||Flyssa
we|607||Frying Pan
we|646||Gakgung
we|647||Gauntlet Bow
we|510||Gladius
we|648||Harpoon
we|641||Hook Sword
we|623||Jiu Huan Dao
we|642||Karambit
we|513||Kestros
we|624||Khopesh
we|625||Kusarigama
we|661||Lancer
we|626||Leiomano
we|613||Long Hammer
we|614||Machete
we|511||Macuahuitl
we|627||Mambele
we|615||Meteor Hammer
we|662||Mikazuki
we|628||Naginata
we|636||Nodachi
we|506||Palstave
we|616||Panabas
we|656||Phalanx Piercer
we|629||Polytool
we|630||Rope Dart
we|649||Rotary Bow
we|631||Sansetsukon
we|617||Scizore
we|650||Shield Bow
we|654||Spraysling
we|651||Sukgung
we|658||Taw Launcher
we|632||Tekko-Kagi
we|643||Three-Section Naginata
we|655||Thunder Sling
we|633||Urumi
we|507||War Gavel
we|512||War Javelin
we|618||War Razor
we|634||Whipstaff
we|663||Wrecker
we|565||Air Repeater
we|574||Arquebus
we|590||Axe Musket
we|173||Backpack Ballista
we|544||Backpack Catapult
we|562||Bayonet
we|604||Big Boom Gun
we|591||Black Powder Knuckle Dusters
we|575||Blunderbuss
we|592||Cane Pistol
we|576||Clan Pistol
we|567||Coat Pistol
we|593||Dagger Pistol
we|545||Dart Umbrella
we|583||Dawnsilver Tree
we|577||Double-Barreled Musket
we|578||Double-Barreled Pistol
we|579||Dragon-Mouth Pistol
we|580||Dueling Pistol
we|586||Dwarven Scattergun
we|602||Explosive Dogslicer
we|568||Fire Lance
we|587||Flingflenser
we|569||Flintlock Musket
we|570||Flintlock Pistol
we|559||Forked Bipod
we|594||Gnome Amalgam Musket
we|595||Gun Sword
we|596||Hammer Gun
we|571||Hand Cannon
we|581||Harmona Gun
we|546||Injection Spear
we|582||Jezail
we|561||Knuckle Duster
we|572||Long Air Repeater
we|597||Mace Multipistol
we|547||Pantograph Gauntlet
we|584||Pepperbox
we|598||Piercing Wind
we|599||Rapier Pistol
we|563||Reinforced Stock
we|548||Repeating Crossbow
we|549||Repeating Hand Crossbow
we|178||Repeating Heavy Crossbow
we|585||Slide Pistol
we|603||Spoon Gun
we|601||Three Peaked Tree
we|551||Umbrella Injector
a|2|10|Explorer’s clothing
a|3|20|Padded armor
a|4|200|Leather
a|5|300|Studded leather
a|6|500|Chain shirt
a|7|200|Hide
a|8|400|Scale mail
a|9|600|Chain mail
a|10|800|Breastplate
a|11|1300|Splint mail
a|12|1800|Half plate
a|13|3000|Full plate
s|1|100|Buckler
s|2|100|Wooden shield
s|3|200|Steel shield
s|4|1000|Tower shield
$refs$, E'\n') as line
  where btrim(replace(line, chr(13), '')) <> ''
), parsed as (
  select
    split_part(line, '|', 1) as code,
    split_part(line, '|', 2)::integer as aon_id,
    nullif(split_part(line, '|', 3), '')::bigint as price_cp,
    btrim(split_part(line, '|', 4)) as name_en
  from raw_rows
), prepared as (
  select
    case code when 'ws' then 'Armes standards' when 'we' then 'Armes étendues' when 'a' then 'Armures standards' else 'Boucliers standards' end as source_tab,
    case when code in ('ws', 'we') then 'weapon' when code = 'a' then 'armor' else 'shield' end as equipment_kind,
    name_en, price_cp,
    case when price_cp is null then null when price_cp = 0 then '0' when price_cp % 100 = 0 then (price_cp / 100)::text || ' gp' when price_cp % 10 = 0 then (price_cp / 10)::text || ' sp' else price_cp::text || ' cp' end as price_label,
    'https://2e.aonprd.com/' || case when code in ('ws', 'we') then 'Weapons' when code = 'a' then 'Armor' else 'Shields' end || '.aspx?ID=' || aon_id || '&NoRedirect=1' as aon_url
  from parsed
)
insert into public.pf2e_equipment_references (source_tab, equipment_kind, name_en, price_label, price_cp, aon_url)
select source_tab, equipment_kind, name_en, price_label, price_cp, aon_url from prepared
on conflict (aon_url) do update set
  source_tab = excluded.source_tab, equipment_kind = excluded.equipment_kind, name_en = excluded.name_en,
  price_label = excluded.price_label, price_cp = excluded.price_cp;

do $$
begin
  if (select count(*) from public.pf2e_equipment_references) <> 225 then
    raise exception 'Le référentiel PF2e doit contenir exactement 225 références';
  end if;
end $$;
