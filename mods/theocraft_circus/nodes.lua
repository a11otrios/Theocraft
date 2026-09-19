-- Circus building blocks. All soft, colourful, and non-scary.
local mod = theocraft_circus

local function sound_wood()
	if mcl_sounds and mcl_sounds.node_sound_wood_defaults then
		return mcl_sounds.node_sound_wood_defaults()
	end
end

local function sound_wool()
	if mcl_sounds and mcl_sounds.node_sound_wool_defaults then
		return mcl_sounds.node_sound_wool_defaults()
	end
end

local function sound_glass()
	if mcl_sounds and mcl_sounds.node_sound_glass_defaults then
		return mcl_sounds.node_sound_glass_defaults()
	end
end

local function canvas_def(description, tile, longdesc)
	return {
		description = description,
		_doc_items_longdesc = longdesc or "Soft colourful circus tent fabric for walls and big-top roofs.",
		tiles = {tile},
		is_ground_content = false,
		groups = {handy = 1, building_block = 1, circus = 1, circus_canvas = 1},
		sounds = sound_wool(),
		_mcl_blast_resistance = 1,
		_mcl_hardness = 0.8,
	}
end

-- 1. Big Top Canvas Blocks (fabric-soft wool blocks).
-- Registered: theocraft_circus:canvas_red, theocraft_circus:canvas_white,
-- theocraft_circus:canvas_blue, theocraft_circus:canvas_yellow,
-- theocraft_circus:canvas_purple, theocraft_circus:canvas_striped_red,
-- theocraft_circus:canvas_striped_blue.
local canvases = {
	{"red", "Big Top Canvas (Red)", "wool_red.png"},
	{"white", "Big Top Canvas (White)", "wool_white.png"},
	{"blue", "Big Top Canvas (Blue)", "wool_blue.png"},
	{"yellow", "Big Top Canvas (Yellow)", "wool_yellow.png"},
	{"purple", "Big Top Canvas (Purple)", "wool_violet.png"},
	{"striped_red", "Big Top Canvas (Red-White Stripes)", "wool_red.png^wool_white.png^[opacity:110"},
	{"striped_blue", "Big Top Canvas (Blue-White Stripes)", "wool_blue.png^wool_white.png^[opacity:110"},
}
for _, row in ipairs(canvases) do
	minetest.register_node("theocraft_circus:canvas_" .. row[1], canvas_def(row[2], row[3]))
end

-- 2. Circus Poles (stackable supports).
local function pole_def(description, tile)
	return {
		description = description,
		_doc_items_longdesc = "Tall decorative circus support pole. Stacks vertically for tent masts and entrances.",
		tiles = {tile},
		is_ground_content = false,
		paramtype2 = "facedir",
		groups = {handy = 1, axey = 1, building_block = 1, circus = 1, circus_pole = 1},
		sounds = sound_wood(),
		_mcl_blast_resistance = 1,
		_mcl_hardness = 1.2,
	}
end

minetest.register_node("theocraft_circus:pole_gold", pole_def(
	"Circus Pole (Gold)", "wool_yellow.png^[colorize:#B8860B:120"))
minetest.register_node("theocraft_circus:pole_red", pole_def(
	"Circus Pole (Red-White Stripes)", "wool_red.png^wool_white.png^[opacity:110"))
minetest.register_node("theocraft_circus:pole_blue", pole_def(
	"Circus Pole (Blue-White Stripes)", "wool_blue.png^wool_white.png^[opacity:110"))

-- 3. Circus Ring Floors.
local function ring_def(description, tile, longdesc)
	return {
		description = description,
		_doc_items_longdesc = longdesc or "Soft circus performance floor. Kind to land on and made for shows.",
		tiles = {tile},
		is_ground_content = false,
		groups = {handy = 1, building_block = 1, circus = 1, circus_floor = 1, fall_damage_add_percent = -40},
		sounds = sound_wool(),
		_mcl_blast_resistance = 1,
		_mcl_hardness = 0.9,
	}
end

minetest.register_node("theocraft_circus:ring_sawdust", ring_def(
	"Circus Ring Floor (Sawdust)",
	"wool_orange.png^[colorize:#D2A679:90",
	"Golden sawdust-style ring floor for the centre of the show."))
