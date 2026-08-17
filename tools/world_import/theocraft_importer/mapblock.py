"""Luanti mapblock v25 serializer, adapted from minetest-tools/mcimport."""

from __future__ import annotations

import sqlite3
import struct
import zlib
from io import BytesIO
from pathlib import Path
from typing import Sequence


def _u8(stream: BytesIO, value: int) -> None:
    stream.write(struct.pack(">B", value & 0xFF))


def _u16(stream: BytesIO, value: int) -> None:
    stream.write(struct.pack(">H", value & 0xFFFF))


def _u32(stream: BytesIO, value: int) -> None:
    stream.write(struct.pack(">I", value & 0xFFFFFFFF))


def _string16(stream: BytesIO, value: str) -> None:
    encoded = value.encode("utf-8")
    if len(encoded) > 0xFFFF:
        raise ValueError("mapblock string is too long")
    _u16(stream, len(encoded))
    stream.write(encoded)


def serialize_mapblock(nodes: Sequence[str], param2: Sequence[int], underground: bool = False) -> bytes:
    if len(nodes) != 4096 or len(param2) != 4096:
        raise ValueError("a mapblock must contain exactly 4096 nodes")
    output = BytesIO()
    _u8(output, 25)
    flags = (0x01 if underground else 0) | 0x02  # generated=true means bit 0x08 is clear
    _u8(output, flags)
    _u8(output, 2)  # content width
    _u8(output, 2)  # params width

    local_ids: dict[str, int] = {}
    local_names: list[str] = []
    content_ids: list[int] = []
    for node in nodes:
        if node not in local_ids:
            local_ids[node] = len(local_names)
            local_names.append(node)
        content_ids.append(local_ids[node])

    bulk = BytesIO()
    ordered_indices: list[int] = []
    for z in range(16):
        for y in range(16):
            for x in range(16):
                ordered_indices.append(y * 256 + z * 16 + x)
    for index in ordered_indices:
        _u16(bulk, content_ids[index])
    bulk.write(bytes(4096))  # param1; lighting is marked expired and recalculated by Luanti.
    bulk.write(bytes(param2[index] & 0xFF for index in ordered_indices))
    output.write(zlib.compress(bulk.getvalue(), level=6))

    output.write(zlib.compress(b"\0"))  # Empty NodeMetadataList, version 0.
    output.write(b"\0\0\0")  # Empty StaticObjectList: version 0, count 0.
    _u32(output, 0xFFFFFFFF)  # BLOCK_TIMESTAMP_UNDEFINED

    _u8(output, 0)  # NameIdMapping version
    _u16(output, len(local_names))
    for local_id, node in enumerate(local_names):
        _u16(output, local_id)
        _string16(output, node)
    _u8(output, 10)  # Empty NodeTimerList record size
    _u16(output, 0)
    return output.getvalue()


class MapDatabase:
    def __init__(self, path: Path):
        self.connection = sqlite3.connect(path)
        self.connection.execute(
            "CREATE TABLE blocks (x INTEGER, y INTEGER, z INTEGER, data BLOB NOT NULL, PRIMARY KEY (x, z, y))"
        )

    def write(self, x: int, y: int, z: int, data: bytes) -> None:
        self.connection.execute("INSERT INTO blocks (x, y, z, data) VALUES (?, ?, ?, ?)", (x, y, z, data))

    def commit(self) -> None:
        self.connection.commit()

    def close(self) -> None:
        self.connection.commit()
        self.connection.close()

    def __enter__(self) -> "MapDatabase":
        return self

    def __exit__(self, exc_type, exc, traceback) -> None:
        if exc_type is None:
            self.close()
        else:
            self.connection.close()
