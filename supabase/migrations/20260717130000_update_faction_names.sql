-- Apply the campaign's canonical French faction terminology without changing
-- stable technical slugs or foreign keys.

update public.factions
set
  name = case slug
    when 'bâtisseurs' then 'Ligue des Bâtisseurs'
    when 'célébrants' then 'Célébrants'
    when 'exportation' then 'Guilde des Exportateurs'
    when 'réanimateurs' then 'Réanimateurs'
    when 'uci' then 'Syndicats des Percepteurs d’Impôts'
    when 'charretiers' then 'Consortium des Convoyeurs'
    else name
  end,
  short_name = case slug
    when 'bâtisseurs' then 'Bâtisseurs'
    when 'célébrants' then 'Célébrants'
    when 'exportation' then 'Exportateurs'
    when 'réanimateurs' then 'Réanimateurs'
    when 'uci' then 'Percepteurs'
    when 'charretiers' then 'Convoyeurs'
    else short_name
  end
where slug in ('bâtisseurs', 'célébrants', 'exportation', 'réanimateurs', 'uci', 'charretiers');

update public.journal_entries
set details = 'Berline Haldoli fait connaître l’efficacité du groupe auprès des Réanimateurs.'
where id = '00000000-0000-4000-8600-000000000001';

update public.reputation_milestones
set title = 'Choisir la branche SPI de la banque'
where id = '00000000-0000-4000-8700-000000000004';

update public.reputation_milestones
set condition = 'Choix exclusif avec la branche SPI.'
where id = '00000000-0000-4000-8700-000000000005';

update public.source_references
set usage_note = 'Développement de la campagne et Convoyeurs.'
where title = 'Blood Lords #2 — Graveclaw';

update public.bilateral_dossiers
set pair_name = case id
  when '00000000-0000-4000-8400-000000000002' then 'Bâtisseurs ↔ Exportateurs'
  when '00000000-0000-4000-8400-000000000004' then 'Bâtisseurs ↔ Percepteurs'
  when '00000000-0000-4000-8400-000000000005' then 'Bâtisseurs ↔ Convoyeurs'
  when '00000000-0000-4000-8400-000000000006' then 'Célébrants ↔ Exportateurs'
  when '00000000-0000-4000-8400-000000000008' then 'Célébrants ↔ Percepteurs'
  when '00000000-0000-4000-8400-000000000009' then 'Célébrants ↔ Convoyeurs'
  when '00000000-0000-4000-8400-000000000010' then 'Exportateurs ↔ Réanimateurs'
  when '00000000-0000-4000-8400-000000000011' then 'Exportateurs ↔ Percepteurs'
  when '00000000-0000-4000-8400-000000000012' then 'Exportateurs ↔ Convoyeurs'
  when '00000000-0000-4000-8400-000000000013' then 'Réanimateurs ↔ Percepteurs'
  when '00000000-0000-4000-8400-000000000014' then 'Réanimateurs ↔ Convoyeurs'
  when '00000000-0000-4000-8400-000000000015' then 'Percepteurs ↔ Convoyeurs'
  else pair_name
end
where id between '00000000-0000-4000-8400-000000000002' and '00000000-0000-4000-8400-000000000015';

update public.bilateral_dossiers
set
  canon_core = 'Les SPI nomment la Ligue alliée ; tradition, caveaux et structures impénétrables.',
  b_to_a = 'Les SPI financent, possèdent, taxent et saisissent.',
  scene_hook = 'Deux contrats concurrents rouvrent une banque : propriété aux SPI ou contrôle technique à la Ligue.',
  evidence_note = 'Alliance explicite côté SPI.'
where id = '00000000-0000-4000-8400-000000000004';

update public.bilateral_dossiers
set b_to_a = 'Les SPI voient gaspillage, perte de contrôle et menace sur le prestige ancien.'
where id = '00000000-0000-4000-8400-000000000008';

update public.bilateral_dossiers
set b_to_a = 'Les SPI veulent un rendement garanti, une perception fiable et de la stabilité.'
where id = '00000000-0000-4000-8400-000000000011';

update public.bilateral_dossiers
set b_to_a = 'Les SPI taxent, surveillent et peuvent redouter cette immense force de travail.'
where id = '00000000-0000-4000-8400-000000000013';

update public.bilateral_dossiers
set
  a_to_b = 'Les SPI traitent le Consortium comme débiteur, contribuable et outil logistique.',
  b_to_a = 'Les Convoyeurs ressentent péages et tutelle mais ont besoin de crédit et de reconnaissance.'
where id = '00000000-0000-4000-8400-000000000015';
