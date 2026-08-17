minetest.register_node("theocraft_import:unknown", {
	description = "Unsupported Imported Block",
	_doc_items_longdesc = "This placeholder marks a Minecraft block state that was not mapped during world import. See import-report.json in the world folder.",
	tiles = {"mcl_core_stone.png^[colorize:#C000FF:170"},
	is_ground_content = false,
	groups = {handy = 1, pickaxey = 1, building_block = 1},
	_mcl_blast_resistance = 6,
	_mcl_hardness = 1.5,
})
