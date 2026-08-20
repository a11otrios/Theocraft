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

minetest.register_chatcommand("tcfind", {
	params = "<name>",
	description = "Locate a villager by name (nearest last-known spot + a waypoint beacon)",
	func = function(player_name, param)
		local player = minetest.get_player_by_name(player_name)
		if not player then return false, "No player." end
		local target = (param or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
		if target == "" then return false, "Usage: /tcfind <name>" end

		scan_active()  -- freshest data for anyone loaded right now

		local ppos = player:get_pos()
		local matches = {}
		for _, e in pairs(mod.locations) do
			if e.name and e.name:lower() == target then
				local pos = {x = e.x, y = e.y, z = e.z}
				matches[#matches + 1] = {pos = pos, d = vector.distance(ppos, pos), name = e.name}
			end
		end
		if #matches == 0 then
			return false, "No villager named '" .. param ..
				"' on record yet. Walk near them once so the game learns where they are."
		end
		table.sort(matches, function(a, b) return a.d < b.d end)
		local m = matches[1]
		place_waypoint(player, m.name, m.pos)
		local extra = #matches > 1 and (" (" .. #matches .. " share that name; nearest shown)") or ""
		return true, string.format("%s is at %d, %d, %d — %d blocks away. Follow the gold beacon.%s",
			m.name, m.pos.x, m.pos.y, m.pos.z, math.floor(m.d), extra)
	end,
})
