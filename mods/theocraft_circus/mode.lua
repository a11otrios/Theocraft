-- Theo's Circus Mode: soft landings, follow-spots, confetti, and encouragement.
local mod = theocraft_circus

local function near_circus(pos, radius)
	if not pos then return false end
	local r = radius or mod.area_radius()
	local found = minetest.find_node_near(pos, r, {"group:circus"})
	return found ~= nil
end

function mod.player_in_circus(player)
	if not (player and player:is_player()) then return false end
	local pos = player:get_pos()
	if not pos then return false end
	return near_circus(pos, mod.area_radius())
end

-- Cancel fall damage inside circus areas; replace it with applause.
if minetest.register_on_player_hpchange then
	minetest.register_on_player_hpchange(function(player, hp_change, reason)
		if hp_change >= 0 then return hp_change end
		if not mod.fall_protect_enabled() then return hp_change end
		if not reason or reason.type ~= "fall" then return hp_change end
		if not mod.player_in_circus(player) then return hp_change end
		local name = player:get_player_name()
		minetest.after(0.1, function()
			local p = minetest.get_player_by_name(name)
			if p then
				local pos = p:get_pos()
				if pos then mod.sparkle({x = pos.x, y = pos.y + 0.5, z = pos.z}, "soft") end
			end
			if name and name ~= "" then
				minetest.chat_send_player(name, "[Circus] Soft landing! Theo's Circus Mode kept you safe. Bravo!")
			end
		end)
		return 0
	end, true)
end

-- Follow-spot: while performing in a circus area, nearby spotlights stay lit
-- and a gentle sparkle follows the player like a kind follow-spot.
local follow_timer = 0
minetest.register_globalstep(function(dtime)
	if not mod.is_theo_mode() then return end
	follow_timer = follow_timer + dtime
	if follow_timer < 4 then return end
	follow_timer = 0
	for _, player in ipairs(minetest.get_connected_players()) do
		local pos = player:get_pos()
		if pos and near_circus(pos, mod.area_radius()) then
			local off = minetest.find_node_near(pos, 10, {"theocraft_circus:spotlight_off"})
			if off then
				local n = minetest.get_node(off)
				minetest.swap_node(off, {name = "theocraft_circus:spotlight_on", param2 = n.param2})
				mod.safe_sound("mcl_note_block_pling", {pos = off, gain = 0.3})
			end
			if mod.confetti_enabled() and math.random() < 0.25 then
				mod.sparkle({x = pos.x, y = pos.y + 2.2, z = pos.z}, "follow")
			end
		end
	end
end)

-- Cheer when placing circus pieces; helps Theo build a route/course.
minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
	if not (placer and placer:is_player()) then return end
	if not mod.is_theo_mode() then return end
	local def = newnode and minetest.registered_nodes[newnode.name]
	if not def then return end
	local groups = def.groups or {}
	if not groups.circus then return end
	if math.random() < 0.20 then
		mod.cheer(placer:get_player_name())
	end
end)

-- Circus route helper: count nearby course pieces for building obstacle courses.
minetest.register_chatcommand("tccourse", {
	params = "[radius]",
	description = "Count nearby circus course pieces (beams, ropes, mats, hoops, trampolines) for building a route",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then return false, "You must be in the game." end
		local radius = tonumber(param) or 20
		if radius < 4 then radius = 4 end
		if radius > 48 then radius = 48 end
		local pos = player:get_pos()
		local found = minetest.find_nodes_in_area(
			{x = pos.x - radius, y = pos.y - radius, z = pos.z - radius},
			{x = pos.x + radius, y = pos.y + radius, z = pos.z + radius},
			{"group:circus"})
		local counts = {}
		for _, p in ipairs(found) do
			local n = minetest.get_node(p)
			counts[n.name] = (counts[n.name] or 0) + 1
		end
		local total = #found
		if total == 0 then
			return true, "No circus pieces nearby yet. Use /tccircuskit and build a colourful route with beams, ropes, mats, hoops, and trampolines!"
		end
		local top = {}
		for node_name, c in pairs(counts) do
			top[#top + 1] = node_name:gsub("theocraft_circus:", "") .. " x" .. c
			if #top >= 6 then break end
		end
		return true, "Circus route: " .. total .. " pieces nearby (" .. table.concat(top, ", ") ..
			"). Link them into an obstacle course with soft mats underneath!"
	end,
})
