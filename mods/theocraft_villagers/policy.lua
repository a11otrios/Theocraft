local mod = theocraft_villagers

-- field -> {min, max}: single source of truth for clamping both the global
-- defaults and per-villager overrides.
local RANGES = {
	message_length = {50, 4000},
	speech_length = {50, 4000},
	history_entries = {2, 200},
	gather_count = {1, 64},
	interaction_distance = {1, 32},
}
mod.limit_ranges = RANGES

local function clamp_field(field, value, default)
	local number = tonumber(value)
	if not number then return default end
	local range = RANGES[field]
	return math.max(range[1], math.min(range[2], math.floor(number)))
end
mod.clamp_limit = clamp_field

-- Read a setting if the engine is present (absent in the unit-test harness).
local function get_setting(name)
	local engine = rawget(_G, "minetest")
	if not engine or not engine.settings then return nil end
	return engine.settings:get(name)
end

local function limit(field, setting_name, default)
	return clamp_field(field, get_setting(setting_name), default)
end

-- Global defaults, read once at load. Per-villager overrides layer on top via
-- mod.resolve_limits.
mod.limits = {
	message_length      = limit("message_length",      "theocraft_message_length",      500),
	speech_length        = limit("speech_length",        "theocraft_speech_length",        700),
	history_entries      = limit("history_entries",      "theocraft_history_entries",       20),
	gather_count         = limit("gather_count",         "theocraft_gather_count",           8),
	interaction_distance = limit("interaction_distance", "theocraft_interaction_distance",   7),
}

-- Effective limits for a villager: its own override for a field when set and
-- valid, otherwise the global default. No overrides -> the shared defaults
-- table (fast path, no allocation).
function mod.resolve_limits(self)
	local over = type(self) == "table" and type(self._theocraft_limits) == "table"
		and self._theocraft_limits or nil
	if not over then return mod.limits end
	local out = {}
	for field, default in pairs(mod.limits) do
		out[field] = clamp_field(field, over[field], default)
	end
	return out
end

local gather_resources = {
	dirt = "group:soil",
	logs = "group:tree",
	sand = "group:sand",
	stone = "group:stone",
	wood = "group:tree",
}

local resource_aliases = {
	log = "wood",
	logs = "wood",
	tree = "wood",
	trees = "wood",
	cobble = "stone",
	cobblestone = "stone",
	soil = "dirt",
}

local function clean_text(value, maximum)
	if type(value) ~= "string" then return "" end
	value = value:gsub("%c", " ")
	value = value:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
	return value:sub(1, maximum)
end

mod.clean_text = clean_text

local function canonical_resource(value)
	value = clean_text(value, 32):lower()
	value = resource_aliases[value] or value
	if gather_resources[value] then return value end
	return nil
end

function mod.resource_query(resource)
	return gather_resources[canonical_resource(resource)]
end

