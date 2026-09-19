from pathlib import Path

from luaparser import ast


ROOT = Path(__file__).resolve().parents[1]


def test_all_theocraft_lua_sources_parse() -> None:
    sources = sorted((ROOT / "mods").glob("theocraft_*/*.lua"))
    assert sources
    for source in sources:
        ast.parse(source.read_text(encoding="utf-8"))


def test_android_game_assembly_bundles_import_support() -> None:
    script = (ROOT / "scripts" / "Assemble-Game.ps1").read_text(encoding="utf-8")
    assert '"theocraft_villagers", "theocraft_halloween", "theocraft_circus", "theocraft_import"' in script
    assert 'mods\\theocraft_villagers\\settingtypes.txt' in script
    assert 'mods\\theocraft_halloween\\settingtypes.txt' in script
    assert 'mods\\theocraft_circus\\settingtypes.txt' in script
    assert 'Join-Path $outputPath "settingtypes.txt"' in script
    assert "secure.http_mods" not in script


def test_branded_engine_patch_allows_villager_http() -> None:
    patch = (ROOT / "patches" / "luanti-5.16.1-theocraft.patch").read_text(encoding="utf-8")
    assert 'setDefault("secure.http_mods", "theocraft_villagers")' in patch
    assert "ICONV_INCLUDE_DIR" in patch
    assert "resourceConfigurations += ['en']" in patch


def test_import_placeholder_uses_a_bundled_texture() -> None:
    source = (ROOT / "mods" / "theocraft_import" / "init.lua").read_text(encoding="utf-8")
    assert '"default_stone.png^[colorize:' in source
    assert (ROOT / "vendor" / "voxelibre" / "textures" / "default_stone.png").is_file()


def test_invincible_villagers_setting_is_exposed() -> None:
    settings = (ROOT / "mods" / "theocraft_villagers" / "settingtypes.txt").read_text(
        encoding="utf-8"
    )
    assert "theocraft_villagers_invincible (Invincible villagers) bool false" in settings


def test_halloween_feature_pack_is_bundled() -> None:
    source = (ROOT / "mods" / "theocraft_halloween" / "init.lua").read_text(
        encoding="utf-8"
    )
    assert 'register_craftitem("theocraft_halloween:candy"' in source
    assert 'register_node("theocraft_halloween:treat_bowl"' in source
    assert 'register_chatcommand("halloween"' in source
    assert 'minetest.add_entity(spawn_pos, "mobs_mc:bat")' in source

    ui = (ROOT / "mods" / "theocraft_villagers" / "ui.lua").read_text(
        encoding="utf-8"
    )
    assert "trick_or_treat" in ui


def test_circus_pack_is_bundled_and_safe() -> None:
    mod_root = ROOT / "mods" / "theocraft_circus"
    init = (mod_root / "init.lua").read_text(encoding="utf-8")
    nodes = (mod_root / "nodes.lua").read_text(encoding="utf-8")
    items = (mod_root / "items.lua").read_text(encoding="utf-8")
    props = (mod_root / "props.lua").read_text(encoding="utf-8")
    challenges = (mod_root / "challenges.lua").read_text(encoding="utf-8")
    arena = (mod_root / "arena.lua").read_text(encoding="utf-8")
    mode = (mod_root / "mode.lua").read_text(encoding="utf-8")
    # Blocks: tent canvas, poles, ring, seats, lights, curtains, stage, booths, mats, beam, crate.
    for name in (
        'theocraft_circus:canvas_red',
        'theocraft_circus:pole_gold',
        'theocraft_circus:ring_sawdust',
        'theocraft_circus:seat_vip',
        'theocraft_circus:spotlight_off',
        'theocraft_circus:fairy_light',
        'theocraft_circus:curtain_red_closed',
        'theocraft_circus:stage',
        'theocraft_circus:ticket_booth',
        'theocraft_circus:popcorn_stand',
        'theocraft_circus:prize_stand',
        'theocraft_circus:practice_mat_red',
        'theocraft_circus:balance_beam',
        'theocraft_circus:crate',
    ):
        assert name in nodes, name
    # Items: hat, cane, juggling, hoop, ribbon, ticket, popcorn, popper, medal, disc, wand.
    for name in (
        'theocraft_circus:ringmaster_hat',
        'theocraft_circus:ringmaster_cane',
        'theocraft_circus:juggling_balls',
        'theocraft_circus:juggling_clubs',
        'theocraft_circus:hoop',
        'theocraft_circus:acrobat_ribbon',
        'theocraft_circus:ticket',
        'theocraft_circus:popcorn',
        'theocraft_circus:confetti_popper',
        'theocraft_circus:performer_medal',
        'theocraft_circus:music_disc',
        'theocraft_circus:magic_wand',
    ):
        assert name in items, name
    # Props: rope, trapeze, swing, trampoline, rola bola, hoop stand, bell, applause, music, switch.
    for name in (
        'theocraft_circus:tightrope',
        'theocraft_circus:trapeze',
        'theocraft_circus:swing_rope',
        'theocraft_circus:trampoline',
        'theocraft_circus:rola_bola',
        'theocraft_circus:hoop_stand',
        'theocraft_circus:performance_bell',
        'theocraft_circus:applause_box',
        'theocraft_circus:music_box_off',
        'theocraft_circus:curtain_switch',
    ):
        assert name in props, name
    # Show mode, challenges, and Theo's Circus Mode wiring.
    assert 'register_chatcommand("circus"' in challenges
    assert 'register_chatcommand("tcshow"' in challenges
    assert 'register_chatcommand("tccircuskit"' in challenges
    assert 'theocraft_circus_theo_mode' in (mod_root / "settingtypes.txt").read_text(encoding="utf-8")
    assert 'register_on_player_hpchange' in mode
    assert 'Amazing balance!' in init
    # Arena auto-builder: /build circus_arena with size variants and show finale.
    assert 'register_chatcommand("build"' in arena
    assert 'circus_arena' in arena
    for variant in ("small", "medium", "large", "rainbow", "theos_show"):
        assert variant in arena, variant
    for label in (
        "Welcome to Theo",
        "Main Ring",
        "Tightrope Practice",
        "Trapeze Zone",
        "Juggling Corner",
        "Hoop Jump Challenge",
        "Backstage",
        "Popcorn Stand",
        "Prize Stand",
        "Press the Bell to Start the Show!",
        "Theo the Ringmaster",
        "Theo's Circus Show has begun!",
    ):
        assert label in arena or label in challenges, label
    assert 'is_protected' in arena
    assert 'force' in arena
    # Safety: no explosives, entity spawning, portals, or damage-dealing code.
    # (Checked as code patterns so safety comments describing what is *not*
    # included cannot trip the test.)
    combined = init + nodes + items + props + challenges + arena + mode
    combined_lower = combined.lower()
    for banned in ("tnt:", "tnt_", "explode(", "detonate", "spawneggs",
                   "spawn_entity(", "add_entity(", "set_hp(", "punch(",
                   "register_entity("):
        assert banned not in combined_lower, banned
