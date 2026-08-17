"""High-level Minecraft Java world import pipeline."""

from __future__ import annotations

import gzip
import json
import shutil
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

from .anvil import AnvilError, iter_world_sections
from .mapblock import MapDatabase, serialize_mapblock
from .mapping import BlockMapper
from .nbt import NBTError, read_nbt


@dataclass(frozen=True)
class ImportResult:
    destination: Path
    chunks: int
    sections: int
    mapblocks: int
    mapped_blocks: int
    unknown_blocks: int


def _level_metadata(source: Path) -> dict[str, object]:
    level_path = source / "level.dat"
    if not level_path.is_file():
        return {}
    try:
        root = read_nbt(gzip.decompress(level_path.read_bytes()))
    except (OSError, NBTError) as exc:
        raise AnvilError(f"could not read level.dat: {exc}") from exc
    data = root.get("Data", root)
    return data if isinstance(data, dict) else {}


def _write_world_files(directory: Path, level: dict[str, object]) -> None:
    spawn = None
    if all(key in level for key in ("SpawnX", "SpawnY", "SpawnZ")):
        spawn = (int(level["SpawnX"]), int(level["SpawnY"]), int(level["SpawnZ"]))
    world_lines = [
        "gameid = theocraft",
        "backend = sqlite3",
        "player_backend = sqlite3",
        "auth_backend = sqlite3",
        "mod_storage_backend = sqlite3",
    ]
    if spawn:
        world_lines.append(f"static_spawnpoint = ({spawn[0]},{spawn[1]},{spawn[2]})")
    (directory / "world.mt").write_text("\n".join(world_lines) + "\n", encoding="utf-8")
    (directory / "map_meta.txt").write_text(
        "mg_name = singlenode\nseed = 0\n[end_of_params]\n", encoding="utf-8"
    )


def import_world(
    source: Path,
    destination: Path,
    mapping_path: Path | None = None,
    max_chunks: int | None = None,
) -> ImportResult:
    source = source.resolve()
    destination = destination.resolve()
    if not source.is_dir():
        raise ValueError(f"Minecraft world directory does not exist: {source}")
    if destination.exists():
        raise ValueError(f"destination already exists; refusing to overwrite it: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    mapper = BlockMapper.from_json(mapping_path)
    level = _level_metadata(source)
    temporary = Path(tempfile.mkdtemp(prefix=destination.name + "-import-", dir=destination.parent))

    sections = 0
    mapblocks = 0
    mapped_blocks = 0
    unknown_blocks = 0
    chunk_positions: set[tuple[int, int]] = set()
    data_versions: set[int] = set()
    unknown_states: Counter[str] = Counter()
    try:
        _write_world_files(temporary, level)
        with MapDatabase(temporary / "map.sqlite") as database:
            for record in iter_world_sections(source, max_chunks=max_chunks):
                sections += 1
                chunk_positions.add((record.chunk_x, record.chunk_z))
                data_versions.add(record.data_version)
                mapped_palette = [mapper.map(state) for state in record.palette]
                counts = Counter(record.indices)
                for palette_index, count in counts.items():
                    mapping = mapped_palette[palette_index]
                    if mapping.known:
                        mapped_blocks += count
                    else:
                        unknown_blocks += count
                        unknown_states[record.palette[palette_index].report_key] += count
                nodes = [mapped_palette[index].node for index in record.indices]
                if all(node == "air" for node in nodes):
                    continue
                param2 = [mapped_palette[index].param2 for index in record.indices]
                database.write(
                    record.chunk_x,
                    record.section_y,
                    record.chunk_z,
                    serialize_mapblock(nodes, param2, underground=record.section_y < 0),
                )
                mapblocks += 1
                if mapblocks % 100 == 0:
                    database.commit()

        report = {
            "format_version": 1,
            "source": str(source),
            "minecraft_level_name": level.get("LevelName"),
            "minecraft_data_versions": sorted(data_versions),
            "coordinate_transform": "identity (Minecraft x/y/z -> Theocraft x/y/z)",
            "chunks": len(chunk_positions),
            "sections": sections,
            "mapblocks_written": mapblocks,
            "mapped_blocks": mapped_blocks,
            "unknown_blocks": unknown_blocks,
            "unknown_states": dict(unknown_states.most_common()),
            "limitations": [
                "Only the Java overworld region directory is imported in this milestone.",
                "Block entities, inventories, signs, mobs, and player files are not imported yet.",
                "Unmapped states become theocraft_import:unknown and remain listed above.",
            ],
        }
        (temporary / "import-report.json").write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        temporary.rename(destination)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise
    return ImportResult(destination, len(chunk_positions), sections, mapblocks, mapped_blocks, unknown_blocks)
