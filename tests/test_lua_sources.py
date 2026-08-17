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
    assert '"theocraft_villagers", "theocraft_import"' in script
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
