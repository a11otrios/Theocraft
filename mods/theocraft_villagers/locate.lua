local mod = theocraft_villagers

-- Locate villagers by name. The game can only know positions it has observed, so
-- we keep a small persistent registry of each villager's last-known spot,
-- refreshed whenever the villager is loaded/active. `/tcfind <name>` then reports
-- the nearest match and drops an in-world waypoint beacon toward it.

local STORAGE_KEY = "villager_locations"
local SCAN_INTERVAL = 3      -- seconds between background position refreshes
local WAYPOINT_TTL = 180     -- seconds a /tcfind beacon stays up

-- id -> {name = <string>, x, y, z}
mod.locations = {}
mod.waypoints = mod.waypoints or {}   -- player_name -> hud id

local function load_locations()
	local saved = mod.storage:get_string(STORAGE_KEY)
	local decoded = saved ~= "" and minetest.parse_json(saved) or nil
	mod.locations = type(decoded) == "table" and decoded or {}
end
load_locations()

local save_scheduled = false
local function save_locations()
	-- Coalesce writes: at most one save per scan interval even if called often.
	if save_scheduled then return end
	save_scheduled = true
	minetest.after(SCAN_INTERVAL, function()
		save_scheduled = false
		local encoded = minetest.write_json(mod.locations)
		if encoded then mod.storage:set_string(STORAGE_KEY, encoded) end
	end)
end

-- Update the registry from every currently-active villager.
local function scan_active()
	local changed = false
	for _, entity in pairs(minetest.luaentities) do
		if entity.name == "mobs_mc:villager" and entity._id and entity._theocraft_name then
			local pos = entity.object and entity.object:get_pos()
			if pos then
				mod.locations[entity._id] = {
					name = entity._theocraft_name,
					bio = entity._theocraft_bio,   -- kept so a lost villager can be revived exactly
					born = entity._theocraft_born, -- DDMMYY, to tell same-named villagers apart
					x = math.floor(pos.x + 0.5),
					y = math.floor(pos.y + 0.5),
					z = math.floor(pos.z + 0.5),
				}
				changed = true
			end
		end
	end
	if changed then save_locations() end
end

local accum = 0
minetest.register_globalstep(function(dtime)
	accum = accum + dtime
	if accum < SCAN_INTERVAL then return end
	accum = 0
	scan_active()
end)

local function place_waypoint(player, name, pos)
	local player_name = player:get_player_name()
	if mod.waypoints[player_name] then
		player:hud_remove(mod.waypoints[player_name])
	end
	local id = player:hud_add({
		hud_elem_type = "waypoint",
		name = name,
		text = "m",              -- suffix after the auto distance
		number = 0xFFD000,        -- gold
		world_pos = pos,
	})
	mod.waypoints[player_name] = id
	minetest.after(WAYPOINT_TTL, function()
		local pl = minetest.get_player_by_name(player_name)
		if pl and mod.waypoints[player_name] == id then
			pl:hud_remove(id)
			mod.waypoints[player_name] = nil
		end
	end)
end

