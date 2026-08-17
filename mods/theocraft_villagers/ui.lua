local mod = theocraft_villagers
local FORMNAME = "theocraft_villagers:conversation"

local function session_entity(player_name)
	local session = mod.sessions[player_name]
	if not session or not session.object then return nil end
	local pos = session.object:get_pos()
	local entity = pos and session.object:get_luaentity()
	if not entity or entity.name ~= "mobs_mc:villager" or entity._id ~= session.id then return nil end
	return entity
end

local function history_text(self, player_name)
	local lines = {}
	local history = mod.get_history(self, player_name)
	local first = math.max(1, #history - 7)
	for index = first, #history do
		local entry = history[index]
		local speaker = entry.role == "player" and player_name or self._theocraft_name
		lines[#lines + 1] = speaker .. ": " .. entry.content
	end
	return table.concat(lines, "\n\n")
end

function mod.show_conversation(player_name, status)
	local self = session_entity(player_name)
	if not self then
		mod.sessions[player_name] = nil
		return
	end
	mod.ensure_identity(self)
	local status_text = status and ("Status: " .. status) or ""
	local formspec = table.concat({
		"formspec_version[4]",
		"size[12,9]",
		"label[0.55,0.45;", minetest.formspec_escape(self._theocraft_name), "]",
		"textarea[0.5,0.75;11,1.35;;;", minetest.formspec_escape(self._theocraft_bio), "]",
		"textarea[0.5,2.05;11,3.65;history;;", minetest.formspec_escape(history_text(self, player_name)), "]",
		"label[0.55,5.85;", minetest.formspec_escape("Carrying: " .. mod.inventory_summary(self)), "]",
		"field[0.55,6.45;8.1,0.9;message;Say something or give an instruction;]",
		"field_close_on_enter[message;false]",
		"field_enter_after_edit[message;true]",
		"set_focus[message;true]",
		"button[8.8,6.35;2.65,0.85;send;Send]",
		"button[0.55,7.45;2.4,0.8;trade;Trade]",
		"button[3.15,7.45;2.4,0.8;take;Take items]",
		"button_exit[9.05,7.45;2.4,0.8;close;Close]",
		"label[0.55,8.45;", minetest.formspec_escape(status_text), "]",
	})
	minetest.show_formspec(player_name, FORMNAME, formspec)
end

function mod.start_conversation(self, player)
	local player_name = player:get_player_name()
	local villager_pos = self.object:get_pos()
	if not villager_pos or vector.distance(villager_pos, player:get_pos()) > mod.limits.interaction_distance then return end
	mod.ensure_identity(self)
	mod.sessions[player_name] = {object = self.object, id = self._id, original_rightclick = mod.original_rightclick}
	mod.show_conversation(player_name)
end

local function send_message(player, self, fields)
	local player_name = player:get_player_name()
	local message = mod.clean_text(fields.message, mod.limits.message_length)
	if message == "" then return mod.show_conversation(player_name, "Type a message first.") end
	if mod.pending[player_name] then return mod.show_conversation(player_name, "Still waiting for a reply...") end
	mod.pending[player_name] = true
	mod.show_conversation(player_name, self._theocraft_name .. " is thinking...")
	mod.ask_villager(self, player, message, function(response, source, warning)
		mod.pending[player_name] = nil
		local current = session_entity(player_name)
		local current_player = minetest.get_player_by_name(player_name)
		if not current or not current_player then return end
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
	if vector.distance(player:get_pos(), self.object:get_pos()) > mod.limits.interaction_distance then
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
	elseif fields.trade then
		mod.sessions[player_name] = nil
		if mod.original_rightclick then mod.original_rightclick(self, player) end
	end
	return true
end)

minetest.register_on_leaveplayer(function(player)
	local player_name = player:get_player_name()
	mod.sessions[player_name] = nil
	mod.pending[player_name] = nil
end)
