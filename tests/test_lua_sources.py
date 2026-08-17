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
