-- Généré par scripts/generate-campaign-slug-migration.mjs depuis
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
  (1, 'Abomination', 'abomination', 'Warcraft'),
  (2, 'Ahkiyyini', 'ahkiyyini', 'Folklore, mythologies et archétypes fantastiques'),
  (3, 'Alhoon', 'alhoon', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (4, 'All-consuming Hunger', 'allconsuminghunger', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (5, 'Allip', 'allip', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (6, 'Amiq Rasol', 'amiqrasol', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (7, 'Anchimayen', 'anchimayen', 'Folklore, mythologies et archétypes fantastiques'),
  (8, 'Angel of Decay', 'angelofdecay', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (9, 'Arcane Horror', 'arcanehorror', 'Dragon Age'),
  (10, 'Archliche', 'archliche', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (11, 'Ashenwight', 'ashenwight', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (12, 'Atropal', 'atropal', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (13, 'Atropal Scion', 'atropalscion', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (14, 'Baelnorn', 'baelnorn', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (15, 'Banedead', 'banedead', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (16, 'Baneguard', 'baneguard', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (17, 'Banelich', 'banelich', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (18, 'Banshee', 'banshee', 'Folklore, mythologies et archétypes fantastiques'),
  (19, 'Barghest', 'barghest', 'The Witcher'),
  (20, 'Bhoot', 'bhoot', 'Folklore, mythologies et archétypes fantastiques'),
  (21, 'Black Knight', 'blackknight', 'Warhammer Fantasy / Age of Sigmar'),
  (22, 'Bladegheist Revenant', 'bladegheistrevenant', 'Warhammer Fantasy / Age of Sigmar'),
  (23, 'Bloodkiss Beholder', 'bloodkissbeholder', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (24, 'Blood Knight', 'bloodknight', 'Warhammer Fantasy / Age of Sigmar'),
  (25, 'Bloodmote Cloud', 'bloodmotecloud', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (26, 'Bodak', 'bodak', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (27, 'Boneclaw', 'boneclaw', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (28, 'Bone Colossus', 'bonecolossus', 'The Elder Scrolls'),
  (29, 'Bonedrinker', 'bonedrinker', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (30, 'Bone Flayer', 'boneflayer', 'The Elder Scrolls'),
  (31, 'Bone Golem', 'bonegolem', 'Warcraft'),
  (32, 'Boneless', 'boneless', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (33, 'Bone Naga', 'bonenaga', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (34, 'Bone Warrior', 'bonewarrior', 'Diablo'),
  (35, 'Bone Wraith', 'bonewraith', 'Warcraft'),
  (36, 'Boneyard', 'boneyard', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (37, 'Brahmarakshasa', 'brahmarakshasa', 'Folklore, mythologies et archétypes fantastiques'),
  (38, 'Brain in a Jar', 'braininajar', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (39, 'Burning Dead', 'burningdead', 'Diablo'),
  (40, 'Cairn Wraith', 'cairnwraith', 'Warhammer Fantasy / Age of Sigmar'),
  (41, 'Caller in Darkness', 'callerindarkness', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (42, 'Chainghast', 'chainghast', 'Warhammer Fantasy / Age of Sigmar'),
  (43, 'Chainrasp', 'chainrasp', 'Warhammer Fantasy / Age of Sigmar'),
  (44, 'Chudail', 'chudail', 'Folklore, mythologies et archétypes fantastiques'),
  (45, 'Chu-u', 'chuu', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (46, 'Cihuateteo', 'cihuateteo', 'Folklore, mythologies et archétypes fantastiques'),
  (47, 'Coldlight Walker', 'coldlightwalker', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (48, 'Con-tinh', 'continh', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (49, 'Coronach', 'coronach', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (50, 'Corpsehound', 'corpsehound', 'Warcraft'),
  (51, 'Craventhrone Guard', 'craventhroneguard', 'Warhammer Fantasy / Age of Sigmar'),
  (52, 'Crawling Apocalypse', 'crawlingapocalypse', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (53, 'Crawling Claw', 'crawlingclaw', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (54, 'Crypt Cat', 'cryptcat', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (55, 'Crypt Fiend', 'cryptfiend', 'Warcraft'),
  (56, 'Crypt Lord', 'cryptlord', 'Warcraft'),
  (57, 'Crypt Thing', 'cryptthing', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (58, 'Curst', 'curst', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (59, 'Darkfallen', 'darkfallen', 'Warcraft'),
  (60, 'Dark Ranger', 'darkranger', 'Warcraft'),
  (61, 'Deathcharger', 'deathcharger', 'Warcraft'),
  (62, 'Deathfang', 'deathfang', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (63, 'Death Knight', 'deathknight', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (64, 'Deathlock', 'deathlock', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (65, 'Deathroc', 'deathroc', 'Warcraft'),
  (66, 'Death Shepherd', 'deathshepherd', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (67, 'Death Tyrant', 'deathtyrant', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (68, 'Demiliche', 'demiliche', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (69, 'Devourer', 'devourer', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (70, 'Direguard', 'direguard', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (71, 'Doomknight', 'doomknight', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (72, 'Doomsphere', 'doomsphere', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (73, 'Dracoliche', 'dracoliche', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (74, 'Draconic Shard', 'draconicshard', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (75, 'Dragon Priest', 'dragonpriest', 'The Elder Scrolls'),
  (76, 'Draug', 'draug', 'The Witcher'),
  (77, 'Draugir', 'draugir', 'The Witcher'),
  (78, 'Draugr', 'draugr', 'Folklore, mythologies et archétypes fantastiques'),
  (79, 'Dread', 'dread', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (80, 'Dreadblade Harrow', 'dreadbladeharrow', 'Warhammer Fantasy / Age of Sigmar'),
  (81, 'Dreadscythe Harridan', 'dreadscytheharridan', 'Warhammer Fantasy / Age of Sigmar'),
  (82, 'Dread Warrior', 'dreadwarrior', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (83, 'Dream Vestige', 'dreamvestige', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (84, 'Drekavac', 'drekavac', 'Folklore, mythologies et archétypes fantastiques'),
  (85, 'Drowned One', 'drownedone', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (86, 'Dust Wight', 'dustwight', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (87, 'Dybbuk', 'dybbuk', 'Folklore, mythologies et archétypes fantastiques'),
  (88, 'Edimmu', 'edimmu', 'Folklore, mythologies et archétypes fantastiques'),
  (89, 'Eidolon', 'eidolon', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (90, 'Elemental Lich', 'elementallich', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (91, 'Emberwyrm', 'emberwyrm', 'Warcraft'),
  (92, 'Entombed', 'entombed', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (93, 'Entropic Reaper', 'entropicreaper', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (94, 'Ephemeral Swarm', 'ephemeralswarm', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (95, 'Ethereal', 'ethereal', 'The Witcher'),
  (96, 'Eye of Fear and Flame', 'eyeoffearandflame', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (97, 'Famine Hound', 'faminehound', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (98, 'Fell Bat', 'fellbat', 'Warhammer Fantasy / Age of Sigmar'),
  (99, 'Fext', 'fext', 'Folklore, mythologies et archétypes fantastiques'),
  (100, 'Fey Lingerer', 'feylingerer', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (101, 'Flameskull', 'flameskull', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (102, 'Flesh Giant', 'fleshgiant', 'Warcraft'),
  (103, 'Flesh Titan', 'fleshtitan', 'Warcraft'),
  (104, 'Forgewraith', 'forgewraith', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (105, 'Forsaken', 'forsaken', 'Warcraft'),
  (106, 'Forsaken Shell', 'forsakenshell', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (107, 'Frost Wyrm', 'frostwyrm', 'Warcraft'),
  (108, 'Funayūrei', 'funayurei', 'Folklore, mythologies et archétypes fantastiques'),
  (109, 'Gashadokuro', 'gashadokuro', 'Folklore, mythologies et archétypes fantastiques'),
  (110, 'Geist', 'geist', 'Warcraft'),
  (111, 'Ghast', 'ghast', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (112, 'Ghost', 'ghost', 'Folklore, mythologies et archétypes fantastiques'),
  (113, 'Ghost Dragon', 'ghostdragon', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (114, 'Gjenganger', 'gjenganger', 'Folklore, mythologies et archétypes fantastiques'),
  (115, 'Glaivewraith Stalker', 'glaivewraithstalker', 'Warhammer Fantasy / Age of Sigmar'),
  (116, 'Gloom Wraith', 'gloomwraith', 'The Elder Scrolls'),
  (117, 'Goryō', 'goryo', 'Folklore, mythologies et archétypes fantastiques'),
  (118, 'Gothizzar Harvester', 'gothizzarharvester', 'Warhammer Fantasy / Age of Sigmar'),
  (119, 'Goule', 'goule', 'Folklore, mythologies et archétypes fantastiques'),
  (120, 'Grave Guard', 'graveguard', 'Warhammer Fantasy / Age of Sigmar'),
  (121, 'Gravehound', 'gravehound', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (122, 'Grave Mist', 'gravemist', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (123, 'Greater Mummy', 'greatermummy', 'Diablo'),
  (124, 'Greater Shadowrath', 'greatershadowrath', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (125, 'Great Ghul', 'greatghul', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (126, 'Great Wight', 'greatwight', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (127, 'Grimghast Reaper', 'grimghastreaper', 'Warhammer Fantasy / Age of Sigmar'),
  (128, 'Harvester', 'harvester', 'Dragon Age'),
  (129, 'Haunt', 'haunt', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (130, 'Haunting Revenant', 'hauntingrevenant', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (131, 'Heucuva', 'heucuva', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (132, 'Hexwraith', 'hexwraith', 'Warhammer Fantasy / Age of Sigmar'),
  (133, 'Hoarder Dragon', 'hoarderdragon', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (134, 'Hone-onna', 'honeonna', 'Folklore, mythologies et archétypes fantastiques'),
  (135, 'Horadrim Ancient', 'horadrimancient', 'Diablo'),
  (136, 'Horror Skeleton', 'horrorskeleton', 'Diablo'),
  (137, 'Hupia', 'hupia', 'Folklore, mythologies et archétypes fantastiques'),
  (138, 'Hym', 'hym', 'The Witcher'),
  (139, 'Immortis Guard', 'immortisguard', 'Warhammer Fantasy / Age of Sigmar'),
  (140, 'Jiangshi', 'jiangshi', 'Folklore, mythologies et archétypes fantastiques'),
  (141, 'Jikininki', 'jikininki', 'Folklore, mythologies et archétypes fantastiques'),
  (142, 'Ju-ju Zombie', 'jujuzombie', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (143, 'Kavalos Deathrider', 'kavalosdeathrider', 'Warhammer Fantasy / Age of Sigmar'),
  (144, 'Kukudh', 'kukudh', 'Folklore, mythologies et archétypes fantastiques'),
  (145, 'Lacedon', 'lacedon', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (146, 'Langsuyar', 'langsuyar', 'Folklore, mythologies et archétypes fantastiques'),
  (147, 'Lemure', 'lemure', 'Folklore, mythologies et archétypes fantastiques'),
  (148, 'Lichen Lich', 'lichenlich', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (149, 'Lugat', 'lugat', 'Folklore, mythologies et archétypes fantastiques'),
  (150, 'Magmawyrm', 'magmawyrm', 'Warcraft'),
  (151, 'Maw', 'maw', 'Warcraft'),
  (152, 'Mohrg', 'mohrg', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (153, 'Momie', 'momie', 'Folklore, mythologies et archétypes fantastiques'),
  (154, 'Morghast', 'morghast', 'Warhammer Fantasy / Age of Sigmar'),
  (155, 'Moroi', 'moroi', 'Folklore, mythologies et archétypes fantastiques'),
  (156, 'Mortek Guard', 'mortekguard', 'Warhammer Fantasy / Age of Sigmar'),
  (157, 'Mourngul', 'mourngul', 'Warhammer Fantasy / Age of Sigmar'),
  (158, 'Mummy Lord', 'mummylord', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (159, 'Mur''ghoul', 'murghoul', 'Warcraft'),
  (160, 'Myling', 'myling', 'Folklore, mythologies et archétypes fantastiques'),
  (161, 'Myrmourn Banshee', 'myrmournbanshee', 'Warhammer Fantasy / Age of Sigmar'),
  (162, 'Nachzehrer', 'nachzehrer', 'Folklore, mythologies et archétypes fantastiques'),
  (163, 'Necropolis Stalker', 'necropolisstalker', 'Warhammer Fantasy / Age of Sigmar'),
  (164, 'Necrosphinx', 'necrosphinx', 'Warhammer Fantasy / Age of Sigmar'),
  (165, 'Nightwalker', 'nightwalker', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (166, 'Nightwraith', 'nightwraith', 'The Witcher'),
  (167, 'Noonwraith', 'noonwraith', 'The Witcher'),
  (168, 'Nosferatu', 'nosferatu', 'Folklore, mythologies et archétypes fantastiques'),
  (169, 'Oblivion Knight', 'oblivionknight', 'Diablo'),
  (170, 'Onryō', 'onryo', 'Folklore, mythologies et archétypes fantastiques'),
  (171, 'Orb Wraith', 'orbwraith', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (172, 'Orek', 'orek', 'Folklore, mythologies et archétypes fantastiques'),
  (173, 'Ossiarch Bonereaper', 'ossiarchbonereaper', 'Warhammer Fantasy / Age of Sigmar'),
  (174, 'Oupyr', 'oupyr', 'Folklore, mythologies et archétypes fantastiques'),
  (175, 'Penitent', 'penitent', 'The Witcher'),
  (176, 'Plagued Dragon', 'plagueddragon', 'Warcraft'),
  (177, 'Plague Eruptor', 'plagueeruptor', 'Warcraft'),
  (178, 'Plague Maiden', 'plaguemaiden', 'The Witcher'),
  (179, 'Pocong', 'pocong', 'Folklore, mythologies et archétypes fantastiques'),
  (180, 'Poltergeist', 'poltergeist', 'Folklore, mythologies et archétypes fantastiques'),
  (181, 'Pontianak', 'pontianak', 'Folklore, mythologies et archétypes fantastiques'),
  (182, 'Pricolici', 'pricolici', 'Folklore, mythologies et archétypes fantastiques'),
  (183, 'Qutrub', 'qutrub', 'Folklore, mythologies et archétypes fantastiques'),
  (184, 'Reanimated Horde', 'reanimatedhorde', 'Diablo'),
  (185, 'Red Miasmal', 'redmiasmal', 'The Witcher'),
  (186, 'Returned', 'returned', 'Diablo'),
  (187, 'Revenant', 'revenant', 'Folklore, mythologies et archétypes fantastiques'),
  (188, 'Ro-langs', 'rolangs', 'Folklore, mythologies et archétypes fantastiques'),
  (189, 'Rusalka', 'rusalka', 'Folklore, mythologies et archétypes fantastiques'),
  (190, 'San''layn', 'sanlayn', 'Warcraft'),
  (191, 'Scourge Gargoyle', 'scourgegargoyle', 'Warcraft'),
  (192, 'Sepulchral Stalker', 'sepulchralstalker', 'Warhammer Fantasy / Age of Sigmar'),
  (193, 'Shadehound', 'shadehound', 'Warcraft'),
  (194, 'Shadow', 'shadow', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (195, 'Shiryō', 'shiryo', 'Folklore, mythologies et archétypes fantastiques'),
  (196, 'Skadegamutc', 'skadegamutc', 'Folklore, mythologies et archétypes fantastiques'),
  (197, 'Skeletal Dragon', 'skeletaldragon', 'Warcraft'),
  (198, 'Skull Lord', 'skulllord', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (199, 'Sluagh', 'sluagh', 'Folklore, mythologies et archétypes fantastiques'),
  (200, 'Soucouyant', 'soucouyant', 'Folklore, mythologies et archétypes fantastiques'),
  (201, 'Soul-rotted Flesh', 'soulrottedflesh', 'Warcraft'),
  (202, 'Spawn of Kyuss', 'spawnofkyuss', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (203, 'Specter', 'specter', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (204, 'Spirit Host', 'spirithost', 'Warhammer Fantasy / Age of Sigmar'),
  (205, 'Spirit Torment', 'spirittorment', 'Warhammer Fantasy / Age of Sigmar'),
  (206, 'Squelette', 'squelette', 'Folklore, mythologies et archétypes fantastiques'),
  (207, 'Strigoi', 'strigoi', 'Folklore, mythologies et archétypes fantastiques'),
  (208, 'Strzyga', 'strzyga', 'Folklore, mythologies et archétypes fantastiques'),
  (209, 'Sword Wraith', 'swordwraith', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (210, 'Terrorgheist', 'terrorgheist', 'Warhammer Fantasy / Age of Sigmar'),
  (211, 'Tomb Banshee', 'tombbanshee', 'Warhammer Fantasy / Age of Sigmar'),
  (212, 'Tomb Scorpion', 'tombscorpion', 'Warhammer Fantasy / Age of Sigmar'),
  (213, 'Topi', 'topi', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (214, 'Toyol', 'toyol', 'Folklore, mythologies et archétypes fantastiques'),
  (215, 'Ubume', 'ubume', 'Folklore, mythologies et archétypes fantastiques'),
  (216, 'Umbra', 'umbra', 'The Witcher'),
  (217, 'Unraveller', 'unraveller', 'Diablo'),
  (218, 'Ushabti', 'ushabti', 'Warhammer Fantasy / Age of Sigmar'),
  (219, 'Val''kyr', 'valkyr', 'Warcraft'),
  (220, 'Vampire', 'vampire', 'Folklore, mythologies et archétypes fantastiques'),
  (221, 'Vampire Nightbringer', 'vampirenightbringer', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (222, 'Vampire Spawn', 'vampirespawn', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (223, 'Vampiric Mind Flayer', 'vampiricmindflayer', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (224, 'Vampiric Mist', 'vampiricmist', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (225, 'Vargheist', 'vargheist', 'Warhammer Fantasy / Age of Sigmar'),
  (226, 'Varghulf', 'varghulf', 'Warhammer Fantasy / Age of Sigmar'),
  (227, 'Vargul', 'vargul', 'Warcraft'),
  (228, 'Vetala', 'vetala', 'Folklore, mythologies et archétypes fantastiques'),
  (229, 'Vourdalak', 'vourdalak', 'Folklore, mythologies et archétypes fantastiques'),
  (230, 'Vrykolakas', 'vrykolakas', 'Folklore, mythologies et archétypes fantastiques'),
  (231, 'Werewolf', 'werewolf', 'The Elder Scrolls'),
  (232, 'Wicht', 'wicht', 'Folklore, mythologies et archétypes fantastiques'),
  (233, 'Wiedergänger', 'wiederganger', 'Folklore, mythologies et archétypes fantastiques'),
  (234, 'Wight', 'wight', 'Folklore, mythologies et archétypes fantastiques'),
  (235, 'Wight King', 'wightking', 'Warhammer Fantasy / Age of Sigmar'),
  (236, 'Will-o''-Wisp', 'willowisp', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (237, 'Winged Horror', 'wingedhorror', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (238, 'Witherling', 'witherling', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (239, 'Wraith', 'wraith', 'Folklore, mythologies et archétypes fantastiques'),
  (240, 'Yellow Musk Zombie', 'yellowmuskzombie', 'Donjons & Dragons / Forgotten Realms et dérivés'),
  (241, 'Yūrei', 'yurei', 'Folklore, mythologies et archétypes fantastiques'),
  (242, 'Zombie', 'zombie', 'Folklore, mythologies et archétypes fantastiques'),
  (243, 'Zombie Dragon', 'zombiedragon', 'Warhammer Fantasy / Age of Sigmar'),
  (244, 'Zombie Lord', 'zombielord', 'Donjons & Dragons / Forgotten Realms et dérivés');

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
