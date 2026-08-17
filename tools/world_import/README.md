# Minecraft Java world importer

This desktop-side converter reads Minecraft Java Anvil region files and writes a Theocraft-compatible Luanti world database. It is dependency-free and supports both legacy numeric chunk sections and modern palette/block-state sections, including negative section heights introduced in Minecraft 1.18.

The Luanti mapblock serializer is adapted from the X11/MIT-licensed [minetest-tools/mcimport](https://github.com/minetest-tools/mcimport), pinned under `vendor/mcimport`. The reader and VoxeLibre mappings are new because upstream mcimport only understands the pre-1.13 numeric format and maps to Minetest Game mods.

Run from the repository root:

```powershell
.\scripts\Import-MinecraftWorld.ps1 -Source "C:\Minecraft\saves\My World" -Destination "C:\Converted\My World"
```

The destination must not already exist. Add `-Zip` to produce an archive for transfer to Android. The generated `import-report.json` gives exact unknown block-state counts. Unknown states are visibly preserved as `theocraft_import:unknown`; they are not silently converted to air.

Custom mappings use JSON, keyed by a Minecraft block name or a full state string:

```json
{
  "minecraft:modded_block": "mcl_core:stone",
  "minecraft:oak_log[axis=x]": {"node": "mcl_core:tree", "param2": 12}
}
```

Current boundary: overworld blocks and the original world spawn are imported. Nether/End dimensions, block-entity inventories, signs, entities, and player files remain in the source world and are listed as limitations in the report.
