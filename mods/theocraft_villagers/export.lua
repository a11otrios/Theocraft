local mod = theocraft_villagers

-- Move villagers between worlds. A villager's whole self lives in mod storage:
-- the roster (villager_locations: id -> name/bio/birthday/last spot) and her chat
-- memories (history:<sha1> keys). The mob body in the map cannot be lifted out,
-- but /tcexport writes those brains to one JSON file in the world folder, and
-- /tcimport reads them into another world. Memory keys are built from the
-- villager id + player name, so after import the memories reconnect on their own
-- when you run /tcrevive <name>.

local ROSTER_KEY = "villager_locations"   -- must match locate.lua
local EXPORT_VERSION = 1

-- Build the export file path. An optional label lets you keep several exports;
-- with none you get the single default file.
local function export_path(label)
	local name = "theocraft_villagers_export"
	if label and label ~= "" then
		-- Keep filenames tame: letters, digits, underscore and dash only.
		label = label:gsub("[^%w_%-]", "")
		if label ~= "" then name = name .. "_" .. label end
	end
	return minetest.get_worldpath() .. "/" .. name .. ".json", name .. ".json"
end

-- Collect every villager brain currently in this world's storage.
local function gather()
	local all = mod.storage:to_table()
	local fields = (all and all.fields) or {}

	local roster = {}
	local decoded_roster = minetest.parse_json(fields[ROSTER_KEY] or "")
	if type(decoded_roster) == "table" then roster = decoded_roster end

	local histories = {}
	local history_count = 0
	for key, value in pairs(fields) do
		if key:sub(1, 8) == "history:" then
			local decoded = minetest.parse_json(value)
			if type(decoded) == "table" then
				histories[key] = decoded
				history_count = history_count + 1
			end
		end
	end

	local roster_count = 0
	for _ in pairs(roster) do roster_count = roster_count + 1 end

	return {
		version = EXPORT_VERSION,
		exported = os.date("%Y-%m-%d %H:%M:%S"),
		roster = roster,
		histories = histories,
	}, roster_count, history_count
end

minetest.register_chatcommand("tcexport", {
	params = "[label]",
	description = "Save all villagers (names, birthdays and memories) to a file in this world's folder",
	privs = {server = true},
	func = function(player_name, param)
		local label = (param or ""):match("^%s*(.-)%s*$")
		local data, roster_count, history_count = gather()
		if roster_count == 0 and history_count == 0 then
			return false, "No villagers to export yet. Meet some first, then try again."
		end

		local encoded = minetest.write_json(data, true)
		if not encoded then return false, "Could not encode the villager data." end

		local path, shown = export_path(label)
		if not minetest.safe_file_write(path, encoded) then
			return false, "Could not write the export file."
		end
		return true, string.format(
			"Exported %d villager(s) and %d memory record(s) to:\n  %s\n" ..
			"(inside this world's folder — copy that file into another world, then run /tcimport)",
			roster_count, history_count, shown)
	end,
})

minetest.register_chatcommand("tcimport", {
	params = "[label]",
	description = "Load villagers from an export file in this world's folder (then use /tcrevive <name>)",
	privs = {server = true},
	func = function(player_name, param)
		local label = (param or ""):match("^%s*(.-)%s*$")
		local path, shown = export_path(label)

		local file = io.open(path, "r")
		if not file then
			return false, "No export file named " .. shown ..
				" in this world's folder. Copy one in first, then run /tcimport."
		end
		local raw = file:read("*a")
		file:close()

		local data = minetest.parse_json(raw or "")
		if type(data) ~= "table" or type(data.roster) ~= "table" then
			return false, "The file " .. shown .. " is not a valid villager export."
		end

		-- Merge the roster (ids are UUIDs, so imported villagers sit alongside any
		-- already here rather than clobbering them).
		mod.locations = mod.locations or {}
		local imported = 0
		for id, entry in pairs(data.roster) do
			if type(entry) == "table" then
				mod.locations[id] = entry
				imported = imported + 1
			end
		end
		local encoded_roster = minetest.write_json(mod.locations)
		if encoded_roster then mod.storage:set_string(ROSTER_KEY, encoded_roster) end

		-- Restore the chat memories. Keys carry the villager id + player name, so
		-- /tcrevive reconnects them automatically for the matching player.
		local memories = 0
		if type(data.histories) == "table" then
			for key, history in pairs(data.histories) do
				if type(key) == "string" and key:sub(1, 8) == "history:" then
					local encoded = minetest.write_json(history)
					if encoded then
						mod.storage:set_string(key, encoded)
						memories = memories + 1
					end
				end
			end
		end

		return true, string.format(
			"Imported %d villager(s) and %d memory record(s).\n" ..
			"Use /tcrevive <name> to bring each one here (add their birthday to pick a specific one).",
			imported, memories)
	end,
})
