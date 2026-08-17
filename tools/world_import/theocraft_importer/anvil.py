"""Minecraft Java region and chunk-section reader."""

from __future__ import annotations

import gzip
import math
import re
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Mapping

from .nbt import NBTError, read_nbt


REGION_NAME = re.compile(r"^r\.(-?\d+)\.(-?\d+)\.mca$")


class AnvilError(ValueError):
    pass


@dataclass(frozen=True)
class BlockState:
    name: str
    properties: Mapping[str, str]

    @property
    def report_key(self) -> str:
        if not self.properties:
            return self.name
        properties = ",".join(f"{key}={self.properties[key]}" for key in sorted(self.properties))
        return f"{self.name}[{properties}]"

    def __hash__(self) -> int:
        return hash((self.name, tuple(sorted(self.properties.items()))))


@dataclass(frozen=True)
class SectionRecord:
    chunk_x: int
    section_y: int
    chunk_z: int
    data_version: int
    palette: tuple[BlockState, ...]
    indices: tuple[int, ...]


def _unsigned(value: int) -> int:
    return value & ((1 << 64) - 1)


def decode_palette_indices(data: list[int], palette_size: int, data_version: int) -> tuple[int, ...]:
    if palette_size < 1:
        raise AnvilError("block-state palette is empty")
    if palette_size == 1:
        return (0,) * 4096
    bits = max(4, (palette_size - 1).bit_length())
    words = [_unsigned(value) for value in data]
    values_per_word = 64 // bits
    padded_length = math.ceil(4096 / values_per_word)
    compact_length = math.ceil(4096 * bits / 64)
    if len(words) not in {padded_length, compact_length}:
        raise AnvilError(
            f"unexpected block-state data length {len(words)} for palette {palette_size} "
            f"(expected {compact_length} or {padded_length})"
        )

    padded = len(words) == padded_length and (
        padded_length != compact_length or data_version >= 2529
    )
    mask = (1 << bits) - 1
    result: list[int] = []
    if padded:
        for index in range(4096):
            word = words[index // values_per_word]
            value = (word >> ((index % values_per_word) * bits)) & mask
            result.append(value)
    else:
        for index in range(4096):
            bit_index = index * bits
            word_index, offset = divmod(bit_index, 64)
            value = words[word_index] >> offset
            if offset + bits > 64:
                value |= words[word_index + 1] << (64 - offset)
            result.append(value & mask)
    if any(value >= palette_size for value in result):
        raise AnvilError("block-state data references an index outside its palette")
    return tuple(result)


LEGACY_NAMES: dict[int, tuple[str, ...]] = {
    0: ("minecraft:air",),
    1: ("minecraft:stone", "minecraft:granite", "minecraft:polished_granite", "minecraft:diorite", "minecraft:polished_diorite", "minecraft:andesite", "minecraft:polished_andesite"),
    2: ("minecraft:grass_block",),
    3: ("minecraft:dirt", "minecraft:coarse_dirt", "minecraft:podzol"),
    4: ("minecraft:cobblestone",),
    5: tuple(f"minecraft:{wood}_planks" for wood in ("oak", "spruce", "birch", "jungle", "acacia", "dark_oak")),
    7: ("minecraft:bedrock",),
    8: ("minecraft:water",),
    9: ("minecraft:water",),
    10: ("minecraft:lava",),
    11: ("minecraft:lava",),
    12: ("minecraft:sand", "minecraft:red_sand"),
    13: ("minecraft:gravel",),
    14: ("minecraft:gold_ore",),
    15: ("minecraft:iron_ore",),
    16: ("minecraft:coal_ore",),
    20: ("minecraft:glass",),
    21: ("minecraft:lapis_ore",),
    22: ("minecraft:lapis_block",),
    24: ("minecraft:sandstone", "minecraft:chiseled_sandstone", "minecraft:cut_sandstone"),
    41: ("minecraft:gold_block",),
    42: ("minecraft:iron_block",),
    45: ("minecraft:bricks",),
    47: ("minecraft:bookshelf",),
    48: ("minecraft:mossy_cobblestone",),
    49: ("minecraft:obsidian",),
    56: ("minecraft:diamond_ore",),
    57: ("minecraft:diamond_block",),
    73: ("minecraft:redstone_ore",),
    79: ("minecraft:ice",),
    80: ("minecraft:snow_block",),
    82: ("minecraft:clay",),
    87: ("minecraft:netherrack",),
    88: ("minecraft:soul_sand",),
    89: ("minecraft:glowstone",),
    98: ("minecraft:stone_bricks", "minecraft:mossy_stone_bricks", "minecraft:cracked_stone_bricks", "minecraft:chiseled_stone_bricks"),
    103: ("minecraft:melon",),
    112: ("minecraft:nether_bricks",),
    121: ("minecraft:end_stone",),
    129: ("minecraft:emerald_ore",),
    133: ("minecraft:emerald_block",),
    152: ("minecraft:redstone_block",),
    155: ("minecraft:quartz_block", "minecraft:chiseled_quartz_block", "minecraft:quartz_pillar"),
    173: ("minecraft:coal_block",),
    174: ("minecraft:packed_ice",),
}


def _legacy_state(block_id: int, data: int) -> BlockState:
    variants = LEGACY_NAMES.get(block_id)
    if not variants:
        return BlockState(f"legacy:{block_id}:{data}", {})
    return BlockState(variants[min(data, len(variants) - 1)], {})


def _nibbles(data: bytes) -> list[int]:
    result: list[int] = []
    for byte in data:
        result.extend((byte & 0x0F, byte >> 4))
    return result


def _legacy_section(section: Mapping[str, object]) -> tuple[tuple[BlockState, ...], tuple[int, ...]]:
    blocks = section.get("Blocks")
    if not isinstance(blocks, (bytes, bytearray)) or len(blocks) != 4096:
        raise AnvilError("legacy section has no 4096-byte Blocks array")
    data = _nibbles(section.get("Data", bytes(2048)))
    add = _nibbles(section.get("Add", bytes(2048)))
    states = [_legacy_state(blocks[index] | (add[index] << 8), data[index]) for index in range(4096)]
    palette: list[BlockState] = []
    palette_lookup: dict[BlockState, int] = {}
    indices: list[int] = []
    for state in states:
        if state not in palette_lookup:
            palette_lookup[state] = len(palette)
            palette.append(state)
        indices.append(palette_lookup[state])
    return tuple(palette), tuple(indices)


def _modern_section(section: Mapping[str, object], data_version: int) -> tuple[tuple[BlockState, ...], tuple[int, ...]]:
    state_container = section.get("block_states")
    if isinstance(state_container, dict):
        palette_data = state_container.get("palette")
        packed_data = state_container.get("data", [])
    else:
        palette_data = section.get("Palette")
        packed_data = section.get("BlockStates", [])
    if not isinstance(palette_data, list):
        raise AnvilError("modern section has no block-state palette")
    palette: list[BlockState] = []
    for raw in palette_data:
        if not isinstance(raw, dict) or not isinstance(raw.get("Name"), str):
            raise AnvilError("invalid entry in block-state palette")
        properties = raw.get("Properties", {})
        if not isinstance(properties, dict):
            properties = {}
        palette.append(BlockState(raw["Name"], {str(k): str(v) for k, v in properties.items()}))
    if not isinstance(packed_data, list):
        raise AnvilError("block-state data is not a long array")
    return tuple(palette), decode_palette_indices(packed_data, len(palette), data_version)


def _decompress(compression: int, payload: bytes) -> bytes:
    if compression == 1:
        return gzip.decompress(payload)
    if compression == 2:
        return zlib.decompress(payload)
    if compression == 3:
        return payload
    if compression == 4:
        raise AnvilError("Minecraft LZ4-compressed chunks are not supported yet; open and save the world with zlib compression")
    raise AnvilError(f"unsupported Anvil compression type {compression}")


def _chunk_payload(region_file: Path, chunk_index: int, location: bytes) -> bytes:
    sector_offset = int.from_bytes(location[:3], "big") * 4096
    if sector_offset == 0:
        raise AnvilError("empty chunk location")
    with region_file.open("rb") as handle:
        handle.seek(sector_offset)
        length = int.from_bytes(handle.read(4), "big")
        compression_raw = handle.read(1)
        if len(compression_raw) != 1 or length < 1:
            raise AnvilError(f"invalid chunk header in {region_file.name}")
        compression = compression_raw[0]
        external = bool(compression & 0x80)
        compression &= 0x7F
        if external:
            region_x, region_z = map(int, REGION_NAME.match(region_file.name).groups())
            local_x, local_z = chunk_index % 32, chunk_index // 32
            chunk_x, chunk_z = region_x * 32 + local_x, region_z * 32 + local_z
            payload = (region_file.parent / f"c.{chunk_x}.{chunk_z}.mcc").read_bytes()
        else:
            payload = handle.read(length - 1)
    return _decompress(compression, payload)


def iter_world_sections(world: Path, max_chunks: int | None = None) -> Iterator[SectionRecord]:
    region_directory = world / "region"
    if not region_directory.is_dir():
        raise AnvilError(f"Minecraft Java region directory not found: {region_directory}")
    chunks_read = 0
    for region_file in sorted(region_directory.glob("r.*.*.mca")):
        match = REGION_NAME.match(region_file.name)
        if not match:
            continue
        region_x, region_z = map(int, match.groups())
        with region_file.open("rb") as handle:
            locations = handle.read(4096)
        if len(locations) != 4096:
            raise AnvilError(f"truncated region header: {region_file}")
        for chunk_index in range(1024):
            location = locations[chunk_index * 4 : chunk_index * 4 + 4]
            if location[:3] == b"\0\0\0":
                continue
            if max_chunks is not None and chunks_read >= max_chunks:
                return
            try:
                root = read_nbt(_chunk_payload(region_file, chunk_index, location))
            except (OSError, zlib.error, NBTError) as exc:
                raise AnvilError(f"failed to read chunk {chunk_index} in {region_file.name}: {exc}") from exc
            chunk = root.get("Level", root)
            data_version = int(root.get("DataVersion", chunk.get("DataVersion", 0)))
            local_x, local_z = chunk_index % 32, chunk_index // 32
            chunk_x = int(chunk.get("xPos", region_x * 32 + local_x))
            chunk_z = int(chunk.get("zPos", region_z * 32 + local_z))
            sections = chunk.get("sections", chunk.get("Sections", []))
            if not isinstance(sections, list):
                raise AnvilError(f"chunk {chunk_x},{chunk_z} has an invalid sections list")
            chunks_read += 1
            for section in sections:
                if not isinstance(section, dict) or "Y" not in section:
                    continue
                if "block_states" in section or "Palette" in section:
                    palette, indices = _modern_section(section, data_version)
                elif "Blocks" in section:
                    palette, indices = _legacy_section(section)
                else:
                    continue
                yield SectionRecord(chunk_x, int(section["Y"]), chunk_z, data_version, palette, indices)
