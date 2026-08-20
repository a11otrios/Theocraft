local mod = theocraft_villagers

-- In-world "speech" for villagers: a floating text bubble above the head plus a
-- short pitched voice murmur when they reply. Both effects reuse assets already
-- shipped by VoxeLibre (the mobs_mc_villager.* sounds) and are pure Lua, so this
-- works on Android with no engine or gateway changes. Each is independently
-- toggleable via settings.

local BUBBLE_ENTITY = "theocraft_villagers:speech_bubble"
local WRAP_WIDTH = 24      -- characters per bubble line before wrapping
local MAX_LINES = 4        -- cap bubble height; excess is truncated with an ellipsis
local BUBBLE_MAX_LIFE = 10 -- absolute safety lifetime (seconds) if the parent vanishes

-- Small deterministic hash, matching the style used in identity.lua so a
-- villager's voice stays stable across sessions (keyed on its persistent UUID).
local function stable_number(value)
	local total = 0
	value = tostring(value or "")
	for i = 1, #value do
		total = (total * 33 + value:byte(i)) % 2147483647
	end
	return total
end

local function bool_setting(name)
	-- Default ON: both effects are enabled unless the player turns them off.
	return minetest.settings:get_bool(name, true)
end

-- Wrap plain text to a few short lines for the nametag bubble. Nametags render
-- on a single line unless we insert the newlines ourselves.
local function wrap_text(text)
	text = tostring(text or ""):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
	if text == "" then return "" end
	local lines, line = {}, ""
	for word in text:gmatch("%S+") do
		if line == "" then
			line = word
		elseif #line + 1 + #word <= WRAP_WIDTH then
			line = line .. " " .. word
		else
			lines[#lines + 1] = line
			line = word
			if #lines >= MAX_LINES then break end
		end
	end
	if #lines < MAX_LINES and line ~= "" then
		lines[#lines + 1] = line
	elseif #lines >= MAX_LINES then
		-- Ran out of room: mark the last kept line as truncated.
		lines[MAX_LINES] = lines[MAX_LINES] .. "\226\128\166" -- "…" (UTF-8, LuaJIT-safe)
	end
	return table.concat(lines, "\n")
end

-- A camera-facing text label attached above a villager's head. Invisible sprite;
-- only its nametag is seen. Never saved to the world (static_save = false).
minetest.register_entity(BUBBLE_ENTITY, {
	initial_properties = {
		visual = "sprite",
		visual_size = {x = 0.1, y = 0.1},
		-- "blank.png" is a built-in Luanti texture (a 1x1 transparent pixel), so
		-- the sprite is invisible and only the nametag shows. Avoids shipping our
		-- own tiny PNG.
		textures = {"blank.png"},
		physical = false,
		pointable = false,
		collide_with_objects = false,
		static_save = false,
		nametag = "",
		nametag_color = "#ffffff",
	},
	on_activate = function(self)
		self.timer = 0
		self.life = BUBBLE_MAX_LIFE
	end,
	on_step = function(self, dtime)
		self.timer = self.timer + dtime
		if self.timer >= (self.life or BUBBLE_MAX_LIFE) then
			self.object:remove()
		end
	end,
})

local function remove_bubble(villager)
	local bubble = villager._theocraft_bubble
	if bubble and bubble:get_luaentity() then
		bubble:remove()
	end
	villager._theocraft_bubble = nil
end

local function show_bubble(villager, text)
	local wrapped = wrap_text(text)
	if wrapped == "" then return end
	local pos = villager.object and villager.object:get_pos()
	if not pos then return end

	remove_bubble(villager)

	local bubble = minetest.add_entity(pos, BUBBLE_ENTITY)
	if not bubble then return end
	-- Offset is in the villager's local attach space (~1/10 node units); y ~= 19
	-- floats it just above the head. May need a small tune per model.
	bubble:set_attach(villager.object, "", {x = 0, y = 19, z = 0}, {x = 0, y = 0, z = 0})
	bubble:set_properties({nametag = wrapped})

	local entity = bubble:get_luaentity()
	if entity then
		-- Keep the bubble up long enough to read; scales with length.
		local words = select(2, wrapped:gsub("%S+", ""))
		entity.life = math.max(2, math.min(8, 2 + words * 0.35))
	end
	villager._theocraft_bubble = bubble
end

local function play_voice(villager, text)
	local obj = villager.object
	if not obj or not obj:get_pos() then return end
	local words = select(2, tostring(text or ""):gsub("%S+", ""))
	local blips = math.max(1, math.min(4, words))
	-- Stable base pitch per villager (0.80..1.39), keyed on its UUID.
	local pitch = 0.8 + (stable_number(villager._id) % 60) / 100
	for i = 0, blips - 1 do
		minetest.after(i * 0.15, function()
			if not obj or not obj:get_pos() then return end
			minetest.sound_play("mobs_mc_villager", {
				object = obj,
				pitch = pitch + (math.random() - 0.5) * 0.1,
				gain = 1.0,
				max_hear_distance = 16,
			}, true)
		end)
	end
end

-- Entry point: called with the finished reply text whenever a villager speaks
-- (both remote LLM and offline fallback replies flow through here).
function mod.villager_say(villager, text)
	if not villager or not villager.object then return end
	if bool_setting("theocraft_speech_bubbles") then
		show_bubble(villager, text)
	end
	if bool_setting("theocraft_speech_voice") then
		play_voice(villager, text)
	end
end
