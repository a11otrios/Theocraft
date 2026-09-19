-- Simple, child-friendly crafting: wool + dye, wood + string, glass + glow.
-- Recipes use common VoxeLibre items; unknown items simply stay uncraftable
-- without ever breaking the game.

-- Canvas Block = wool + dye.
minetest.register_craft({output = "theocraft_circus:canvas_red 4", recipe = {{"mcl_wool:white", "mcl_dye:red", "mcl_wool:white"}}})
minetest.register_craft({output = "theocraft_circus:canvas_blue 4", recipe = {{"mcl_wool:white", "mcl_dye:blue", "mcl_wool:white"}}})
minetest.register_craft({output = "theocraft_circus:canvas_yellow 4", recipe = {{"mcl_wool:white", "mcl_dye:yellow", "mcl_wool:white"}}})
minetest.register_craft({output = "theocraft_circus:canvas_purple 4", recipe = {{"mcl_wool:white", "mcl_dye:violet", "mcl_wool:white"}}})
minetest.register_craft({output = "theocraft_circus:canvas_white 4", recipe = {{"mcl_wool:white", "mcl_wool:white", "mcl_wool:white"}}})
minetest.register_craft({
	output = "theocraft_circus:canvas_striped_red 4",
	recipe = {{"mcl_wool:red", "mcl_wool:white", "mcl_wool:red"}},
})
minetest.register_craft({
	output = "theocraft_circus:canvas_striped_blue 4",
	recipe = {{"mcl_wool:blue", "mcl_wool:white", "mcl_wool:blue"}},
})

-- Circus Pole = stick + wool stripes (stackable supports).
minetest.register_craft({
	output = "theocraft_circus:pole_red 2",
	recipe = {{"mcl_wool:red"}, {"mcl_core:stick"}, {"mcl_wool:white"}},
})
minetest.register_craft({
	output = "theocraft_circus:pole_blue 2",
	recipe = {{"mcl_wool:blue"}, {"mcl_core:stick"}, {"mcl_wool:white"}},
})
minetest.register_craft({
	output = "theocraft_circus:pole_gold 2",
	recipe = {{"mcl_dye:yellow"}, {"mcl_core:stick"}, {"mcl_core:gold_ingot"}},
})

-- Ring floors and mats from wool + sawdust tones.
minetest.register_craft({output = "theocraft_circus:ring_sawdust 4", recipe = {{"mcl_wool:orange", "mcl_wool:yellow", "mcl_wool:orange"}}})
minetest.register_craft({output = "theocraft_circus:ring_red 4", recipe = {{"mcl_wool:red", "mcl_wool:red", "mcl_wool:white"}}})
minetest.register_craft({output = "theocraft_circus:ring_blue 4", recipe = {{"mcl_wool:blue", "mcl_wool:blue", "mcl_wool:white"}}})
minetest.register_craft({
	output = "theocraft_circus:ring_gold 1",
	recipe = {{"mcl_wool:yellow", "mcl_core:gold_ingot", "mcl_wool:yellow"}},
})
minetest.register_craft({output = "theocraft_circus:practice_mat_red 2", recipe = {{"mcl_wool:red", "mcl_wool:white"}}})
minetest.register_craft({output = "theocraft_circus:practice_mat_blue 2", recipe = {{"mcl_wool:blue", "mcl_wool:white"}}})

-- Seats, stage, beam, crate.
minetest.register_craft({
	output = "theocraft_circus:seat_wood 2",
	recipe = {{"group:wood", "group:wood", "group:wood"}},
})
minetest.register_craft({output = "theocraft_circus:seat_red 2", recipe = {{"theocraft_circus:seat_wood", "mcl_wool:red"}}})
minetest.register_craft({output = "theocraft_circus:seat_blue 2", recipe = {{"theocraft_circus:seat_wood", "mcl_wool:blue"}}})
minetest.register_craft({output = "theocraft_circus:seat_vip 1", recipe = {{"theocraft_circus:seat_wood", "mcl_core:gold_ingot"}}})
minetest.register_craft({
	output = "theocraft_circus:stage 2",
	recipe = {{"group:wood", "mcl_wool:red", "group:wood"}},
})
minetest.register_craft({
	output = "theocraft_circus:balance_beam 2",
	recipe = {{"group:wood", "group:wood", "group:wood"}},
})
minetest.register_craft({
	output = "theocraft_circus:crate 1",
	recipe = {{"group:wood", "mcl_wool:red", "group:wood"}, {"group:wood", "", "group:wood"}},
})

