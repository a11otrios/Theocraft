"""Minecraft block-state to VoxeLibre node mapping."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

from .anvil import BlockState


UNKNOWN_NODE = "theocraft_import:unknown"


@dataclass(frozen=True)
class MappingResult:
    node: str
    param2: int = 0
    known: bool = True


DEFAULT_MAP: dict[str, str] = {
    "minecraft:air": "air",
    "minecraft:cave_air": "air",
    "minecraft:void_air": "air",
    "minecraft:stone": "mcl_core:stone",
    "minecraft:granite": "mcl_core:granite",
    "minecraft:polished_granite": "mcl_core:granite_smooth",
    "minecraft:diorite": "mcl_core:diorite",
    "minecraft:polished_diorite": "mcl_core:diorite_smooth",
    "minecraft:andesite": "mcl_core:andesite",
    "minecraft:polished_andesite": "mcl_core:andesite_smooth",
    "minecraft:deepslate": "mcl_deepslate:deepslate",
    "minecraft:cobbled_deepslate": "mcl_deepslate:deepslate_cobbled",
    "minecraft:polished_deepslate": "mcl_deepslate:deepslate_polished",
    "minecraft:deepslate_bricks": "mcl_deepslate:deepslate_bricks",
    "minecraft:cracked_deepslate_bricks": "mcl_deepslate:deepslate_bricks_cracked",
    "minecraft:deepslate_tiles": "mcl_deepslate:deepslate_tiles",
    "minecraft:cracked_deepslate_tiles": "mcl_deepslate:deepslate_tiles_cracked",
    "minecraft:chiseled_deepslate": "mcl_deepslate:deepslate_chiseled",
    "minecraft:tuff": "mcl_deepslate:tuff",
    "minecraft:calcite": "mcl_amethyst:calcite",
    "minecraft:grass_block": "mcl_core:dirt_with_grass",
    "minecraft:dirt": "mcl_core:dirt",
    "minecraft:coarse_dirt": "mcl_core:coarse_dirt",
    "minecraft:podzol": "mcl_core:podzol",
    "minecraft:mycelium": "mcl_core:mycelium",
    "minecraft:dirt_path": "mcl_core:grass_path",
    "minecraft:rooted_dirt": "mcl_core:dirt",
    "minecraft:mud": "mcl_mud:mud",
    "minecraft:cobblestone": "mcl_core:cobble",
    "minecraft:mossy_cobblestone": "mcl_core:mossycobble",
    "minecraft:bedrock": "mcl_core:bedrock",
    "minecraft:sand": "mcl_core:sand",
    "minecraft:red_sand": "mcl_core:redsand",
    "minecraft:gravel": "mcl_core:gravel",
    "minecraft:sandstone": "mcl_core:sandstone",
    "minecraft:smooth_sandstone": "mcl_core:sandstonesmooth",
    "minecraft:cut_sandstone": "mcl_core:sandstonesmooth2",
    "minecraft:chiseled_sandstone": "mcl_core:sandstonecarved",
    "minecraft:red_sandstone": "mcl_core:redsandstone",
    "minecraft:smooth_red_sandstone": "mcl_core:redsandstonesmooth",
    "minecraft:cut_red_sandstone": "mcl_core:redsandstonesmooth2",
    "minecraft:chiseled_red_sandstone": "mcl_core:redsandstonecarved",
    "minecraft:clay": "mcl_core:clay",
    "minecraft:bricks": "mcl_core:brick_block",
    "minecraft:stone_bricks": "mcl_core:stonebrick",
    "minecraft:mossy_stone_bricks": "mcl_core:stonebrickmossy",
    "minecraft:cracked_stone_bricks": "mcl_core:stonebrickcracked",
    "minecraft:chiseled_stone_bricks": "mcl_core:stonebrickcarved",
    "minecraft:smooth_stone": "mcl_core:stone_smooth",
    "minecraft:water": "mcl_core:water_source",
    "minecraft:lava": "mcl_core:lava_source",
    "minecraft:glass": "mcl_core:glass",
    "minecraft:ice": "mcl_core:ice",
    "minecraft:packed_ice": "mcl_core:packed_ice",
    "minecraft:snow_block": "mcl_core:snowblock",
    "minecraft:obsidian": "mcl_core:obsidian",
    "minecraft:crying_obsidian": "mcl_core:crying_obsidian",
    "minecraft:coal_ore": "mcl_core:stone_with_coal",
    "minecraft:iron_ore": "mcl_core:stone_with_iron",
    "minecraft:gold_ore": "mcl_core:stone_with_gold",
    "minecraft:redstone_ore": "mcl_core:stone_with_redstone",
    "minecraft:lapis_ore": "mcl_core:stone_with_lapis",
    "minecraft:diamond_ore": "mcl_core:stone_with_diamond",
    "minecraft:emerald_ore": "mcl_core:stone_with_emerald",
    "minecraft:copper_ore": "mcl_copper:stone_with_copper",
    "minecraft:deepslate_coal_ore": "mcl_deepslate:deepslate_with_coal",
    "minecraft:deepslate_iron_ore": "mcl_deepslate:deepslate_with_iron",
    "minecraft:deepslate_gold_ore": "mcl_deepslate:deepslate_with_gold",
    "minecraft:deepslate_redstone_ore": "mcl_deepslate:deepslate_with_redstone",
    "minecraft:deepslate_lapis_ore": "mcl_deepslate:deepslate_with_lapis",
    "minecraft:deepslate_diamond_ore": "mcl_deepslate:deepslate_with_diamond",
    "minecraft:deepslate_emerald_ore": "mcl_deepslate:deepslate_with_emerald",
    "minecraft:deepslate_copper_ore": "mcl_deepslate:deepslate_with_copper",
    "minecraft:coal_block": "mcl_core:coalblock",
    "minecraft:iron_block": "mcl_core:ironblock",
    "minecraft:gold_block": "mcl_core:goldblock",
    "minecraft:diamond_block": "mcl_core:diamondblock",
    "minecraft:lapis_block": "mcl_core:lapisblock",
    "minecraft:emerald_block": "mcl_core:emeraldblock",
    "minecraft:raw_copper_block": "mcl_copper:block_raw",
    "minecraft:copper_block": "mcl_copper:block",
    "minecraft:cut_copper": "mcl_copper:block_cut",
    "minecraft:crafting_table": "mcl_crafting_table:crafting_table",
    "minecraft:furnace": "mcl_furnaces:furnace",
    "minecraft:blast_furnace": "mcl_blast_furnace:blast_furnace",
    "minecraft:chest": "mcl_chests:chest",
    "minecraft:trapped_chest": "mcl_chests:trapped_chest",
    "minecraft:ender_chest": "mcl_chests:ender_chest",
    "minecraft:bookshelf": "mcl_books:bookshelf",
    "minecraft:ladder": "mcl_core:ladder",
    "minecraft:torch": "mcl_torches:torch",
    "minecraft:wall_torch": "mcl_torches:torch_wall",
    "minecraft:glowstone": "mcl_nether:glowstone",
    "minecraft:netherrack": "mcl_nether:netherrack",
    "minecraft:soul_sand": "mcl_nether:soul_sand",
    "minecraft:nether_bricks": "mcl_nether:nether_brick",
    "minecraft:end_stone": "mcl_end:end_stone",
    "minecraft:prismarine": "mcl_ocean:prismarine",
    "minecraft:prismarine_bricks": "mcl_ocean:prismarine_brick",
    "minecraft:dark_prismarine": "mcl_ocean:prismarine_dark",
    "minecraft:sea_lantern": "mcl_ocean:sea_lantern",
    "minecraft:hay_block": "mcl_farming:hay_block",
    "minecraft:melon": "mcl_farming:melon",
    "minecraft:quartz_block": "mcl_nether:quartz_block",
    "minecraft:chiseled_quartz_block": "mcl_nether:quartz_chiseled",
    "minecraft:quartz_pillar": "mcl_nether:quartz_pillar",
    "minecraft:redstone_block": "mesecons_torch:redstoneblock",
}


WOOD_NODES: dict[str, tuple[str, str, str]] = {
    "oak": ("mcl_core:tree", "mcl_core:wood", "mcl_core:leaves"),
    "spruce": ("mcl_core:sprucetree", "mcl_core:sprucewood", "mcl_core:spruceleaves"),
    "birch": ("mcl_core:birchtree", "mcl_core:birchwood", "mcl_core:birchleaves"),
    "jungle": ("mcl_core:jungletree", "mcl_core:junglewood", "mcl_core:jungleleaves"),
    "acacia": ("mcl_core:acaciatree", "mcl_core:acaciawood", "mcl_core:acacialeaves"),
    "dark_oak": ("mcl_core:darktree", "mcl_core:darkwood", "mcl_core:darkleaves"),
    "mangrove": ("mcl_mangrove:mangrove_tree", "mcl_mangrove:mangrove_wood", "mcl_mangrove:mangroveleaves"),
    "cherry": ("mcl_cherry_blossom:cherrytree", "mcl_cherry_blossom:cherrywood", "mcl_cherry_blossom:cherryleaves"),
}


STAIR_BASES = {
    "oak": "wood", "spruce": "sprucewood", "birch": "birchwood", "jungle": "junglewood",
    "acacia": "acaciawood", "dark_oak": "darkwood", "mangrove": "mangrove_wood", "cherry": "cherrywood",
    "cobblestone": "cobble", "mossy_cobblestone": "mossycobble", "stone": "stone_rough",
    "stone_brick": "stonebrick", "brick": "brick_block", "sandstone": "sandstone",
    "red_sandstone": "redsandstone", "quartz": "quartzblock", "prismarine": "prismarine",
    "prismarine_brick": "prismarine_brick", "dark_prismarine": "prismarine_dark",
}


COLOR_ALIASES = {"gray": "grey", "light_gray": "silver"}


def _axis_param2(properties: Mapping[str, str]) -> int:
    return {"x": 12, "z": 6}.get(properties.get("axis", "y"), 0)


def _stair_param2(properties: Mapping[str, str]) -> int:
    facing = properties.get("facing", "north")
    if properties.get("half") == "top":
        return {"north": 20, "south": 22, "east": 23, "west": 21}.get(facing, 20)
    return {"north": 0, "south": 2, "east": 1, "west": 3}.get(facing, 0)


class BlockMapper:
    def __init__(self, overrides: Mapping[str, object] | None = None):
        self.overrides = dict(overrides or {})

    @classmethod
    def from_json(cls, path: Path | None) -> "BlockMapper":
        if path is None:
            return cls()
        value = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            raise ValueError("custom block mapping must be a JSON object")
        return cls(value)

    def map(self, state: BlockState) -> MappingResult:
        override = self.overrides.get(state.report_key, self.overrides.get(state.name))
        if isinstance(override, str):
            return MappingResult(override)
        if isinstance(override, dict) and isinstance(override.get("node"), str):
            return MappingResult(override["node"], int(override.get("param2", 0)) & 0xFF)
        if state.name in DEFAULT_MAP:
            return MappingResult(DEFAULT_MAP[state.name])
        if not state.name.startswith("minecraft:"):
            return MappingResult(UNKNOWN_NODE, known=False)

        name = state.name.removeprefix("minecraft:")
        for wood, (log_node, plank_node, leaves_node) in WOOD_NODES.items():
            if name == f"{wood}_log":
                return MappingResult(log_node, _axis_param2(state.properties))
            if name == f"{wood}_wood":
                return MappingResult(log_node + "_bark", _axis_param2(state.properties))
            if name == f"{wood}_planks":
                return MappingResult(plank_node)
            if name == f"{wood}_leaves":
                return MappingResult(leaves_node)

        if name.startswith("stripped_") and (name.endswith("_log") or name.endswith("_wood")):
            wood = name.removeprefix("stripped_").removesuffix("_log").removesuffix("_wood")
            stripped = {
                "oak": "mcl_core:stripped_oak", "spruce": "mcl_core:stripped_spruce",
                "birch": "mcl_core:stripped_birch", "jungle": "mcl_core:stripped_jungle",
                "acacia": "mcl_core:stripped_acacia", "dark_oak": "mcl_core:stripped_dark_oak",
                "mangrove": "mcl_mangrove:mangrove_stripped", "cherry": "mcl_cherry_blossom:stripped_cherrytree",
            }.get(wood)
            if stripped:
                if name.endswith("_wood"):
                    stripped += "_bark"
                return MappingResult(stripped, _axis_param2(state.properties))

        for minecraft_suffix, node_prefix in (
            ("_concrete_powder", "mcl_colorblocks:concrete_powder_"),
            ("_concrete", "mcl_colorblocks:concrete_"),
            ("_glazed_terracotta", "mcl_colorblocks:glazed_terracotta_"),
            ("_terracotta", "mcl_colorblocks:hardened_clay_"),
            ("_stained_glass", "mcl_core:glass_"),
            ("_carpet", "mcl_wool:"),
            ("_wool", "mcl_wool:"),
        ):
            if name.endswith(minecraft_suffix):
                minecraft_color = name.removesuffix(minecraft_suffix)
                if minecraft_suffix == "_stained_glass" and minecraft_color == "gray":
                    color = "gray"
                else:
                    color = COLOR_ALIASES.get(minecraft_color, minecraft_color)
                suffix = "_carpet" if minecraft_suffix == "_carpet" else ""
                return MappingResult(node_prefix + color + suffix)

        if name.endswith("_stairs"):
            base = name.removesuffix("_stairs")
            stair = STAIR_BASES.get(base)
            if stair:
                return MappingResult("mcl_stairs:stair_" + stair, _stair_param2(state.properties))
        if name.endswith("_slab"):
            base = name.removesuffix("_slab")
            slab = STAIR_BASES.get(base)
            if slab:
                slab_type = state.properties.get("type", "bottom")
                suffix = "_top" if slab_type == "top" else ("_double" if slab_type == "double" else "")
                return MappingResult("mcl_stairs:slab_" + slab + suffix)
        return MappingResult(UNKNOWN_NODE, known=False)
