local mod = theocraft_villagers
local FORMNAME = "theocraft_villagers:conversation"
local LIMITS_FORMNAME = "theocraft_villagers:limits"

-- Order and labels for the per-villager Limits editor. Keys match mod.limits.
local LIMIT_FIELDS = {
	{key = "history_entries",     label = "Conversation memory (turns)"},
	{key = "message_length",      label = "Max player message length"},
	{key = "speech_length",       label = "Max villager reply length"},
	{key = "gather_count",        label = "Max gather count"},
	{key = "interaction_distance", label = "Interaction distance (blocks)"},
}

local function can_edit_limits(player_name)
	return minetest.check_player_privs(player_name, {server = true})
end

local function session_entity(player_name)
	local session = mod.sessions[player_name]
	if not session or not session.object then return nil end
	local pos = session.object:get_pos()
	local entity = pos and session.object:get_luaentity()
	if not entity or entity.name ~= "mobs_mc:villager" or entity._id ~= session.id then return nil end
	return entity
end

-- Rough chars-per-line for the history box, used only to size the scrollable
-- area. Slightly generous (few chars/line) so we over-estimate height and never
-- clip text; any extra is just reachable blank space below.
local HIST_WRAP = 40

-- Build the history newest-first so the latest reply is on top and visible the
-- moment the box opens, with older turns reachable by dragging the scrollbar.
-- Returns the text and an approximate wrapped-line count for sizing.
local function history_text(self, player_name)
	local history = mod.get_history(self, player_name)
	local lines, rows = {}, 0
	for index = #history, 1, -1 do
		local entry = history[index]
		local speaker = entry.role == "player" and player_name or self._theocraft_name
		local line = speaker .. ": " .. entry.content
		lines[#lines + 1] = line
		rows = rows + math.max(1, math.ceil(#line / HIST_WRAP))
	end
	return table.concat(lines, "\n"), rows
end

function mod.show_conversation(player_name, status)
	local self = session_entity(player_name)
	if not self then
		mod.sessions[player_name] = nil
		return
	end
	mod.ensure_identity(self)
	local status_text = status or ""
	local limits_button = can_edit_limits(player_name)
		and "button[4.15,4.55;1.9,0.6;limits;Limits]" or ""

	-- History in a scroll container so older turns are reachable, but anchored at
	-- the TOP showing the newest reply first. This avoids the old scroll-to-bottom
	-- math, which over-shot on mobile and parked the view in blank space. The
	-- content height is a generous estimate; over-estimating only leaves reachable
	-- blank below, never hides text.
	local hist, hist_rows = history_text(self, player_name)
	local hist_h = 2.9
	local content_h = math.max(hist_h, hist_rows * 0.5 + 0.2)
	local scroll_factor = math.max(0.0001, (content_h - hist_h) / 1000)

	local formspec = table.concat({
		"formspec_version[4]",
		"size[8.8,5.5]",
		-- Pin the box's bottom-centre to the screen's bottom-centre so it sits
		-- out of the way at the bottom instead of filling the middle.
		"position[0.5,1.0]",
		"anchor[0.5,1.0]",
		-- Flat, borderless history so the box reads thin, not chunky. The input
		-- field keeps its border so it's clearly tappable. textarea text defaults
		-- to white, which is invisible on VoxeLibre's light form background, so
		-- force a dark colour for the read-only history.
		"style_type[textarea;border=false;textcolor=#222222]",
		"label[0.25,0.3;", minetest.formspec_escape(self._theocraft_name), "]",
		"scrollbaroptions[max=1000;thumbsize=120]",
		"scroll_container[0.25,0.55;8.05,", tostring(hist_h), ";histbar;vertical;",
			tostring(scroll_factor), "]",
		-- Empty name = READ-ONLY display. With a name it becomes an editable
		-- field that hijacks the keyboard when tapped.
		"textarea[0,0;8.05,", tostring(content_h), ";;;", minetest.formspec_escape(hist), "]",
		"scroll_container_end[]",
		-- Start at value 0 = top = newest message (history is newest-first).
		"scrollbar[8.35,0.55;0.25,", tostring(hist_h), ";vertical;histbar;0]",
		"field[0.25,3.65;5.45,0.7;message;;]",
		"field_close_on_enter[message;false]",
		"field_enter_after_edit[message;true]",
		"set_focus[message;true]",
		"button[5.85,3.6;2.7,0.8;send;Send]",
		"button[0.25,4.55;1.9,0.6;trade;Trade]",
		"button[2.2,4.55;1.9,0.6;take;Take]",
		limits_button,
		"button_exit[6.45,4.55;1.9,0.6;close;Close]",
		status_text ~= "" and ("label[0.25,5.2;" .. minetest.formspec_escape(status_text) .. "]") or "",
	})
	minetest.show_formspec(player_name, FORMNAME, formspec)
end

function mod.show_limits(player_name, status)
	local self = session_entity(player_name)
	if not self then
		mod.sessions[player_name] = nil
		return
	end
	if not can_edit_limits(player_name) then
		return mod.show_conversation(player_name, "You need the server privilege to edit limits.")
	end
	local over = type(self._theocraft_limits) == "table" and self._theocraft_limits or {}
	local rows = {
		"formspec_version[4]",
		"size[11,9]",
		"label[0.55,0.5;", minetest.formspec_escape("Limits for " .. self._theocraft_name), "]",
		"label[0.55,1.05;", minetest.formspec_escape("Leave a field blank to inherit the global default."), "]",
	}
	local y = 1.7
	for _, item in ipairs(LIMIT_FIELDS) do
		local range = mod.limit_ranges[item.key]
		local hint = string.format("%s  (default %d, range %d-%d)",
			item.label, mod.limits[item.key], range[1], range[2])
		local value = over[item.key]
		rows[#rows + 1] = table.concat({
			"field[0.55,", y, ";9.9,0.8;", item.key, ";",
			minetest.formspec_escape(hint), ";",
			minetest.formspec_escape(value and tostring(value) or ""), "]",
		})
		y = y + 1.15
	end
	rows[#rows + 1] = table.concat({"button[0.55,", y, ";2.6,0.85;save;Save]"})
	rows[#rows + 1] = table.concat({"button[3.3,", y, ";2.6,0.85;back;Back]"})
	rows[#rows + 1] = table.concat({"button_exit[8.4,", y, ";2.05,0.85;close;Close]"})
	if status then
		rows[#rows + 1] = table.concat({"label[0.55,", y + 1.0, ";",
			minetest.formspec_escape(status), "]"})
	end
	minetest.show_formspec(player_name, LIMITS_FORMNAME, table.concat(rows))
end

function mod.start_conversation(self, player)
	local player_name = player:get_player_name()
	local villager_pos = self.object:get_pos()
	if not villager_pos or vector.distance(villager_pos, player:get_pos()) > mod.resolve_limits(self).interaction_distance then return end
	mod.ensure_identity(self)
	mod.sessions[player_name] = {object = self.object, id = self._id, original_rightclick = mod.original_rightclick}
	mod.show_conversation(player_name)
end

local function send_message(player, self, fields)
	local player_name = player:get_player_name()
	local message = mod.clean_text(fields.message, mod.resolve_limits(self).message_length)
	if message == "" then return mod.show_conversation(player_name, "Type a message first.") end
	if mod.pending[player_name] then return mod.show_conversation(player_name, "Still waiting for a reply...") end
	mod.pending[player_name] = true
	mod.show_conversation(player_name, self._theocraft_name .. " is thinking...")
	mod.ask_villager(self, player, message, function(response, source, warning)
		mod.pending[player_name] = nil
		local current = session_entity(player_name)
		local current_player = minetest.get_player_by_name(player_name)
		if not current or not current_player then return end
		mod.villager_say(current, response.speech)
		local result = mod.apply_action(current, current_player, response.action)
		local status = source == "remote" and "Remote LLM" or "Offline interpreter"
		if warning then status = status .. " (" .. mod.clean_text(warning, 100) .. ")" end
		if result.message then status = status .. ". " .. result.message end
		mod.show_conversation(player_name, status)
	end)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORMNAME then return false end
	local player_name = player:get_player_name()
	local self = session_entity(player_name)
	if not self then return true end
	if vector.distance(player:get_pos(), self.object:get_pos()) > mod.resolve_limits(self).interaction_distance then
		mod.sessions[player_name] = nil
		minetest.close_formspec(player_name, FORMNAME)
		return true
	end
	if fields.quit then
		mod.sessions[player_name] = nil
	elseif fields.send or fields.key_enter_field == "message" then
		send_message(player, self, fields)
	elseif fields.take then
		mod.take_inventory(self, player)
		mod.show_conversation(player_name, "Collected available items.")
	elseif fields.limits then
		if can_edit_limits(player_name) then
			mod.show_limits(player_name)
		else
			mod.show_conversation(player_name, "You need the server privilege to edit limits.")
		end
	elseif fields.trade then
		mod.sessions[player_name] = nil
		if mod.original_rightclick then mod.original_rightclick(self, player) end
	end
	return true
end)

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= LIMITS_FORMNAME then return false end
	local player_name = player:get_player_name()
	local self = session_entity(player_name)
	if not self then return true end
	if not can_edit_limits(player_name) then return true end
	if vector.distance(player:get_pos(), self.object:get_pos()) > mod.resolve_limits(self).interaction_distance then
		mod.sessions[player_name] = nil
		minetest.close_formspec(player_name, LIMITS_FORMNAME)
		return true
	end
	if fields.quit then
		mod.sessions[player_name] = nil
	elseif fields.back then
		mod.show_conversation(player_name)
	elseif fields.save then
		local overrides = {}
		local any = false
		for _, item in ipairs(LIMIT_FIELDS) do
			local raw = fields[item.key]
			if type(raw) == "string" and raw:match("%S") then
				local clamped = mod.clamp_limit(item.key, raw, nil)
				if clamped then
					overrides[item.key] = clamped
					any = true
				end
			end
		end
		self._theocraft_limits = any and overrides or nil
		mod.show_limits(player_name, any and "Saved." or "Saved. All fields inherit the global defaults.")
	end
	return true
end)

minetest.register_on_leaveplayer(function(player)
	local player_name = player:get_player_name()
	mod.sessions[player_name] = nil
	mod.pending[player_name] = nil
end)