function mod.normalise_action(raw, limits)
	limits = limits or mod.limits
	if raw == nil then return {type = "none"} end
	if type(raw) == "string" then raw = {type = raw} end
	if type(raw) ~= "table" then return {type = "none"} end

	local action_type = clean_text(raw.type or raw.name, 24):lower()
	local args = type(raw.args) == "table" and raw.args or raw
	if action_type == "follow" or action_type == "stay" or action_type == "come" then
		return {type = action_type}
	elseif action_type == "gather" then
		local resource = canonical_resource(args.resource or args.material or args.target)
		if not resource then return {type = "none"} end
		local count = math.floor(tonumber(args.count) or 1)
		count = math.max(1, math.min(limits.gather_count, count))
		return {type = "gather", resource = resource, count = count}
	elseif action_type == "buildhome" or action_type == "buildhouse" then
		return {type = "buildhome"}
	elseif action_type == "build" then
		local blueprint = clean_text(args.blueprint or args.structure, 24):lower()
		if blueprint == "house" or blueprint == "home" then
			return {type = "buildhome"}
		elseif blueprint == "wall" or blueprint == "shelter" then
			return {type = "build", blueprint = blueprint}
		end
	elseif action_type == "goto" or action_type == "go" then
		local target = args.landmark or args.destination or args.target or args.name or args.place
		local lm = type(target) == "string" and mod.get_landmark(clean_text(target, 40))
		if lm and lm.x then return {type = "goto", landmark = lm.name} end
	elseif action_type == "guard" or action_type == "defend" then
		local target = args.landmark or args.destination or args.target or args.place
		if type(target) == "string" and target ~= "" then
			local lm = mod.get_landmark(clean_text(target, 40))
			if lm and lm.x then return {type = "guard", landmark = lm.name} end
			return {type = "none"}
		end
		return {type = "guard"}   -- no landmark named: guard the current spot
	elseif action_type == "patrol" then
		local raw_list = args.landmarks or args.route or args.places
		local names = {}
		if type(raw_list) == "table" then
			for _, v in ipairs(raw_list) do
				local lm = type(v) == "string" and mod.get_landmark(clean_text(v, 40))
				if lm and lm.x then names[#names + 1] = lm.name end
			end
		end
		if #names >= 2 then return {type = "patrol", landmarks = names} end
	elseif action_type == "deliver" or action_type == "bring" or action_type == "take" then
		local dest = args.destination or args.landmark or args.target or args.to
		dest = type(dest) == "string" and clean_text(dest, 40) or ""
		local low = dest:lower()
		if dest == "" or low == "player" or low == "me" or low == "you" then
			return {type = "deliver", destination = "player"}
		end
		local lm = mod.get_landmark(dest)
		if lm and lm.x then return {type = "deliver", landmark = lm.name} end
		return {type = "deliver", destination = "player"}   -- unknown place: default to the player
	elseif action_type == "teleport" or action_type == "tp" or action_type == "blink" or action_type == "warp" then
		local dest = args.destination or args.landmark or args.target or args.to or args.place
		dest = type(dest) == "string" and clean_text(dest, 40) or ""
		local low = dest:lower()
		if dest == "" or low == "player" or low == "me" or low == "you" then
			return {type = "teleport", destination = "player"}
		end
		local lm = mod.get_landmark(dest)
		if lm and lm.x then return {type = "teleport", landmark = lm.name} end
		return {type = "teleport", destination = "player"}   -- unknown place: default to the player
	end
	return {type = "none"}
end

function mod.normalise_response(raw, fallback_name, limits)
	limits = limits or mod.limits
	if type(raw) ~= "table" then return nil, "response is not a JSON object" end
	if type(raw.response) == "table" then raw = raw.response end
	local speech = clean_text(raw.speech or raw.message or raw.output_text, limits.speech_length)
	if speech == "" then
		speech = (fallback_name or "The villager") .. " nods."
	end
	return {speech = speech, action = mod.normalise_action(raw.action, limits)}
end

function mod.allowed_actions(limits)
	limits = limits or mod.limits
	local actions = {
		{type = "none"},
		{type = "follow"},
		{type = "stay"},
		{type = "come"},
		{type = "gather", resources = {"wood", "stone", "dirt", "sand"}, max_count = limits.gather_count},
		{type = "build", blueprints = {"wall", "shelter"}},
		{type = "buildhome"},   -- walk home and raise a small house there
	}
	-- Landmark-based actions only exist when there are landmarks to target, so the
	-- model can never pick an impossible destination.
	local names = mod.landmark_names and mod.landmark_names() or {}
	if #names >= 1 then
		actions[#actions + 1] = {type = "goto", landmarks = names}
		actions[#actions + 1] = {type = "guard", landmarks = names}
	end
	if #names >= 2 then
		actions[#actions + 1] = {type = "patrol", landmarks = names}
	end
	local destinations = {"player"}
	for _, n in ipairs(names) do destinations[#destinations + 1] = n end
	actions[#actions + 1] = {type = "deliver", destinations = destinations}
	actions[#actions + 1] = {type = "teleport", destinations = destinations}
	return actions
end

local function contains(text, pattern)
	return text:find("%f[%a]" .. pattern .. "%f[%A]") ~= nil
end

-- Longest known landmark name mentioned in the text, or nil.
local function find_landmark_in_text(text)
	local best
	for _, lname in ipairs(mod.landmark_names and mod.landmark_names() or {}) do
		local needle = lname:lower()
		if text:find(needle, 1, true) and (not best or #needle > #best:lower()) then
			best = lname
		end
	end
	return best
end

function mod.offline_response(message, identity, limits)
	limits = limits or mod.limits
	local text = clean_text(message, limits.message_length):lower()
	local name = identity.name or "I"
	if contains(text, "follow") then
		return {speech = "All right, I will follow you.", action = {type = "follow"}}
	elseif contains(text, "stay") or contains(text, "wait") or contains(text, "stop") then
		return {speech = "I will wait here.", action = {type = "stay"}}
	elseif contains(text, "patrol") then
		local names = {}
		for _, lname in ipairs(mod.landmark_names and mod.landmark_names() or {}) do
			if text:find(lname:lower(), 1, true) then names[#names + 1] = lname end
		end
		local action = mod.normalise_action({type = "patrol", landmarks = names}, limits)
		if action.type == "patrol" then
			return {speech = "I'll patrol between them.", action = action}
		end
		return {speech = "Name two landmarks I know and I'll patrol between them.", action = {type = "none"}}
	elseif contains(text, "guard") or contains(text, "defend") then
		local lm = find_landmark_in_text(text)
		local action = mod.normalise_action({type = "guard", landmark = lm}, limits)
		if action.type == "guard" then
			return {speech = lm and ("I'll guard " .. lm .. ".") or "I'll guard this spot.", action = action}
		end
		return {speech = "I'll keep watch right here.", action = {type = "stay"}}
	elseif contains(text, "deliver") or contains(text, "bring") or
		((contains(text, "take") or contains(text, "drop")) and contains(text, "to")) then
		local lm = find_landmark_in_text(text)
		if lm and not (contains(text, "me") or contains(text, "here")) then
			return {speech = "I'll take these to " .. lm .. ".",
				action = mod.normalise_action({type = "deliver", landmark = lm}, limits)}
		end
		return {speech = "I'll bring these to you.", action = {type = "deliver", destination = "player"}}
	elseif contains(text, "teleport") or contains(text, "blink") or contains(text, "warp") then
		local lm = find_landmark_in_text(text)
		if lm and not (contains(text, "me") or contains(text, "here")) then
			return {speech = "Blinking over to " .. lm .. ".",
				action = mod.normalise_action({type = "teleport", landmark = lm}, limits)}
		end
		return {speech = "Blinking to you.", action = {type = "teleport", destination = "player"}}
	elseif contains(text, "come") then
		return {speech = "Coming over now.", action = {type = "come"}}
	elseif (contains(text, "go") or contains(text, "goto") or contains(text, "head") or contains(text, "walk")) and find_landmark_in_text(text) then
		local lm = find_landmark_in_text(text)
		local action = mod.normalise_action({type = "goto", landmark = lm}, limits)
		if action.type == "goto" then
			return {speech = "On my way to " .. lm .. ".", action = action}
		end
	elseif contains(text, "gather") or contains(text, "collect") or contains(text, "fetch") or contains(text, "mine") or contains(text, "chop") then
		local resource
		for word in text:gmatch("[%a]+") do
			resource = canonical_resource(word) or resource
		end
		if resource then
			local count = tonumber(text:match("(%d+)")) or 1
			local action = mod.normalise_action({type = "gather", resource = resource, count = count}, limits)
			return {speech = "I will gather " .. action.count .. " " .. resource .. " for you.", action = action}
		end
		return {speech = "Tell me whether you need wood, stone, dirt, or sand.", action = {type = "none"}}
	elseif contains(text, "build") or contains(text, "make") then
		if contains(text, "house") or contains(text, "home") then
			return {speech = "I'll head home and build a house.", action = {type = "buildhome"}}
		end
		local blueprint = contains(text, "shelter") and "shelter" or (contains(text, "wall") and "wall" or nil)
		if blueprint then
			return {speech = "I can build that " .. blueprint .. " using blocks from your inventory.", action = {type = "build", blueprint = blueprint}}
		end
		return {speech = "I know how to build a wall, a small shelter, or a house at my home.", action = {type = "none"}}
	end
	local extra = ""
	if mod.landmark_names and #mod.landmark_names() >= 1 then
		extra = " I can also head to, guard, patrol, or carry goods to the places you've named."
	end
	return {
		speech = "I am " .. name .. ". I can follow, stay, come, gather wood or stone, build a wall or shelter, or head home to build a house." .. extra,
		action = {type = "none"},
	}
end