-- Tightrope = string + anchor sticks.
minetest.register_craft({
	output = "theocraft_circus:tightrope 6",
	type = "shapeless",
	recipe = {"mcl_mobitems:string", "mcl_mobitems:string", "mcl_core:stick"},
})
minetest.register_craft({
	output = "theocraft_circus:tightrope_anchor 2",
	recipe = {{"mcl_core:stick", "mcl_wool:red", "mcl_core:stick"}},
})

-- Trapeze Bar = stick + string.
minetest.register_craft({
	output = "theocraft_circus:trapeze 1",
	type = "shapeless",
	recipe = {"mcl_core:stick", "mcl_mobitems:string", "mcl_mobitems:string"},
})
minetest.register_craft({
	output = "theocraft_circus:swing_rope 2",
	type = "shapeless",
	recipe = {"mcl_mobitems:string", "mcl_mobitems:string", "mcl_wool:brown"},
})
minetest.register_craft({
	output = "theocraft_circus:rola_bola 1",
	recipe = {{"group:wood"}, {"mcl_wool:red"}},
})

-- Trampoline = wool bounce-top + sticks.
minetest.register_craft({
	output = "theocraft_circus:trampoline 1",
	recipe = {
		{"mcl_core:stick", "mcl_wool:blue", "mcl_core:stick"},
		{"mcl_core:stick", "mcl_wool:red", "mcl_core:stick"},
	},
})

-- Spotlight = glass + glow wool + gold.
minetest.register_craft({
	output = "theocraft_circus:spotlight_off 1",
	recipe = {
		{"mcl_core:glass", "mcl_wool:yellow", "mcl_core:glass"},
		{"", "mcl_core:gold_ingot", ""},
	},
})
minetest.register_craft({
	output = "theocraft_circus:fairy_light 4",
	type = "shapeless",
	recipe = {"mcl_mobitems:string", "mcl_wool:yellow", "mcl_core:glass"},
})

-- Curtains, banners, booths, stands.
minetest.register_craft({output = "theocraft_circus:curtain_red_closed 2", recipe = {{"mcl_wool:red", "mcl_wool:red", "mcl_core:stick"}}})
minetest.register_craft({output = "theocraft_circus:curtain_blue_closed 2", recipe = {{"mcl_wool:blue", "mcl_wool:blue", "mcl_core:stick"}}})
minetest.register_craft({output = "theocraft_circus:curtain_purple_closed 2", recipe = {{"mcl_wool:purple", "mcl_wool:purple", "mcl_core:stick"}}})
minetest.register_craft({output = "theocraft_circus:curtain_gold_closed 2", recipe = {{"mcl_wool:yellow", "mcl_wool:yellow", "mcl_core:stick"}}})
minetest.register_craft({output = "theocraft_circus:banner_red 2", type = "shapeless", recipe = {"mcl_wool:red", "mcl_core:stick"}})
minetest.register_craft({output = "theocraft_circus:banner_blue 2", type = "shapeless", recipe = {"mcl_wool:blue", "mcl_core:stick"}})
minetest.register_craft({output = "theocraft_circus:banner_gold 2", type = "shapeless", recipe = {"mcl_wool:yellow", "mcl_core:stick"}})
minetest.register_craft({output = "theocraft_circus:banner_rainbow 2", type = "shapeless", recipe = {"mcl_wool:magenta", "mcl_wool:cyan", "mcl_core:stick"}})
minetest.register_craft({
	output = "theocraft_circus:ticket_booth 1",
	recipe = {
		{"theocraft_circus:canvas_striped_red", "theocraft_circus:canvas_striped_red", "theocraft_circus:canvas_striped_red"},
		{"group:wood", "mcl_core:paper", "group:wood"},
	},
})
minetest.register_craft({
	output = "theocraft_circus:popcorn_stand 1",
	recipe = {
		{"mcl_wool:red", "mcl_wool:white", "mcl_wool:red"},
		{"group:wood", "mcl_core:bowl", "group:wood"},
	},
})
minetest.register_craft({
	output = "theocraft_circus:prize_stand 1",
	recipe = {
		{"mcl_wool:pink", "mcl_wool:yellow", "mcl_wool:pink"},
		{"group:wood", "group:wood", "group:wood"},
	},
})