minetest.register_node("theocraft_circus:ring_red", ring_def(
	"Circus Ring Floor (Red Mat)", "wool_red.png"))
minetest.register_node("theocraft_circus:ring_blue", ring_def(
	"Circus Ring Floor (Blue Mat)", "wool_blue.png"))
minetest.register_node("theocraft_circus:ring_gold", ring_def(
	"Circus Centre Ring (Gold)",
	"wool_yellow.png^[colorize:#FFD23F:120",
	"Shiny golden centre ring that marks the star spot of the performance."))

-- 4. Audience Seats (place in rows).
local seat_boxes = {
	type = "fixed",
	fixed = {
		{-0.45, -0.50, -0.40, 0.45, -0.10, 0.40},
		{-0.45, -0.10, 0.25, 0.45, 0.45, 0.40},
	},
}
local function seat_def(description, tile, longdesc)
	return {
		description = description,
		_doc_items_longdesc = longdesc or "A friendly circus audience seat. Place in rows so friends can watch the show.",
		drawtype = "nodebox",
		paramtype = "light",
		paramtype2 = "facedir",
		sunlight_propagates = true,
		tiles = {tile},
		node_box = seat_boxes,
		selection_box = seat_boxes,
		collision_box = seat_boxes,
		groups = {handy = 1, axey = 1, deco_block = 1, circus = 1, circus_seat = 1},
		sounds = sound_wood(),
		_mcl_blast_resistance = 1,
		_mcl_hardness = 1.0,
	}
end

minetest.register_node("theocraft_circus:seat_wood", seat_def(
	"Audience Seat (Wood)", "wool_brown.png"))
minetest.register_node("theocraft_circus:seat_red", seat_def(
	"Audience Seat (Red Cushion)", "wool_red.png"))
minetest.register_node("theocraft_circus:seat_blue", seat_def(
	"Audience Seat (Blue Cushion)", "wool_blue.png"))
minetest.register_node("theocraft_circus:seat_vip", seat_def(
	"Audience Seat (Gold VIP)",
	"wool_yellow.png^[colorize:#FFD23F:120",
	"A golden VIP seat for the guest of honour."))

-- 5. Spotlight (toggleable, directional).
local function spotlight_tile(on)
	if on then
		return "wool_yellow.png^[colorize:#FFF6C9:160"
	end
	return "wool_grey.png"
end

