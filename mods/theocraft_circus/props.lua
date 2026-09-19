-- Interactable circus props. Every interaction is gentle, forgiving,
-- and never damages players, villagers, animals, or builds.
local mod = theocraft_circus

local function sound_wood()
	if mcl_sounds and mcl_sounds.node_sound_wood_defaults then
		return mcl_sounds.node_sound_wood_defaults()
	end
end

local function gentle_boost(player, up, forward)
	if not (player and player:is_player()) then return end
	local ok = pcall(function()
		if player.add_velocity then
			local dir = player:get_look_dir() or {x = 0, y = 0, z = 0}
			player:add_velocity({x = dir.x * (forward or 0), y = up or 3, z = dir.z * (forward or 0)})
		elseif player.setvelocity then
			local v = player:get_velocity() or {x = 0, y = 0, z = 0}
			v.y = (v.y or 0) + (up or 3)
			player:setvelocity(v)
		end
	end)
	if not ok then
		-- Movement helpers are best-effort; the show goes on without them.
	end
end

-- 1. Tightrope (thin walkable line; place mats underneath).
minetest.register_node("theocraft_circus:tightrope", {
	description = "Circus Tightrope",
	_doc_items_longdesc = "A thin friendly tightrope. Walk across slowly; wobbles are just for fun, and mats below keep practice safe.",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	tiles = {"wool_white.png^[colorize:#B0B0B0:60"},
	node_box = {type = "fixed", fixed = {{-0.50, -0.06, -0.06, 0.50, 0.06, 0.06}}},
	selection_box = {type = "fixed", fixed = {-0.5, -0.3, -0.3, 0.5, 0.3, 0.3}},
	collision_box = {type = "fixed", fixed = {{-0.50, -0.06, -0.06, 0.50, 0.06, 0.06}}},
	walkable = true,
	groups = {handy = 1, deco_block = 1, circus = 1, circus_rope = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 0.6,
	on_rightclick = function(pos, node, clicker, itemstack)
		if clicker and clicker:is_player() then
			minetest.chat_send_player(clicker:get_player_name(),
				"[Circus] Steady... arms out! Amazing balance! Mats below keep you safe.")
			mod.sparkle({x = pos.x, y = pos.y + 0.5, z = pos.z}, "rope")
		end
		return itemstack
	end,
})

minetest.register_node("theocraft_circus:tightrope_anchor", {
	description = "Tightrope Anchor Post",
	_doc_items_longdesc = "A sturdy striped post that holds the tightrope. Place two anchors and span the rope between them.",
	tiles = {"wool_red.png^wool_white.png^[opacity:110"},
	is_ground_content = false,
	groups = {handy = 1, axey = 1, building_block = 1, circus = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1.0,
})

-- 2. Trapeze Bar (grab, gentle swing, easy release).
minetest.register_node("theocraft_circus:trapeze", {
	description = "Circus Trapeze Bar",
	_doc_items_longdesc = "Hang it from chains or ropes. Right-click to grab and enjoy a gentle swing, then hop off safely.",
	drawtype = "nodebox",
	paramtype = "light",
	sunlight_propagates = true,
	tiles = {"wool_brown.png"},
	node_box = {type = "fixed", fixed = {
		{-0.05, 0.30, -0.05, 0.05, 0.50, 0.05},
		{-0.45, -0.10, -0.05, 0.45, 0.05, 0.05},
	}},
	selection_box = {type = "fixed", fixed = {-0.5, -0.1, -0.1, 0.5, 0.5, 0.1}},
	groups = {handy = 1, deco_block = 1, circus = 1, circus_trapeze = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 0.8,
	on_rightclick = function(pos, node, clicker, itemstack)
		if clicker and clicker:is_player() then
			gentle_boost(clicker, 3.5, 2.0)
			mod.sparkle({x = pos.x, y = pos.y, z = pos.z}, "trapeze")
			minetest.chat_send_player(clicker:get_player_name(), "[Circus] Whee! A graceful trapeze swing! Fantastic circus trick!")
			mod.cheer(clicker:get_player_name())
		end
		return itemstack
	end,
})

-- 3. Swing Rope (gentle obstacle-course swing).
minetest.register_node("theocraft_circus:swing_rope", {
	description = "Circus Swing Rope",
	_doc_items_longdesc = "A soft knotted rope for circus obstacle courses. Right-click for a gentle forward swing.",
	drawtype = "nodebox",
	paramtype = "light",
	sunlight_propagates = true,
	tiles = {"wool_brown.png^[colorize:#FFFFFF:40"},
	node_box = {type = "fixed", fixed = {{-0.06, -0.50, -0.06, 0.06, 0.50, 0.06}}},
	selection_box = {type = "fixed", fixed = {-0.1, -0.5, -0.1, 0.1, 0.5, 0.1}},
	groups = {handy = 1, deco_block = 1, circus = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 0.6,
	on_rightclick = function(pos, node, clicker, itemstack)
		if clicker and clicker:is_player() then
			gentle_boost(clicker, 2.5, 3.0)
			minetest.chat_send_player(clicker:get_player_name(), "[Circus] Swinging along the circus course! Brilliant jump coming up!")
		end
		return itemstack
	end,
})

-- 4. Mini Trampoline (gentle bounce via engine bouncy group + cushion).
minetest.register_node("theocraft_circus:trampoline", {
	description = "Circus Mini Trampoline",
	_doc_items_longdesc = "A small, safe trampoline. It bounces the player gently upward and cushions every landing.",
	tiles = {
		"wool_blue.png^[colorize:#FFFFFF:60",
		"wool_blue.png",
		"wool_red.png",
		"wool_red.png",
		"wool_red.png",
		"wool_red.png",
	},
	is_ground_content = false,
	groups = {
		handy = 1, deco_block = 1, circus = 1, circus_trampoline = 1,
		bouncy = 60, fall_damage_add_percent = -100,
	},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 0.8,
	on_rightclick = function(pos, node, clicker, itemstack)
		if clicker and clicker:is_player() then
			gentle_boost(clicker, 6.0, 0)
			mod.confetti(pos)
			minetest.chat_send_player(clicker:get_player_name(), "[Circus] Boing! A bouncy circus bounce! Brilliant jump!")
		end
		return itemstack
	end,
})

-- 5. Rola Bola Board (wobble prop, stays safe).
minetest.register_node("theocraft_circus:rola_bola", {
	description = "Circus Rola Bola Board",
	_doc_items_longdesc = "A cheerful balance board. Stand on it and wobble for fun — falling off just means applause.",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	tiles = {"wool_red.png^wool_blue.png^[opacity:110"},
	node_box = {type = "fixed", fixed = {
		{-0.40, -0.50, -0.15, 0.40, -0.30, 0.15},
		{-0.50, -0.30, -0.25, 0.50, -0.20, 0.25},
	}},
	selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.25, 0.5, -0.2, 0.25}},
	groups = {handy = 1, deco_block = 1, circus = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 0.8,
	on_rightclick = function(pos, node, clicker, itemstack)
		if clicker and clicker:is_player() then
			minetest.chat_send_player(clicker:get_player_name(), "[Circus] Wobble-wobble! Amazing balance! The crowd claps along!")
			mod.sparkle({x = pos.x, y = pos.y + 0.4, z = pos.z}, "wobble")
		end
		return itemstack
	end,
})

-- 6. Hoop Stand (holds hoop upright; jumping through is rewarded).
minetest.register_node("theocraft_circus:hoop_stand", {
	description = "Circus Hoop Stand",
	_doc_items_longdesc = "Holds a circus hoop upright. Jump through the hoop for cheers and challenge progress.",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	tiles = {"wool_yellow.png^[colorize:#FF4FA3:80"},
	node_box = {type = "fixed", fixed = {
		{-0.50, -0.50, -0.08, -0.40, 0.50, 0.08},
		{0.40, -0.50, -0.08, 0.50, 0.50, 0.08},
		{-0.40, 0.30, -0.08, 0.40, 0.50, 0.08},
	}},
	selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.1, 0.5, 0.5, 0.1}},
	groups = {handy = 1, deco_block = 1, circus = 1, circus_hoop = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 0.8,
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", "Circus Hoop Stand (jump through!)")
	end,
})

-- 7. Performance Bell (starts the show).
minetest.register_node("theocraft_circus:performance_bell", {
	description = "Circus Performance Bell",
	_doc_items_longdesc = "Ring it to start the show: curtains open, spotlights glow, music plays, and friends applaud.",
	tiles = {"wool_yellow.png^[colorize:#FFD23F:150"},
	is_ground_content = false,
	groups = {handy = 1, pickaxey = 1, deco_block = 1, circus = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1.0,
	on_rightclick = function(pos, node, clicker, itemstack)
		mod.safe_sound("mcl_note_block_pling", {pos = pos, gain = 0.8})
		mod.confetti(pos)
		if clicker and clicker:is_player() then
			minetest.chat_send_all("[Circus] Ding-ding! " .. clicker:get_player_name() .. "'s circus show is beginning!")
		else
			minetest.chat_send_all("[Circus] Ding-ding! The circus show is beginning!")
		end
		if mod.start_show then mod.start_show(pos) end
		return itemstack
	end,
})

-- 8. Applause Box (plays applause cheer).
minetest.register_node("theocraft_circus:applause_box", {
	description = "Circus Applause Box",
	_doc_items_longdesc = "A friendly box of recorded cheers. Right-click after any trick for instant applause.",
	tiles = {"wool_pink.png^[colorize:#FFFFFF:50"},
	is_ground_content = false,
	groups = {handy = 1, deco_block = 1, circus = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 0.8,
	on_rightclick = function(pos, node, clicker, itemstack)
		mod.safe_sound("mcl_note_block_pling", {pos = pos, gain = 0.7})
		mod.confetti(pos)
		minetest.chat_send_all("[Circus] Clap-clap-clap! The crowd goes wild!")
		return itemstack
	end,
})

-- 9. Circus Music Box (toggleable background jingle).
minetest.register_node("theocraft_circus:music_box_off", {
	description = "Circus Music Box (Off)",
	_doc_items_longdesc = "Right-click to start the cheerful circus background music. Right-click again to stop.",
	tiles = {"wool_purple.png", "wool_purple.png", "wool_cyan.png",
		"wool_cyan.png", "wool_purple.png", "wool_purple.png"},
	is_ground_content = false,
	groups = {handy = 1, deco_block = 1, circus = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 0.8,
	on_rightclick = function(pos, node, clicker)
		mod.set_music_box(pos, true)
		if clicker and clicker:is_player() then
			minetest.chat_send_player(clicker:get_player_name(), "[Circus] The circus band begins to play! Oom-pah-pah!")
		end
		return clicker and clicker:get_wielded_item() or nil
	end,
	on_destruct = function(pos)
		mod.stop_music_at(pos)
	end,
})

minetest.register_node("theocraft_circus:music_box_on", {
	description = "Circus Music Box (On)",
	_doc_items_longdesc = "The circus band is playing! Right-click to stop the music.",
	tiles = {"wool_violet.png^[colorize:#FFFFFF:50", "wool_violet.png^[colorize:#FFFFFF:50",
		"wool_cyan.png^[colorize:#FFFFFF:50", "wool_cyan.png^[colorize:#FFFFFF:50",
		"wool_violet.png^[colorize:#FFFFFF:50", "wool_violet.png^[colorize:#FFFFFF:50"},
	is_ground_content = false,
	paramtype = "light",
	light_source = 6,
	groups = {handy = 1, deco_block = 1, circus = 1, not_in_creative_inventory = 1},
	sounds = sound_wood(),
	drop = "theocraft_circus:music_box_off",
	_mcl_blast_resistance = 1,
	_mcl_hardness = 0.8,
	on_rightclick = function(pos, node, clicker)
		mod.set_music_box(pos, false)
		return clicker and clicker:get_wielded_item() or nil
	end,
	on_destruct = function(pos)
		mod.stop_music_at(pos)
	end,
})

-- 10. Curtain Switch (opens nearby curtains + lights spotlights).
minetest.register_node("theocraft_circus:curtain_switch", {
	description = "Circus Curtain Switch",
	_doc_items_longdesc = "One click opens nearby curtains and turns on nearby spotlights. Pure showtime magic.",
	tiles = {"wool_red.png", "wool_red.png", "wool_yellow.png^[colorize:#FFD23F:120",
		"wool_yellow.png^[colorize:#FFD23F:120", "wool_red.png", "wool_red.png"},
	is_ground_content = false,
	groups = {handy = 1, pickaxey = 1, deco_block = 1, circus = 1},
	sounds = sound_wood(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1.0,
	on_rightclick = function(pos, node, clicker, itemstack)
		local opened, lit = 0, 0
		for _, p in ipairs(minetest.find_nodes_in_area(
			{x = pos.x - 10, y = pos.y - 5, z = pos.z - 10},
			{x = pos.x + 10, y = pos.y + 5, z = pos.z + 10},
			{"group:circus_curtain", "theocraft_circus:spotlight_off"})) do
			local n = minetest.get_node(p)
			if n.name == "theocraft_circus:spotlight_off" then
				minetest.swap_node(p, {name = "theocraft_circus:spotlight_on", param2 = n.param2})
				lit = lit + 1
			else
				local base = n.name:match("^(theocraft_circus:curtain_[a-z]+)_closed$")
				if base then
					minetest.swap_node(p, {name = base .. "_open", param2 = n.param2})
					opened = opened + 1
				end
			end
		end
		mod.safe_sound("mcl_note_block_pling", {pos = pos, gain = 0.6})
		if clicker and clicker:is_player() then
			minetest.chat_send_player(clicker:get_player_name(),
				"[Circus] Curtains opening (" .. opened .. ") and spotlights glowing (" .. lit .. ")! Showtime!")
		end
		return itemstack
	end,
})
