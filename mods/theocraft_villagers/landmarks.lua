local mod = theocraft_villagers

-- Named places villagers can be sent to. Worlds don't ship with landmarks, so
-- players name their own spots with /tcmark, and every world is also seeded with
-- one default "village" landmark (a random name) that idle villagers drift back
-- to. The storage + beacon pattern mirrors locate.lua's villager registry.

local STORAGE_KEY = "landmarks"
local SAVE_DELAY = 3   -- seconds; coalesces bursts of writes into one

-- Names for the auto-created starting village.
local VILLAGE_NAMES = {
	"Oakhollow", "Mistford", "Stonebrook", "Ravenmoor", "Elmsworth",
	"Thornvale", "Barleywick", "Greyfen", "Duskmere", "Hearthglen",
}

-- name_lower -> {name = <display>, x, y, z, owner, village?, auto?}
-- A landmark may exist without x/y/z (an unanchored village awaiting its spot).
mod.landmarks = {}

local function load_landmarks()
	local saved = mod.storage:get_string(STORAGE_KEY)
	local decoded = saved ~= "" and minetest.parse_json(saved) or nil
	mod.landmarks = type(decoded) == "table" and decoded or {}
end
load_landmarks()

local save_scheduled = false
local function save_landmarks()
	if save_scheduled then return end
	save_scheduled = true
	minetest.after(SAVE_DELAY, function()
		save_scheduled = false
		local encoded = minetest.write_json(mod.landmarks)
		if encoded then mod.storage:set_string(STORAGE_KEY, encoded) end
	end)
end
mod.save_landmarks = save_landmarks

-- Look up a landmark by name (case-insensitive). May return an unanchored one;
-- callers that need a position must check `.x`.
function mod.get_landmark(name)
	if type(name) ~= "string" then return nil end
	return mod.landmarks[name:lower()]
end

