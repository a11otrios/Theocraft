local mod = theocraft_villagers
local http = minetest.request_http_api()

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

local function add_history(self, player_name, history, role, content)
	history[#history + 1] = {role = role, content = mod.clean_text(content, mod.limits.speech_length)}
	while #history > mod.limits.history_entries do table.remove(history, 1) end
	save_history(self, player_name, history)
end

local function fallback(self, player_name, message, identity, history, callback, reason)
	local response = mod.offline_response(message, identity)
	add_history(self, player_name, history, "villager", response.speech)
	callback(response, "offline", reason)
end

function mod.ask_villager(self, player, message, callback)
	message = mod.clean_text(message, mod.limits.message_length)
	local identity = mod.identity_snapshot(self)
	local player_name = player:get_player_name()
	local history = mod.get_history(self, player_name)
	add_history(self, player_name, history, "player", message)

	local enabled = minetest.settings:get_bool("theocraft_llm_enabled", false)
	local endpoint = setting("theocraft_llm_endpoint", "")
	if not enabled or endpoint == "" or not http then
		return fallback(self, player_name, message, identity, history, callback,
			not http and "HTTP permission unavailable" or "gateway disabled")
	end
	local is_https = endpoint:match("^https://") ~= nil
	if not is_https and not minetest.settings:get_bool("theocraft_llm_allow_insecure_http", false) then
		return fallback(self, player_name, message, identity, history, callback, "gateway URL must use HTTPS")
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
		allowed_actions = mod.allowed_actions(),
		model = setting("theocraft_llm_model", ""),
		system_prompt = setting("theocraft_llm_system_prompt",
			"Be concise, friendly, and stay in character."),
	})
	if not body then return fallback(self, player_name, message, identity, history, callback, json_error) end

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
				"gateway request failed with HTTP " .. tostring(result.code or 0))
		end
		local decoded, parse_error = minetest.parse_json(result.data, nil, true)
		local response, validation_error = mod.normalise_response(decoded, identity.name)
		if not response then
			return fallback(self, player_name, message, identity, history, callback, parse_error or validation_error)
		end
		add_history(self, player_name, history, "villager", response.speech)
		callback(response, "remote")
	end)
end
