local mod = theocraft_villagers
-- Provided by init.lua: request_http_api() must be called from the mod's
-- top-level init scope or the engine denies it (returns nil here).
local http = mod.http

local function setting(name, default)
	local value = minetest.settings:get(name)
	if value == nil or value == "" then return default end
	return value
end

local function history_key(self, player_name)
	return "history:" .. minetest.sha1((self._id or "unknown") .. "\0" .. player_name)
end

function mod.get_history(self, player_name)
	local key = history_key(self, player_name)
	if not mod.histories[key] then
		local saved = mod.storage:get_string(key)
		local decoded = saved ~= "" and minetest.parse_json(saved) or nil
		mod.histories[key] = type(decoded) == "table" and decoded or {}
	end
	return mod.histories[key]
end

local function save_history(self, player_name, history)
	local encoded = minetest.write_json(history)
	if encoded then mod.storage:set_string(history_key(self, player_name), encoded) end
end

local function add_history(self, player_name, history, role, content, limits)
	limits = limits or mod.limits
	history[#history + 1] = {role = role, content = mod.clean_text(content, limits.speech_length)}
	while #history > limits.history_entries do table.remove(history, 1) end
	save_history(self, player_name, history)
end

local function fallback(self, player_name, message, identity, history, callback, reason, limits)
	local response = mod.offline_response(message, identity, limits)
	add_history(self, player_name, history, "villager", response.speech, limits)
	callback(response, "offline", reason)
end

function mod.ask_villager(self, player, message, callback)
	local limits = mod.resolve_limits(self)
	message = mod.clean_text(message, limits.message_length)
	local identity = mod.identity_snapshot(self)
	local player_name = player:get_player_name()
	local history = mod.get_history(self, player_name)
	add_history(self, player_name, history, "player", message, limits)

	local enabled = minetest.settings:get_bool("theocraft_llm_enabled", false)
	local endpoint = setting("theocraft_llm_endpoint", "")
	if not enabled or endpoint == "" or not http then
		return fallback(self, player_name, message, identity, history, callback,
			not http and "HTTP permission unavailable" or "gateway disabled", limits)
	end
	local is_https = endpoint:match("^https://") ~= nil
	if not is_https and not minetest.settings:get_bool("theocraft_llm_allow_insecure_http", false) then
		return fallback(self, player_name, message, identity, history, callback, "gateway URL must use HTTPS", limits)
	end

	local token = setting("theocraft_llm_access_token", ""):gsub("[\r\n]", "")
	local timeout = math.max(3, math.min(60,
		math.floor(tonumber(setting("theocraft_llm_timeout_seconds", "15")) or 15)))
	local headers = {"Content-Type: application/json", "Accept: application/json"}
	if token ~= "" then headers[#headers + 1] = "Authorization: Bearer " .. token end
	local body, json_error = minetest.write_json({
		version = 1,
		villager = identity,
		player = {name = player_name, position = vector.round(player:get_pos())},
		message = message,
		history = history,
		allowed_actions = mod.allowed_actions(limits),
		model = setting("theocraft_llm_model", ""),
		system_prompt = setting("theocraft_llm_system_prompt",
			"Be concise, friendly, and stay in character."),
	})
	if not body then return fallback(self, player_name, message, identity, history, callback, json_error, limits) end

	http.fetch({
		url = endpoint,
		method = "POST",
		data = body,
		timeout = timeout,
		extra_headers = headers,
		user_agent = "Theocraft/0.1",
		quiet = true,
	}, function(result)
		if not result.succeeded or result.code < 200 or result.code >= 300 then
			return fallback(self, player_name, message, identity, history, callback,
				"gateway request failed with HTTP " .. tostring(result.code or 0), limits)
		end
		local decoded, parse_error = minetest.parse_json(result.data, nil, true)
		local response, validation_error = mod.normalise_response(decoded, identity.name, limits)
		if not response then
			return fallback(self, player_name, message, identity, history, callback, parse_error or validation_error, limits)
		end
		-- Carry the optional TTS clip (base64 Ogg Vorbis) straight through; the
		-- game validates/plays it. History only stores the text.
		if type(decoded) == "table" and type(decoded.audio_b64) == "string" then
			response.audio_b64 = decoded.audio_b64
		end
		add_history(self, player_name, history, "villager", response.speech, limits)
		callback(response, "remote")
	end)
end
