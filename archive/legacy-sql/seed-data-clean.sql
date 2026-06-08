-- ============================================================
-- ADEC Sensor Network Tracker — Clean Seed Data
-- Run after schema migration. All sensors start with no type,
-- no status, and no event history.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. COMMUNITIES
-- ============================================================

INSERT INTO communities (id, name) VALUES
    ('anchorage',      'Anchorage'),
    ('badger',         'Badger'),
    ('bethel',         'Bethel'),
    ('big-lake',       'Big Lake'),
    ('chickaloon',     'Chickaloon'),
    ('cordova',        'Cordova'),
    ('delta-junction', 'Delta Junction'),
    ('fairbanks',      'Fairbanks'),
    ('galena',         'Galena'),
    ('gerstle-river',  'Gerstle River'),
    ('glennallen',     'Glennallen'),
    ('goldstream',     'Goldstream'),
    ('haines',         'Haines'),
    ('homer',          'Homer'),
    ('hoonah',         'Hoonah'),
    ('juneau',         'Juneau'),
    ('kenai',          'Kenai'),
    ('ketchikan',      'Ketchikan'),
    ('kodiak',         'Kodiak'),
    ('kotzebue',       'Kotzebue'),
    ('napaskiak',      'Napaskiak'),
    ('nenana',         'Nenana'),
    ('ninilchik',      'Ninilchik'),
    ('nome',           'Nome'),
    ('palmer',         'Palmer'),
    ('salcha',         'Salcha'),
    ('seward',         'Seward'),
    ('sitka',          'Sitka'),
    ('skagway',        'Skagway'),
    ('soldotna',       'Soldotna'),
    ('talkeetna',      'Talkeetna'),
    ('tok',            'Tok'),
    ('tyonek',         'Tyonek'),
    ('valdez',         'Valdez'),
    ('wasilla',        'Wasilla'),
    ('willow',         'Willow'),
    ('wrangell',       'Wrangell'),
    ('yakutat',        'Yakutat')
ON CONFLICT (id) DO NOTHING;

-- Child communities
INSERT INTO communities (id, name, parent_id) VALUES
    ('anc-garden',                   'Garden',                        'anchorage'),
    ('anc-lab',                      'Anc Lab',                       'anchorage'),
    ('campbell-creek-science-center', 'Campbell Creek Science Center', 'anchorage'),
    ('anne-wien-elementary',          'Anne Wien Elementary School',   'fairbanks'),
    ('fbx-lab',                      'Fbx Lab',                       'fairbanks'),
    ('fbx-ncore',                    'NCore',                         'fairbanks'),
    ('jnu-5th-street',               '5th Street',                    'juneau'),
    ('jnu-alaska-state-museum',      'Alaska State Museum',           'juneau'),
    ('jnu-floyd-dryden',             'Floyd Dryden',                  'juneau'),
    ('jnu-lab',                      'Jnu Lab',                       'juneau')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 2. COMMUNITY TAGS
-- ============================================================

INSERT INTO community_tags (community_id, tag) VALUES
    ('anc-garden',       'Regulatory Site'),
    ('fbx-ncore',        'Regulatory Site'),
    ('jnu-floyd-dryden', 'Regulatory Site'),
    ('glennallen',       'BLM'),
    ('talkeetna',        'BLM');

-- ============================================================
-- 3. SENSORS — Clean slate: no type, no status, no history
--    Users will assign types and statuses in Setup Mode
-- ============================================================

INSERT INTO sensors (id, community_id) VALUES
    ('MOD-00442', 'napaskiak'),
    ('MOD-00443', 'fbx-ncore'),
    ('MOD-00444', 'wrangell'),
    ('MOD-00445', 'anc-lab'),
    ('MOD-00446', 'galena'),
    ('MOD-00447', 'delta-junction'),
    ('MOD-00448', 'goldstream'),
    ('MOD-00449', 'ketchikan'),
    ('MOD-00450', 'haines'),
    ('MOD-00451', 'anc-lab'),
    ('MOD-00452', 'hoonah'),
    ('MOD-00453', 'skagway'),
    ('MOD-00454', 'sitka'),
    ('MOD-00455', 'jnu-lab'),
    ('MOD-00456', 'jnu-lab'),
    ('MOD-00458', 'valdez'),
    ('MOD-00459', 'soldotna'),
    ('MOD-00460', 'anc-garden'),
    ('MOD-00461', 'ninilchik'),
    ('MOD-00462', 'campbell-creek-science-center'),
    ('MOD-00463', 'anc-garden'),
    ('MOD-00464', 'homer'),
    ('MOD-00465', 'seward'),
    ('MOD-00466', 'glennallen'),
    ('MOD-00467', 'talkeetna'),
    ('MOD-00468', 'big-lake'),
    ('MOD-00469', 'tyonek'),
    ('MOD-00470', 'willow'),
    ('MOD-00471', 'anc-garden'),
    ('MOD-00649', 'chickaloon'),
    ('MOD-00650', 'kenai'),
    ('MOD-00651', 'fbx-ncore'),
    ('MOD-00652', 'fbx-ncore'),
    ('MOD-00653', 'tok'),
    ('MOD-00654', 'nome'),
    ('MOD-00655', 'nenana'),
    ('MOD-00656', NULL),
    ('MOD-00657', 'palmer'),
    ('MOD-00658', 'yakutat'),
    ('MOD-00659', 'bethel'),
    ('MOD-00660', 'kodiak'),
    ('MOD-00662', 'kotzebue'),
    ('MOD-00663', 'wasilla'),
    ('MOD-00664', 'badger'),
    ('MOD-00665', 'jnu-lab'),
    ('MOD-00666', NULL),
    ('MOD-00667', 'cordova'),
    ('MOD-00668', 'fbx-ncore'),
    ('MOD-00669', 'jnu-lab'),
    ('MOD-00670', NULL),
    ('MOD-00671', 'anne-wien-elementary'),
    ('MOD-00672', 'salcha'),
    ('MOD-00673', 'gerstle-river'),
    ('MOD-00674', NULL),
    ('MOD-X-PM-01656', 'anc-lab'),
    ('MOD-X-PM-01657', 'anc-lab'),
    ('MOD-X-PM-01658', NULL),
    ('MOD-X-PM-01754', 'fbx-ncore'),
    ('MOD-X-PM-01755', 'fbx-ncore'),
    ('MOD-X-PM-01757', 'fbx-ncore'),
    ('MOD-X-PM-01758', 'fbx-ncore'),
    ('MOD-X-PM-01759', 'fbx-ncore'),
    ('MOD-X-PM-01760', 'fbx-ncore'),
    ('MOD-X-PM-01761', 'fbx-ncore'),
    ('MOD-X-PM-01762', 'anc-lab'),
    ('MOD-X-PM-01763', 'fbx-ncore'),
    ('MOD-X-PM-01764', 'fbx-ncore'),
    ('MOD-X-PM-01765', 'anc-lab'),
    ('MOD-X-PM-01766', 'fbx-ncore')
ON CONFLICT (id) DO NOTHING;

COMMIT;
