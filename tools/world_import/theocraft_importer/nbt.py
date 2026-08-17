"""Small, dependency-free NBT reader.

The implementation is adapted from minetest-tools/mcimport's MIT/X11-licensed
``nbt.py`` and adds bounds checking plus a conventional root return value.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Any


class NBTError(ValueError):
    pass


@dataclass
class _Reader:
    data: memoryview
    offset: int = 0

    def take(self, count: int) -> memoryview:
        if count < 0 or self.offset + count > len(self.data):
            raise NBTError("truncated NBT payload")
        result = self.data[self.offset : self.offset + count]
        self.offset += count
        return result

    def unpack(self, fmt: str) -> Any:
        size = struct.calcsize(fmt)
        return struct.unpack(fmt, self.take(size))[0]

    def string(self) -> str:
        length = self.unpack(">H")
        try:
            return bytes(self.take(length)).decode("utf-8")
        except UnicodeDecodeError as exc:
            raise NBTError("invalid UTF-8 in NBT string") from exc


def _array(reader: _Reader, fmt: str, item_size: int) -> list[int]:
    length = reader.unpack(">i")
    if length < 0 or length > 64_000_000:
        raise NBTError(f"invalid NBT array length {length}")
    if length == 0:
        return []
    return list(struct.unpack(f">{length}{fmt}", reader.take(length * item_size)))


def _payload(reader: _Reader, tag: int) -> Any:
    if tag == 1:
        return reader.unpack(">b")
    if tag == 2:
        return reader.unpack(">h")
    if tag == 3:
        return reader.unpack(">i")
    if tag == 4:
        return reader.unpack(">q")
    if tag == 5:
        return reader.unpack(">f")
    if tag == 6:
        return reader.unpack(">d")
    if tag == 7:
        return bytes(_array(reader, "B", 1))
    if tag == 8:
        return reader.string()
    if tag == 9:
        child_tag = reader.unpack(">B")
        length = reader.unpack(">i")
        if length < 0 or length > 16_000_000:
            raise NBTError(f"invalid NBT list length {length}")
        return [_payload(reader, child_tag) for _ in range(length)]
    if tag == 10:
        result: dict[str, Any] = {}
        while True:
            child_tag = reader.unpack(">B")
            if child_tag == 0:
                return result
            name = reader.string()
            result[name] = _payload(reader, child_tag)
    if tag == 11:
        return _array(reader, "i", 4)
    if tag == 12:
        return _array(reader, "q", 8)
    raise NBTError(f"unsupported NBT tag {tag}")


def read_nbt(data: bytes) -> dict[str, Any]:
    reader = _Reader(memoryview(data))
    root_tag = reader.unpack(">B")
    if root_tag != 10:
        raise NBTError(f"NBT root must be a compound, got tag {root_tag}")
    reader.string()  # Root name is not semantically relevant to world import.
    value = _payload(reader, root_tag)
    if not isinstance(value, dict):
        raise NBTError("NBT root was not a compound")
    return value