-- Parse "<name> [DDMMYY]" -> name, optional birthday (or nil).
local function parse_target(param)
	local tokens = {}
	for w in (param or ""):gmatch("%S+") do tokens[#tokens + 1] = w end
	local born = tokens[2] and tokens[2]:match("^%d%d%d%d%d%d$") or nil
	return tokens[1], born
end

local function born_tag(born)
	return born and (" (born " .. born .. ")") or ""
end

minetest.register_chatcommand("tcfind", {
	params = "<name> [DDMMYY]",
	description = "Locate a villager by name; add their birthday DDMMYY to pick a specific one",
	func = function(player_name, param)
		local player = minetest.get_player_by_name(player_name)
		if not player then return false, "No player." end
		local name, born = parse_target(param)
		if not name then return false, "Usage: /tcfind <name> [DDMMYY]" end
		local target = name:lower()

		scan_active()  -- freshest data for anyone loaded right now

		local ppos = player:get_pos()
		local matches = {}
		for _, e in pairs(mod.locations) do
			if e.name and e.name:lower() == target and (not born or e.born == born) then
				local pos = {x = e.x, y = e.y, z = e.z}
				matches[#matches + 1] = {pos = pos, d = vector.distance(ppos, pos), name = e.name, born = e.born}
			end
		end
		if #matches == 0 then
			return false, "No villager named '" .. name .. "'" .. born_tag(born) ..
				" on record yet. Walk near them once so the game learns where they are."
		end
		table.sort(matches, function(a, b) return a.d < b.d end)

		-- Several share the name and no birthday was given: list them so the player
		-- can pick one.
		if #matches > 1 and not born then
			local lines = {"Several villagers named " .. matches[1].name .. " — add a birthday to pick one:"}
			for _, m in ipairs(matches) do
				lines[#lines + 1] = string.format("  born %s at %d, %d, %d (%d away) -> /tcfind %s %s",
					m.born or "??????", m.pos.x, m.pos.y, m.pos.z, math.floor(m.d), matches[1].name, m.born or "??????")
			end
			return true, table.concat(lines, "\n")
		end

		local m = matches[1]
		place_waypoint(player, m.name, m.pos)
		return true, string.format("%s%s is at %d, %d, %d — %d blocks away. Follow the gold beacon.",
			m.name, born_tag(m.born), m.pos.x, m.pos.y, m.pos.z, math.floor(m.d))
	end,
})

-- ---------------------------------------------------------------------------
-- Revival: bring back a lost villager, with her saved chat memory.
--
-- A villager's whole self (name, bio, personality, voice, history) is tied to a
-- persistent id. If we know that id (villager met since roster tracking) we can
-- respawn her *exactly*, and her history reconnects automatically because it is
-- keyed by id. For older villagers whose id was never recorded, we instead find
-- the best-matching saved conversation by name and graft it onto a fresh villager
-- (memory + name restored; personality/voice are new).

local function history_key_for(id, player_name)
	return "history:" .. minetest.sha1((id or "unknown") .. "\0" .. player_name)
end

-- How many times the player addressed `name` in a saved conversation.
local function name_mentions(history, name)
	local needle, score = name:lower(), 0
	for _, e in ipairs(history) do
		if e.role == "player" and type(e.content) == "string" then
			local from = 1
			local text = e.content:lower()
			while true do
				local s = text:find(needle, from, true)
				if not s then break end
				score = score + 1
				from = s + #needle
			end
		end
	end
	return score
end

-- Best-matching saved conversation for a villager name (or nil).
local function find_saved_history(name)
	local all = mod.storage:to_table()
	local fields = all and all.fields or {}
	local best_v, best_s
	for k, v in pairs(fields) do
		if k:sub(1, 8) == "history:" then
			local decoded = minetest.parse_json(v)
			if type(decoded) == "table" then
				local s = name_mentions(decoded, name)
				if s > 0 and (not best_s or s > best_s) then best_s, best_v = s, v end
			end
		end
	end
	return best_v
end

local function is_active(id)
	for _, e in pairs(minetest.luaentities) do
		if e.name == "mobs_mc:villager" and e._id == id then return true end
	end
	return false
end

-- Is a villager with this name (and optional birthday) already loaded nearby?
local function active_match(name, born)
	for _, e in pairs(minetest.luaentities) do
		if e.name == "mobs_mc:villager" and e._theocraft_name
			and e._theocraft_name:lower() == name:lower()
			and (not born or e._theocraft_born == born) then
			return true
		end
	end
	return false
end

local function spawn_villager(player, id, name, bio, born)
	local pos = player:get_pos()
	if not pos then return nil end
	local obj = minetest.add_entity(pos, "mobs_mc:villager")
	local ent = obj and obj:get_luaentity()
	if not ent then return nil end
	ent._id = id                       -- set before identity/history are resolved
	ent._theocraft_name = name
	if bio and bio ~= "" then ent._theocraft_bio = bio end
	if born and born ~= "" then ent._theocraft_born = born end
	mod.ensure_identity(ent)           -- refreshes the nametag, fills in any blanks
	return ent
end

minetest.register_chatcommand("tcrevive", {
	params = "<name> [DDMMYY]",
	description = "Summon a villager by name (add their birthday DDMMYY to pick a specific one), restoring saved chat memory when possible",
	privs = {server = true},
	func = function(player_name, param)
		local player = minetest.get_player_by_name(player_name)
		if not player then return false, "No player." end
		local name, born = parse_target(param)
		if not name then return false, "Usage: /tcrevive <name> [DDMMYY]" end

		-- Don't duplicate a villager who is already standing here.
		if active_match(name, born) then
			return false, name .. born_tag(born) ..
				" is already here. Use /tcfind " .. name .. " to locate her."
		end

		-- 1) Exact restore when we know this villager's id. Collect roster matches so
		-- a birthday can disambiguate two same-named villagers.
		local candidates = {}
		for id, e in pairs(mod.locations) do
			if e.name and e.name:lower() == name:lower()
				and (not born or e.born == born) and not is_active(id) then
				candidates[#candidates + 1] = {id = id, e = e}
			end
		end
		if #candidates > 1 and not born then
			local lines = {"Several villagers named " .. name .. " — add a birthday to pick one:"}
			for _, c in ipairs(candidates) do
				lines[#lines + 1] = "  /tcrevive " .. name .. " " .. (c.e.born or "??????")
			end
			return true, table.concat(lines, "\n")
		end
		if #candidates >= 1 then
			local c = candidates[1]
			if spawn_villager(player, c.id, c.e.name, c.e.bio, c.e.born) then
				return true, c.e.name .. born_tag(c.e.born) ..
					" is back exactly as before — same voice, personality and memory."
			end
			return false, "Could not spawn the villager."
		end

		-- 2) Otherwise graft the best saved conversation onto a fresh villager.
		local blob = find_saved_history(name)
		local id = mcl_util.gen_uuid()
		if not spawn_villager(player, id, name, nil, os.date("%d%m%y")) then
			return false, "Could not spawn the villager."
		end
		if blob then
			mod.storage:set_string(history_key_for(id, player_name), blob)
			return true, name .. " is back and remembers your past chats. " ..
				"(Her voice and personality are new — the originals weren't recorded before today.)"
		end
		return true, "Summoned a new villager named " .. name ..
			", but found no saved chat to restore."
	end,
})
