from __future__ import annotations

import json
import math
import sqlite3
import struct
import sys
import zlib
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "world_import"))

from theocraft_importer.anvil import BlockState, decode_palette_indices  # noqa: E402
from theocraft_importer.importer import import_world  # noqa: E402
from theocraft_importer.mapblock import serialize_mapblock  # noqa: E402
from theocraft_importer.mapping import BlockMapper, UNKNOWN_NODE  # noqa: E402


def _signed_words(words: list[int]) -> list[int]:
    return [word if word < 1 << 63 else word - (1 << 64) for word in words]


def _pack_compact(values: list[int], bits: int) -> list[int]:
    words = [0] * math.ceil(len(values) * bits / 64)
    mask = (1 << bits) - 1
    for index, value in enumerate(values):
        bit_index = index * bits
        word_index, offset = divmod(bit_index, 64)
        words[word_index] |= (value & mask) << offset
        words[word_index] &= (1 << 64) - 1
        if offset + bits > 64:
            words[word_index + 1] |= (value & mask) >> (64 - offset)
    return _signed_words(words)


def _pack_padded(values: list[int], bits: int) -> list[int]:
    values_per_word = 64 // bits
    words = [0] * math.ceil(len(values) / values_per_word)
    for index, value in enumerate(values):
        words[index // values_per_word] |= value << ((index % values_per_word) * bits)
    return _signed_words(words)


def test_decodes_pre_and_post_116_palette_packing() -> None:
    values = [index % 17 for index in range(4096)]
    assert list(decode_palette_indices(_pack_compact(values, 5), 17, 2200)) == values
    assert list(decode_palette_indices(_pack_padded(values, 5), 17, 3105)) == values


def test_mapping_preserves_orientation_and_marks_unknowns() -> None:
    mapper = BlockMapper()
    oak_x = mapper.map(BlockState("minecraft:oak_log", {"axis": "x"}))
    assert (oak_x.node, oak_x.param2) == ("mcl_core:tree", 12)
    top_stair = mapper.map(BlockState("minecraft:cobblestone_stairs", {"facing": "east", "half": "top"}))
    assert (top_stair.node, top_stair.param2) == ("mcl_stairs:stair_cobble", 23)
    stone_stair = mapper.map(BlockState("minecraft:stone_stairs", {"facing": "north"}))
    assert stone_stair.node == "mcl_stairs:stair_stone_rough"
    unknown = mapper.map(BlockState("minecraft:not_added_yet", {}))
    assert not unknown.known
    assert unknown.node == UNKNOWN_NODE


def test_mapblock_serializer_writes_generated_v25_data() -> None:
    payload = serialize_mapblock(["mcl_core:stone"] * 4096, [0] * 4096, underground=True)
    assert payload[0] == 25
    assert payload[1] & 0x01
    assert not payload[1] & 0x08
    first_stream = zlib.decompressobj()
    bulk = first_stream.decompress(payload[4:])
    assert len(bulk) == 4096 * 4
    metadata_stream = zlib.decompressobj()
    assert metadata_stream.decompress(first_stream.unused_data) == b"\0"


def _nbt_string(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack(">H", len(encoded)) + encoded


def _named(tag: int, name: str, payload: bytes) -> bytes:
    return bytes([tag]) + _nbt_string(name) + payload


def _compound(*children: bytes) -> bytes:
    return b"".join(children) + b"\0"


def _modern_chunk(block_name: str, section_y: int = -1) -> bytes:
    palette_entry = _compound(_named(8, "Name", _nbt_string(block_name)))
    palette = bytes([10]) + struct.pack(">i", 1) + palette_entry
    block_states = _compound(_named(9, "palette", palette))
    section = _compound(
        _named(1, "Y", struct.pack(">b", section_y)),
        _named(10, "block_states", block_states),
    )
    sections = bytes([10]) + struct.pack(">i", 1) + section
    root = _compound(
        _named(3, "DataVersion", struct.pack(">i", 3105)),
        _named(3, "xPos", struct.pack(">i", 0)),
        _named(3, "zPos", struct.pack(">i", 0)),
        _named(9, "sections", sections),
    )
    return bytes([10]) + _nbt_string("") + root


def _write_region(world: Path, block_name: str) -> None:
    region = world / "region"
    region.mkdir(parents=True)
    compressed = zlib.compress(_modern_chunk(block_name))
    record = struct.pack(">I", len(compressed) + 1) + b"\x02" + compressed
    sectors = math.ceil(len(record) / 4096)
    location = (2).to_bytes(3, "big") + bytes([sectors])
    header = location + bytes(4096 - 4) + bytes(4096)
    (region / "r.0.0.mca").write_bytes(header + record + bytes(sectors * 4096 - len(record)))


def test_end_to_end_modern_world_conversion_and_unknown_report(tmp_path: Path) -> None:
    source = tmp_path / "minecraft"
    _write_region(source, "minecraft:future_block")
    destination = tmp_path / "theocraft"

    result = import_world(source, destination)
    assert result.chunks == 1
    assert result.mapblocks == 1
    assert result.unknown_blocks == 4096
    report = json.loads((destination / "import-report.json").read_text(encoding="utf-8"))
    assert report["unknown_states"] == {"minecraft:future_block": 4096}
    assert "gameid = theocraft" in (destination / "world.mt").read_text(encoding="utf-8")
    with sqlite3.connect(destination / "map.sqlite") as database:
        x, y, z, data = database.execute("SELECT x, y, z, data FROM blocks").fetchone()
    assert (x, y, z) == (0, -1, 0)
    assert data[0] == 25
    assert UNKNOWN_NODE.encode() in data

    with pytest.raises(ValueError, match="refusing to overwrite"):
        import_world(source, destination)
