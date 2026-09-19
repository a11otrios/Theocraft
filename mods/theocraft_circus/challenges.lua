-- Mini-games, Ringmaster Show Mode, and friendly chat commands.
local mod = theocraft_circus

local function give(player, itemstring)
	local inv = player and player:get_inventory()
	if not inv then return false end
	if not inv:room_for_item("main", itemstring) then
		local pos = player:get_pos()
		if pos then
			pos.y = pos.y + 0.5
			minetest.add_item(pos, itemstring)
			return true
		end
		return false
	end
	inv:add_item("main", itemstring)
	return true
end

local function award_medal(player, reason)
	if give(player, "theocraft_circus:performer_medal 1") then
		minetest.chat_send_player(player:get_player_name(),
			"[Circus] You earned a Performer Medal: " .. reason .. " Well done!")
		local pos = player:get_pos()
		if pos then mod.confetti(pos) end
	end
end

-- Ringmaster Show Mode: curtains open, spotlights on, music, confetti, applause.
function mod.start_show(center)
	center = center or {x = 0, y = 0, z = 0}
	local c = {x = math.floor(center.x), y = math.floor(center.y), z = math.floor(center.z)}
	local opened, lit = 0, 0
	for _, p in ipairs(minetest.find_nodes_in_area(
		{x = c.x - 12, y = c.y - 6, z = c.z - 12},
		{x = c.x + 12, y = c.y + 6, z = c.z + 12},
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
	minetest.chat_send_all("[Circus] Curtains open (" .. opened .. ")! Spotlights on (" .. lit .. ")! The show begins!")
	-- Start any nearby circus music boxes through the shared helper so Show
	-- Mode behaves exactly like a manual toggle (sound on, handle tracked).
	for _, p in ipairs(minetest.find_nodes_in_area(
		{x = c.x - 12, y = c.y - 6, z = c.z - 12},
		{x = c.x + 12, y = c.y + 6, z = c.z + 12},
		{"theocraft_circus:music_box_off"})) do
		mod.set_music_box(p, true)
	end
	minetest.chat_send_all("[Circus] Theo's Circus Show has begun!")
	for i = 1, 4 do
		minetest.after(i * 0.7, function()
			mod.safe_sound("mcl_note_block_pling", {pos = center, gain = 0.6})
			mod.sparkle({x = center.x, y = center.y + 2, z = center.z}, "confetti")
		end)
	end
	minetest.after(3.2, function()
		minetest.chat_send_all("[Circus] Clap-clap-clap! The crowd goes wild!")
	end)
end

-- Hoop jumps + tightrope balance are tracked forgivingly in a globalstep.
local timer = 0
local last_hoop_reward = {}

minetest.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 0.5 then return end
	-- Elapsed real seconds since the last pass, so medals measure actual
	-- balancing time instead of a fixed number of polling ticks.
	local elapsed = timer
	timer = 0
	for _, player in ipairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		local pos = player:get_pos()
		if pos and name and name ~= "" then
			pos.y = pos.y + 0.5
			-- Hoop stand nearby + moving = a joyful hoop leap.
			local near_hoop = minetest.find_node_near(pos, 1.4, {"theocraft_circus:hoop_stand"})
			if near_hoop then
				local now = os.time()
				if (now - (last_hoop_reward[name] or 0)) >= 3 then
					last_hoop_reward[name] = now
					local count = (mod.hoop_progress[name] or 0) + 1
					mod.hoop_progress[name] = count
					minetest.chat_send_player(name,
						"[Circus] Whoosh through the hoop! Brilliant jump! (hoops: " .. count .. ")")
					mod.confetti(player:get_pos())
					if count == 5 then award_medal(player, "5 hoop jumps") end
				end
			end
			-- Standing on rope/beam/rola bola earns cheers and, after about a
			-- full minute of continuous balancing, a performer medal.
			local below = {x = pos.x, y = pos.y - 0.6, z = pos.z}
			local node = minetest.get_node_or_nil(below)
			local on_apparatus = node and (node.name == "theocraft_circus:tightrope" or
				node.name == "theocraft_circus:balance_beam" or
				node.name == "theocraft_circus:rola_bola")
			local state = mod.balance_state[name] or {ticks = 0, time = 0, awarded = false}
			mod.balance_state[name] = state
			local practising_ticks = state.ticks or 0
			local event = mod.update_balance(state, on_apparatus and true or false, elapsed)
			if event == "medal" then
				award_medal(player, "a full minute of balancing")
			elseif event == "cheer" then
				minetest.chat_send_player(name, "[Circus] Amazing balance! Keep going, star performer!")
				if mod.is_theo_mode() then mod.sparkle(pos, "balance") end
			elseif not on_apparatus then
				-- Landing on a mat after practice always gets applause, never punishment.
				local landing = minetest.get_node_or_nil({x = pos.x, y = pos.y - 1.2, z = pos.z})
				if landing and landing.name:find("theocraft_circus:practice_mat_", 1, true) then
					if practising_ticks > 4 then
						minetest.chat_send_player(name, "[Circus] Soft landing! What a safe, bouncy finish!")
					end
				end
			end
		end
	end
end)

local function kit(player)
	local items = {
		"theocraft_circus:canvas_striped_red 16",
		"theocraft_circus:pole_red 8",
		"theocraft_circus:ring_sawdust 12",
		"theocraft_circus:seat_wood 8",
		"theocraft_circus:spotlight_off 2",
		"theocraft_circus:fairy_light 8",
		"theocraft_circus:curtain_red_closed 4",
		"theocraft_circus:stage 4",
		"theocraft_circus:ticket_booth 1",
		"theocraft_circus:practice_mat_red 4",
		"theocraft_circus:balance_beam 4",
		"theocraft_circus:tightrope 12",
		"theocraft_circus:tightrope_anchor 2",
		"theocraft_circus:trapeze 1",
		"theocraft_circus:trampoline 1",
		"theocraft_circus:hoop_stand 2",
		"theocraft_circus:ringmaster_hat 1",
		"theocraft_circus:ringmaster_cane 1",
		"theocraft_circus:juggling_balls 1",
		"theocraft_circus:ticket 8",
		"theocraft_circus:popcorn 4",
		"theocraft_circus:confetti_popper 4",
	}
	for _, item in ipairs(items) do give(player, ItemStack(item)) end
end

minetest.register_chatcommand("circus", {
	params = "help | kit | show",
	description = "Theo-friendly circus help, starter kit, and show controls",
	func = function(name, param)
		param = ((param or "help"):lower():match("^%s*(.-)%s*$"))
		local player = minetest.get_player_by_name(name)
		if param == "kit" then
			if not player then return false, "You must be in the game to receive the kit." end
			kit(player)
			return true, "Circus starter kit added: tent, ring, seats, lights, mats, ropes, and costumes!"
		elseif param == "show" then
			if player then
				mod.start_show(player:get_pos())
			else
				mod.start_show(nil)
			end
			return true, "Showtime! Curtains open, spotlights on, music and confetti!"
		end
		return true, "Circus Pack: /circus kit (building treats), /circus show (curtains+lights+music+confetti), " ..
			"/tcshow (same), /tchoop (your hoop count), /tccircuskit (same as kit), " ..
			"/build circus_arena [small|medium|large|rainbow|theos_show] (a whole arena like magic!). " ..
			"Try tightropes over mats, trampolines, hoop stands, and the performance bell!"
	end,
})

minetest.register_chatcommand("tcshow", {
	description = "Start the Ringmaster Show Mode sequence",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if player then mod.start_show(player:get_pos()) else mod.start_show(nil) end
		return true, "Theo's show is starting! Curtains, spotlights, music, confetti, applause!"
	end,
})

minetest.register_chatcommand("tccircuskit", {
	description = "Receive the cheerful circus starter kit",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then return false, "You must be in the game to receive the kit." end
		kit(player)
		return true, "Circus starter kit added to your inventory!"
	end,
})

minetest.register_chatcommand("tchoop", {
	description = "Show your circus hoop-jump and juggling progress",
	func = function(name, param)
		local hoops = mod.hoop_progress[name] or 0
		local juggle = mod.juggle_progress[name]
		local best = juggle and juggle.best or 0
		return true, "Hoop jumps: " .. hoops .. ". Best juggling combo: " .. best ..
			". Jump through hoop stands and juggle in rhythm to earn Performer Medals!"
	end,
})
