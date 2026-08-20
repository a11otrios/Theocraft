local mod = theocraft_villagers

-- Villager voice when they reply:
--   * real spoken audio when the gateway supplies a TTS clip (played positionally
--     from the villager via dynamic_add_media), or
--   * a pitched voice murmur (reusing VoxeLibre's mobs_mc_villager.* sounds) as a
--     fallback when there's no TTS clip (offline, or TTS disabled).
-- Pure Lua; the TTS path needs no engine changes, just the runtime-media API.
-- Toggle the whole thing off with the theocraft_speech_voice setting.

-- Small deterministic hash, matching the style used in identity.lua so a
-- villager's murmur pitch stays stable across sessions (keyed on its UUID).
local function stable_number(value)
	local total = 0
	value = tostring(value or "")
	for i = 1, #value do
		total = (total * 33 + value:byte(i)) % 2147483647
	end
	return total
end

local function voice_enabled()
	return minetest.settings:get_bool("theocraft_speech_voice", true)
end

-- Fallback "murmur": a short burst of VoxeLibre's villager idle sound, pitched
-- per villager, when the gateway didn't send real speech.
local function play_murmur(villager, text)
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

-- Real text-to-speech: the gateway sends the reply as a base64 Ogg Vorbis clip;
-- we hand the raw bytes to the engine at runtime with dynamic_add_media, then
-- play them positionally from the villager. Returns true if playback was started.
local tts_counter = 0

local function play_tts(villager, player_name, audio_b64)
	if type(audio_b64) ~= "string" or audio_b64 == "" then return false end
	if not (minetest.decode_base64 and minetest.dynamic_add_media) then return false end
	local data = minetest.decode_base64(audio_b64)
	if not data or data == "" then return false end
	local obj = villager.object
	if not obj or not obj:get_pos() then return false end

	tts_counter = tts_counter + 1
	local sound_name = "tc_tts_" .. tts_counter
	local ok = minetest.dynamic_add_media({
		filename = sound_name .. ".ogg",
		filedata = data,
		ephemeral = true,        -- one-shot; the engine forgets it after delivery
		to_player = player_name, -- only the listening player needs it
	}, function()
		-- Fires once the client has the media. Guard the villager still existing.
		if not obj or not obj:get_pos() then return end
		-- ephemeral sound: fire-and-forget, returns no handle (that's expected).
		minetest.sound_play(sound_name, {
			object = obj,
			gain = 1.0,
			max_hear_distance = 24,
		}, true)
	end)
	return ok ~= false
end

-- Entry point: called with the finished reply whenever a villager speaks (both
-- remote LLM and offline fallback replies flow through here). `player` is the
-- listening player (object or name); `audio_b64` is the optional TTS clip.
function mod.villager_say(villager, player, text, audio_b64)
	if not villager or not villager.object then return end
	if not voice_enabled() then return end
	local player_name = type(player) == "string" and player
		or (player and player.get_player_name and player:get_player_name())
	-- Prefer real speech when the gateway supplied it; otherwise fall back to the
	-- pitched murmur so villagers still make a sound offline.
	if not (player_name and play_tts(villager, player_name, audio_b64)) then
		play_murmur(villager, text)
	end
end