-- Props: hoop stand, bell, applause, music, switch.
minetest.register_craft({output = "theocraft_circus:hoop_stand 1", recipe = {{"mcl_core:stick", "theocraft_circus:hoop", "mcl_core:stick"}}})
minetest.register_craft({output = "theocraft_circus:performance_bell 1", recipe = {{"mcl_core:gold_ingot"}, {"group:wood"}}})
minetest.register_craft({output = "theocraft_circus:applause_box 1", recipe = {{"group:wood", "mcl_wool:pink", "group:wood"}}})
minetest.register_craft({output = "theocraft_circus:music_box_off 1", recipe = {{"group:wood", "mcl_core:gold_ingot", "group:wood"}}})
minetest.register_craft({output = "theocraft_circus:curtain_switch 1", recipe = {{"mcl_wool:red", "mcl_core:gold_ingot", "mcl_wool:blue"}}})

-- Items: hat, cane, juggling, hoop, ribbon, tickets, popper, wand, disc.
minetest.register_craft({
	output = "theocraft_circus:ringmaster_hat 1",
	recipe = {{"mcl_wool:black", "mcl_wool:black", "mcl_wool:black"}, {"", "mcl_dye:yellow", ""}},
})
minetest.register_craft({
	output = "theocraft_circus:ringmaster_cane 1",
	type = "shapeless",
	recipe = {"mcl_core:stick", "mcl_core:gold_ingot", "mcl_wool:red"},
})
minetest.register_craft({
	output = "theocraft_circus:juggling_balls 3",
	type = "shapeless",
	recipe = {"mcl_wool:red", "mcl_wool:blue", "mcl_wool:yellow"},
})
minetest.register_craft({
	output = "theocraft_circus:juggling_clubs 2",
	recipe = {{"mcl_core:stick"}, {"mcl_wool:magenta"}, {"mcl_wool:white"}},
})
minetest.register_craft({
	output = "theocraft_circus:hoop 1",
	type = "shapeless",
	recipe = {"mcl_mobitems:string", "mcl_mobitems:string", "mcl_dye:pink"},
})
minetest.register_craft({
	output = "theocraft_circus:acrobat_ribbon 1",
	type = "shapeless",
	recipe = {"mcl_core:stick", "mcl_wool:magenta", "mcl_wool:cyan"},
})
minetest.register_craft({
	output = "theocraft_circus:ticket 8",
	type = "shapeless",
	recipe = {"mcl_core:paper", "mcl_dye:yellow"},
})
minetest.register_craft({
	output = "theocraft_circus:popcorn 2",
	type = "shapeless",
	recipe = {"mcl_farming:wheat", "mcl_core:bowl", "mcl_core:sugar"},
})
minetest.register_craft({
	output = "theocraft_circus:confetti_popper 2",
	type = "shapeless",
	recipe = {"mcl_core:paper", "mcl_dye:red", "mcl_dye:blue"},
})
minetest.register_craft({
	output = "theocraft_circus:music_disc 1",
	type = "shapeless",
	recipe = {"mcl_wool:cyan", "mcl_core:gold_ingot", "mcl_wool:magenta"},
})
minetest.register_craft({
	output = "theocraft_circus:magic_wand 1",
	type = "shapeless",
	recipe = {"mcl_core:stick", "mcl_dye:violet", "mcl_core:sugar"},
})

-- Fuel: canvas and crates burn briefly like other cloth/wood (cosy, controlled).
minetest.register_craft({type = "fuel", recipe = "theocraft_circus:canvas_red", burntime = 4})
minetest.register_craft({type = "fuel", recipe = "theocraft_circus:crate", burntime = 12})