minetest.register_node("theocraft_circus:spotlight_off", {
	description = "Circus Spotlight (Off)",
	_doc_items_longdesc = "A friendly stage spotlight. Right-click to switch on and point the show light with facedir.",
	tiles = {spotlight_tile(false)},
	is_ground_content = false,
	paramtype = "light",
	paramtype2 = "facedir",
	light_source = 0,
	groups = {handy = 1, pickaxey = 1, deco_block = 1, circus = 1, circus_light = 1},
	sounds = sound_glass(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1.0,
	on_rightclick = function(pos, node, clicker)
		minetest.swap_node(pos, {name = "theocraft_circus:spotlight_on", param2 = node.param2})
		if clicker and clicker:is_player() then
			mod.sparkle({x = pos.x, y = pos.y + 0.6, z = pos.z}, "spot")
			mod.safe_sound("mcl_note_block_pling", {pos = pos, gain = 0.4})
		end
		return clicker and clicker:get_wielded_item() or nil
	end,
})

minetest.register_node("theocraft_circus:spotlight_on", {
	description = "Circus Spotlight (On)",
	_doc_items_longdesc = "A glowing circus spotlight. Right-click to switch it off.",
	tiles = {spotlight_tile(true)},
	is_ground_content = false,
	paramtype = "light",
	paramtype2 = "facedir",
	light_source = 14,
	groups = {handy = 1, pickaxey = 1, deco_block = 1, circus = 1, circus_light = 1, not_in_creative_inventory = 1},
	sounds = sound_glass(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1.0,
	drop = "theocraft_circus:spotlight_off",
	on_rightclick = function(pos, node, clicker)
		minetest.swap_node(pos, {name = "theocraft_circus:spotlight_off", param2 = node.param2})
		return clicker and clicker:get_wielded_item() or nil
	end,
})

-- 6. Fairy Light (warm glow, hangs like a string).
minetest.register_node("theocraft_circus:fairy_light", {
	description = "Circus Fairy Light",
	_doc_items_longdesc = "A warm string of circus fairy lights. Place in rows between poles for a cosy glow.",
	drawtype = "nodebox",
	paramtype = "light",
	sunlight_propagates = true,
	light_source = 11,
	tiles = {"wool_yellow.png^[colorize:#FFF3B0:170"},
	node_box = {type = "fixed", fixed = {{-0.50, 0.25, -0.06, 0.50, 0.45, 0.06}}},
	selection_box = {type = "fixed", fixed = {-0.5, 0.2, -0.1, 0.5, 0.5, 0.1}},
	collision_box = {type = "fixed", fixed = {-0.5, 0.2, -0.1, 0.5, 0.5, 0.1}},
	groups = {handy = 1, deco_block = 1, circus = 1, circus_light = 1, dig_by_water = 1},
	sounds = sound_glass(),
	_mcl_blast_resistance = 0,
	_mcl_hardness = 0.2,
})

-- 7. Curtains (open/close by right-click).
-- Registered: theocraft_circus:curtain_red_closed, theocraft_circus:curtain_red_open,
-- theocraft_circus:curtain_blue_closed, theocraft_circus:curtain_blue_open,
-- theocraft_circus:curtain_purple_closed, theocraft_circus:curtain_purple_open,
-- theocraft_circus:curtain_gold_closed, theocraft_circus:curtain_gold_open.
local curtain_colors = {
	{"red", "Circus Curtain (Red)", "wool_red.png"},
	{"blue", "Circus Curtain (Blue)", "wool_blue.png"},
	{"purple", "Circus Curtain (Purple)", "wool_violet.png"},
	{"gold", "Circus Curtain (Gold)", "wool_yellow.png^[colorize:#FFD23F:120"},
}
for _, row in ipairs(curtain_colors) do
	local color, label, tile = row[1], row[2], row[3]
	minetest.register_node("theocraft_circus:curtain_" .. color .. "_closed", {
		description = label .. " (Closed)",
		_doc_items_longdesc = "A grand circus curtain. Right-click to open it and start the show.",
		tiles = {tile},
		is_ground_content = false,
		paramtype2 = "facedir",
		groups = {handy = 1, deco_block = 1, circus = 1, circus_curtain = 1},
		sounds = sound_wool(),
		_mcl_blast_resistance = 1,
		_mcl_hardness = 0.8,
		on_rightclick = function(pos, node, clicker)
			minetest.swap_node(pos, {name = "theocraft_circus:curtain_" .. color .. "_open", param2 = node.param2})
			mod.safe_sound("mcl_note_block_pling", {pos = pos, gain = 0.4})
			return clicker and clicker:get_wielded_item() or nil
		end,
	})
	minetest.register_node("theocraft_circus:curtain_" .. color .. "_open", {
		description = label .. " (Open)",
		_doc_items_longdesc = "An open circus curtain. Right-click to close it again.",
		tiles = {tile .. "^[opacity:160"},
		drawtype = "nodebox",
		paramtype = "light",
		paramtype2 = "facedir",
		sunlight_propagates = true,
		node_box = {type = "fixed", fixed = {{-0.50, -0.50, 0.30, 0.50, 0.50, 0.50}}},
		selection_box = {type = "fixed", fixed = {-0.5, -0.5, 0.3, 0.5, 0.5, 0.5}},
		groups = {handy = 1, deco_block = 1, circus = 1, circus_curtain = 1, not_in_creative_inventory = 1},
		sounds = sound_wool(),
		drop = "theocraft_circus:curtain_" .. color .. "_closed",
		_mcl_blast_resistance = 1,
		_mcl_hardness = 0.8,
		on_rightclick = function(pos, node, clicker)
			minetest.swap_node(pos, {name = "theocraft_circus:curtain_" .. color .. "_closed", param2 = node.param2})
			return clicker and clicker:get_wielded_item() or nil
		end,
	})
end

-- 8. Stage Block (raised platform).
minetest.register_node("theocraft_circus:stage", {
	description = "Circus Stage Block",
	_doc_items_longdesc = "A raised wooden stage platform for announcements and performances.",
	tiles = {"wool_brown.png^wool_red.png^[opacity:60"},
	is_ground_content = false,
	groups = {handy = 1, axey = 1, building_block = 1, circus = 1, circus_stage = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1.2,
})

-- 9. Circus Banners (hanging decoration, facedir).
local banners = {
	{"red", "Circus Banner (Red)", "wool_red.png^[colorize:#FFD23F:60"},
	{"blue", "Circus Banner (Blue)", "wool_blue.png^[colorize:#FFFFFF:60"},
	{"gold", "Circus Banner (Gold)", "wool_yellow.png^[colorize:#FFD23F:120"},
	{"rainbow", "Circus Banner (Rainbow)", "wool_magenta.png^wool_cyan.png^[opacity:120"},
}
for _, row in ipairs(banners) do
	minetest.register_node("theocraft_circus:banner_" .. row[1], {
		description = row[2],
		_doc_items_longdesc = "A colourful hanging circus banner. Mix colours and patterns for a festive tent.",
		drawtype = "nodebox",
		paramtype = "light",
		paramtype2 = "facedir",
		sunlight_propagates = true,
		tiles = {row[3]},
		node_box = {type = "fixed", fixed = {{-0.30, -0.50, -0.05, 0.30, 0.50, 0.05}}},
		selection_box = {type = "fixed", fixed = {-0.3, -0.5, -0.05, 0.3, 0.5, 0.05}},
		groups = {handy = 1, deco_block = 1, circus = 1, dig_by_water = 1},
		sounds = sound_wool(),
		_mcl_blast_resistance = 1,
		_mcl_hardness = 0.5,
	})
end

-- 10. Ticket Booth (entrance kiosk).
minetest.register_node("theocraft_circus:ticket_booth", {
	description = "Circus Ticket Booth",
	_doc_items_longdesc = "A cheerful ticket kiosk. Place it as the entrance to the circus and hand out tickets.",
	tiles = {
		"wool_red.png^wool_white.png^[opacity:110",
		"wool_red.png^wool_white.png^[opacity:110",
		"wool_red.png",
		"wool_red.png",
		"wool_yellow.png^[colorize:#FFD23F:120",
		"wool_yellow.png^[colorize:#FFD23F:120",
	},
	is_ground_content = false,
	paramtype2 = "facedir",
	groups = {handy = 1, axey = 1, deco_block = 1, circus = 1, circus_booth = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1.2,
	on_rightclick = function(pos, node, clicker, itemstack)
		if clicker and clicker:is_player() then
			minetest.chat_send_player(clicker:get_player_name(),
				"[Circus] Welcome to Theo's Circus! Please take a ticket and enjoy the show!")
			mod.sparkle({x = pos.x, y = pos.y + 1, z = pos.z}, "booth")
		end
		return itemstack
	end,
})

-- 11. Popcorn Stand (gives popcorn on right-click, limited rate).
minetest.register_node("theocraft_circus:popcorn_stand", {
	description = "Circus Popcorn Stand",
	_doc_items_longdesc = "A yummy popcorn stand. Right-click for a small popcorn treat.",
	tiles = {
		"wool_white.png", "wool_white.png",
		"wool_red.png^wool_white.png^[opacity:110",
		"wool_red.png^wool_white.png^[opacity:110",
		"wool_yellow.png", "wool_yellow.png",
	},
	is_ground_content = false,
	paramtype2 = "facedir",
	groups = {handy = 1, axey = 1, deco_block = 1, circus = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1.2,
	on_rightclick = function(pos, node, clicker, itemstack)
		if not clicker or not clicker:is_player() then return itemstack end
		local name = clicker:get_player_name()
		local key = "popcorn:" .. name .. ":" .. minetest.pos_to_string(pos)
		local last = tonumber(mod.storage:get_string(key)) or 0
		if os.time() - last < 20 then
			minetest.chat_send_player(name, "[Circus] Fresh popcorn is popping! One moment please...")
			return itemstack
		end
		local inv = clicker:get_inventory()
		if inv and inv:room_for_item("main", "theocraft_circus:popcorn 1") then
			inv:add_item("main", "theocraft_circus:popcorn 1")
			mod.storage:set_string(key, tostring(os.time()))
			minetest.chat_send_player(name, "[Circus] Hot popcorn for the show! Enjoy!")
			mod.safe_sound("mcl_note_block_pling", {pos = pos, gain = 0.4})
		else
			minetest.chat_send_player(name, "[Circus] Your hands are full for popcorn!")
		end
		return itemstack
	end,
})

-- 12. Prize Stand (plush toys, ribbons, trophies; daily medal treat).
minetest.register_node("theocraft_circus:prize_stand", {
	description = "Circus Prize Stand",
	_doc_items_longdesc = "A prize stall with plush toys, ribbons, and trophies. Winners collect a performer medal here.",
	tiles = {"wool_pink.png", "wool_pink.png", "wool_yellow.png^[colorize:#FFD23F:120",
		"wool_yellow.png^[colorize:#FFD23F:120", "wool_pink.png", "wool_pink.png"},
	is_ground_content = false,
	paramtype2 = "facedir",
	groups = {handy = 1, axey = 1, deco_block = 1, circus = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1.2,
	on_rightclick = function(pos, node, clicker, itemstack)
		if clicker and clicker:is_player() then
			minetest.chat_send_player(clicker:get_player_name(),
				"[Circus] Plush toys, rainbow ribbons, and shiny trophies! Finish a circus challenge to earn a medal!")
			mod.sparkle({x = pos.x, y = pos.y + 1, z = pos.z}, "prize")
		end
		return itemstack
	end,
})

-- 13. Practice Mats (soft landing: engine cushion group + Theo-mode guard).
-- Registered: theocraft_circus:practice_mat_red, theocraft_circus:practice_mat_blue.
local function practice_mat(color, label, tile)
	minetest.register_node("theocraft_circus:practice_mat_" .. color, {
		description = label,
		_doc_items_longdesc = "A super-soft circus landing mat. Falls onto it are cushioned, and Theo's Circus Mode makes circus falls safe.",
		tiles = {tile},
		is_ground_content = false,
		groups = {
			handy = 1, building_block = 1, circus = 1, circus_mat = 1,
			fall_damage_add_percent = -100,
		},
		sounds = sound_wool(),
		_mcl_blast_resistance = 1,
		_mcl_hardness = 0.6,
	})
end

practice_mat("red", "Circus Practice Mat (Red)", "wool_red.png^[colorize:#FFFFFF:40")
practice_mat("blue", "Circus Practice Mat (Blue)", "wool_blue.png^[colorize:#FFFFFF:40")

-- 14. Balance Beam (narrow raised beam).
minetest.register_node("theocraft_circus:balance_beam", {
	description = "Circus Balance Beam",
	_doc_items_longdesc = "A narrow raised beam for practising balance. Place mats beside it for safe practice.",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	tiles = {"wool_brown.png^[colorize:#FFD23F:40"},
	node_box = {type = "fixed", fixed = {{-0.50, -0.10, -0.12, 0.50, 0.10, 0.12}}},
	selection_box = {type = "fixed", fixed = {-0.5, -0.1, -0.12, 0.5, 0.1, 0.12}},
	collision_box = {type = "fixed", fixed = {-0.5, -0.1, -0.12, 0.5, 0.5, 0.12}},
	groups = {handy = 1, axey = 1, deco_block = 1, circus = 1, circus_beam = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1.0,
})

-- 15. Circus Crate (decorative storage with real inventory).
minetest.register_node("theocraft_circus:crate", {
	description = "Circus Crate",
	_doc_items_longdesc = "A sturdy decorated crate for storing juggling balls, ribbons, tickets, and costumes.",
	tiles = {"wool_brown.png^wool_yellow.png^[opacity:70"},
	is_ground_content = false,
	paramtype2 = "facedir",
	groups = {handy = 1, axey = 1, deco_block = 1, circus = 1, tubedevice = 1, tubedevice_receiver = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1.2,
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec",
			"size[8,9]label[0,0;Circus Crate]list[current_name;main;0,0.5;8,3;]" ..
			"list[current_player;main;0,4.5;8,4;]listring[current_name;main]" ..
			"listring[current_player;main]")
		meta:set_string("infotext", "Circus Crate")
		local inv = meta:get_inventory()
		inv:set_size("main", 24)
	end,
	can_dig = function(pos, player)
		local inv = minetest.get_meta(pos):get_inventory()
		return inv:is_empty("main")
	end,
})
