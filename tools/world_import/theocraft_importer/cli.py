from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from .importer import import_world


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Convert a Minecraft Java world into a Theocraft/Luanti world folder."
    )
    result.add_argument("source", type=Path, help="Minecraft Java world directory containing region/")
    result.add_argument("destination", type=Path, help="new output world directory")
    result.add_argument("--mapping", type=Path, help="optional JSON mapping overrides")
    result.add_argument("--max-chunks", type=int, help="convert only the first N chunks for testing")
    result.add_argument("--zip", action="store_true", help="also create a ZIP suitable for transfer to Android")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    converted = import_world(args.source, args.destination, args.mapping, args.max_chunks)
    print(
        f"Imported {converted.chunks} chunks / {converted.mapblocks} mapblocks to {converted.destination} "
        f"({converted.unknown_blocks} unsupported blocks)."
    )
    print(f"Review {converted.destination / 'import-report.json'} before copying the world to Android.")
    if args.zip:
        archive = shutil.make_archive(str(converted.destination), "zip", converted.destination.parent, converted.destination.name)
        print(f"Created {archive}")
    return 0