-- Display names of every *anchored* landmark, sorted, for the action menus.
function mod.landmark_names()
	local names = {}
	for _, e in pairs(mod.landmarks) do
		if e.name and e.x then names[#names + 1] = e.name end
	end
	table.sort(names)
	return names
end

function mod.get_village()
	for _, e in pairs(mod.landmarks) do
		if e.village then return e end
	end
	return nil
end

-- While the village is still auto-placed, keep it centred on the villagers.
-- Called from locate.lua's 3s scan with the villager centroid.
function mod.recenter_village(pos)
	local v = mod.get_village()
	if not v or not v.auto or not pos then return end
	local nx = math.floor(pos.x + 0.5)
	local ny = math.floor(pos.y + 0.5)
	local nz = math.floor(pos.z + 0.5)
	if v.x == nx and v.y == ny and v.z == nz then return end
	v.x, v.y, v.z = nx, ny, nz
	save_landmarks()
end

local function seed_village()
	if mod.get_village() then return end
	local idx = (math.floor(minetest.get_us_time()) % #VILLAGE_NAMES) + 1
	local name = VILLAGE_NAMES[idx]
	local rec = {name = name, village = true, auto = true, owner = ""}
	-- Anchor on the world spawn if we know it; otherwise stay unanchored until
	-- the first villager is seen and recenter_village fills it in.
	local spawn = minetest.setting_get_pos and minetest.setting_get_pos("static_spawnpoint")
	if spawn then
		rec.x = math.floor(spawn.x + 0.5)
		rec.y = math.floor(spawn.y + 0.5)
		rec.z = math.floor(spawn.z + 0.5)
	end
	mod.landmarks[name:lower()] = rec
	save_landmarks()
	minetest.log("action", "[theocraft_villagers] seeded default village '" .. name .. "'")
end
seed_village()

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

minetest.register_chatcommand("tcmark", {
	params = "<name>",
	description = "Name your current spot as a landmark villagers can be sent to",
	func = function(player_name, param)
		local player = minetest.get_player_by_name(player_name)
		if not player then return false, "No player." end
		local name = trim(param)
		if name == "" then return false, "Usage: /tcmark <name>" end
		if #name > 40 then name = name:sub(1, 40) end
		local pos = player:get_pos()
		if not pos then return false, "No position." end

		local key = name:lower()
		local existed = mod.landmarks[key]
		local rec = existed or {}
		rec.name = name
		rec.owner = player_name
		rec.x = math.floor(pos.x + 0.5)
		rec.y = math.floor(pos.y + 0.5)
		rec.z = math.floor(pos.z + 0.5)
		if rec.village then rec.auto = false end   -- pinning the village stops auto-recentre
		mod.landmarks[key] = rec
		save_landmarks()

		return true, string.format("%s '%s' at %d, %d, %d.",
			existed and "Moved landmark" or "Marked landmark", name, rec.x, rec.y, rec.z)
	end,
})

minetest.register_chatcommand("tcmarks", {
	params = "[name]",
	description = "List landmarks, or drop a beacon on one by name",
	func = function(player_name, param)
		local player = minetest.get_player_by_name(player_name)
		if not player then return false, "No player." end
		local ppos = player:get_pos()
		local filter = trim(param)

		if filter ~= "" then
			local e = mod.get_landmark(filter)
			if not e or not e.x then return false, "No landmark named '" .. filter .. "'." end
			local pos = {x = e.x, y = e.y, z = e.z}
			if mod.place_waypoint then mod.place_waypoint(player, e.name, pos) end
			return true, string.format("%s is at %d, %d, %d — %d blocks away. Follow the gold beacon.",
				e.name, e.x, e.y, e.z, math.floor(vector.distance(ppos, pos)))
		end

		local list = {}
		for _, e in pairs(mod.landmarks) do
			if e.x then list[#list + 1] = e end
		end
		if #list == 0 then
			return true, "No landmarks yet. Stand somewhere and use /tcmark <name>."
		end
		table.sort(list, function(a, b)
			return vector.distance(ppos, {x = a.x, y = a.y, z = a.z})
				< vector.distance(ppos, {x = b.x, y = b.y, z = b.z})
		end)
		local lines = {"Landmarks:"}
		for _, e in ipairs(list) do
			local d = math.floor(vector.distance(ppos, {x = e.x, y = e.y, z = e.z}))
			lines[#lines + 1] = string.format("  %s%s — %d, %d, %d (%d away)",
				e.name, e.village and " (village)" or "", e.x, e.y, e.z, d)
		end
		if mod.place_waypoint then
			mod.place_waypoint(player, list[1].name, {x = list[1].x, y = list[1].y, z = list[1].z})
		end
		return true, table.concat(lines, "\n")
	end,
})

minetest.register_chatcommand("tcsethome", {
	params = "<villager> <landmark>",
	description = "Give a villager a home they return to when idle (a landmark name, or x y z coords)",
	func = function(player_name, param)
		local player = minetest.get_player_by_name(player_name)
		if not player then return false, "No player." end
		local villager_name, rest = (param or ""):match("^%s*(%S+)%s+(.-)%s*$")
		if not villager_name or not rest or rest == "" then
			return false, "Usage: /tcsethome <villager> <landmark>"
		end

		-- Home target: a known landmark by name, or raw "x y z" coordinates.
		local home_ref, label
		local lm = mod.get_landmark(rest)
		if lm and lm.x then
			home_ref, label = {landmark = lm.name}, lm.name
		else
			local x, y, z = rest:match("^(-?%d+)%s+(-?%d+)%s+(-?%d+)$")
			if x then
				home_ref = {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
				label = string.format("%s, %s, %s", x, y, z)
			else
				return false, "No landmark named '" .. rest .. "'. Mark it first with /tcmark, " ..
					"or give coordinates: /tcsethome " .. villager_name .. " x y z"
			end
		end

		-- Apply to the nearest loaded villager with that name.
		local ppos = player:get_pos()
		local best, best_d
		for _, e in pairs(minetest.luaentities) do
			if e.name == "mobs_mc:villager" and e._theocraft_name
				and e._theocraft_name:lower() == villager_name:lower() then
				local pos = e.object and e.object:get_pos()
				if pos then
					local d = vector.distance(ppos, pos)
					if not best_d or d < best_d then best, best_d = e, d end
				end
			end
		end
		if not best then
			return false, "No villager named '" .. villager_name ..
				"' is loaded nearby. Walk up to them and try again."
		end

		best._theocraft_home = home_ref
		best._theocraft_next_roam = nil   -- re-evaluate drift against the new home
		local born = best._theocraft_born and (" (born " .. best._theocraft_born .. ")") or ""
		return true, string.format("%s%s will call %s home.", best._theocraft_name, born, label)
	end,
})

minetest.register_chatcommand("tcteleport", {
	params = "<villager> here | <landmark> | x y z",
	description = "Teleport a loaded villager to you, a named landmark, or coordinates",
	func = function(player_name, param)
		local player = minetest.get_player_by_name(player_name)
		if not player then return false, "No player." end
		local villager_name, rest = (param or ""):match("^%s*(%S+)%s+(.-)%s*$")
		if not villager_name or not rest or rest == "" then
			return false, "Usage: /tcteleport <villager> here | <landmark> | x y z"
		end

		-- Nearest loaded villager with that name (same finder as /tcsethome).
		local ppos = player:get_pos()
		local best, best_d
		for _, e in pairs(minetest.luaentities) do
			if e.name == "mobs_mc:villager" and e._theocraft_name
				and e._theocraft_name:lower() == villager_name:lower() then
				local pos = e.object and e.object:get_pos()
				if pos then
					local d = vector.distance(ppos, pos)
					if not best_d or d < best_d then best, best_d = e, d end
				end
			end
		end
		if not best then
			return false, "No villager named '" .. villager_name ..
				"' is loaded nearby. Walk up to them and try again."
		end

		-- Destination: "here"/me, a known landmark, or raw x y z coords. Landmark
		-- and player targets reuse the teleport action so the villager ends up
		-- placed and set to "stay" exactly like the in-chat command.
		local low = rest:lower()
		if low == "here" or low == "me" or low == "you" then
			mod.apply_action(best, player, {type = "teleport", destination = "player"})
			return true, best._theocraft_name .. " blinked over to you."
		end
		local lm = mod.get_landmark(rest)
		if lm and lm.x then
			mod.apply_action(best, player, {type = "teleport", landmark = lm.name})
			return true, best._theocraft_name .. " blinked to " .. lm.name .. "."
		end
		local x, y, z = rest:match("^(-?%d+)%s+(-?%d+)%s+(-?%d+)$")
		if x then
			best.object:set_velocity(vector.zero())
			best.object:set_pos({x = tonumber(x), y = tonumber(y), z = tonumber(z)})
			best._theocraft_instruction = {type = "stay", player = player_name}
			return true, string.format("%s blinked to %s, %s, %s.", best._theocraft_name, x, y, z)
		end
		return false, "No landmark named '" .. rest ..
			"'. Use 'here', a landmark name, or x y z coordinates."
	end,
})

minetest.register_chatcommand("tcunmark", {
	params = "<name>",
	description = "Remove a landmark",
	func = function(player_name, param)
		local name = trim(param)
		if name == "" then return false, "Usage: /tcunmark <name>" end
		local key = name:lower()
		local e = mod.landmarks[key]
		if not e then return false, "No landmark named '" .. name .. "'." end
		mod.landmarks[key] = nil
		save_landmarks()
		local note = e.village and " (the default village re-seeds on next world load)" or ""
		return true, "Removed landmark '" .. e.name .. "'." .. note
	end,
})
