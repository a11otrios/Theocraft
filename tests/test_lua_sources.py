from pathlib import Path

from luaparser import ast


ROOT = Path(__file__).resolve().parents[1]


def test_all_theocraft_lua_sources_parse() -> None:
    sources = sorted((ROOT / "mods" / "theocraft_villagers").glob("*.lua"))
    assert sources
    for source in sources:
        ast.parse(source.read_text(encoding="utf-8"))
