-- Theocraft Circus Pack: cheerful, child-friendly circus play.
-- No explosives, weapons, scary mobs, caves, portals, or damage.
-- Blocks/items/props are colourful and forgiving; falls near circus
-- builds become soft landings with applause instead of punishment.
theocraft_circus = {
	modname = minetest.get_current_modname(),
	modpath = minetest.get_modpath(minetest.get_current_modname()),
	storage = minetest.get_mod_storage(),
	scores = {},
	music_handles = {},
	hoop_progress = {},
	juggle_progress = {},
	balance_state = {},
}

local mod = theocraft_circus
local modpath = mod.modpath

function mod.is_theo_mode()
	return minetest.settings:get_bool("theocraft_circus_theo_mode", true)
end

function mod.fall_protect_enabled()
	if not mod.is_theo_mode() then return false end
	return minetest.settings:get_bool("theocraft_circus_fall_protect", true)
end

function mod.area_radius()
	local r = tonumber(minetest.settings:get("theocraft_circus_area_radius")) or 14
	if r < 4 then r = 4 end
	if r > 48 then r = 48 end
	return r
end

function mod.confetti_enabled()
	return minetest.settings:get_bool("theocraft_circus_confetti", true)
end

local CHEERS = {
	"Amazing balance!",
	"Brilliant jump!",
	"The crowd goes wild!",
	"Fantastic circus trick!",
	"Theo's show is starting!",
	"Wonderful performing!",
	"Beautiful circus style!",
	"Bravo! Encore!",
}

function mod.cheer(player_name)
	if not mod.is_theo_mode() then return end
	if not player_name or player_name == "" then return end
	local line = CHEERS[math.random(#CHEERS)]
	minetest.chat_send_player(player_name, "[Circus] " .. line)
end

function mod.safe_sound(name, spec)
	if not name or name == "" then return nil end
	spec = spec or {}
	if not spec.pos then spec.pos = nil end
	local ok, handle = pcall(minetest.sound_play, name, spec, false)
	if ok then return handle end
	return nil
end

-- Harmless colourful sparkle burst. Never damages nodes or entities.
function mod.sparkle(pos, color)
	if not pos then return end
	if not mod.confetti_enabled() and color == "confetti" then return end
	local ok = pcall(function()
		if minetest.add_particlespawner then
			minetest.add_particlespawner({
				amount = 24,
				time = 0.6,
				minpos = {x = pos.x - 0.4, y = pos.y, z = pos.z - 0.4},
				maxpos = {x = pos.x + 0.4, y = pos.y + 0.8, z = pos.z + 0.4},
				minvel = {x = -1.5, y = 1.0, z = -1.5},
				maxvel = {x = 1.5, y = 3.0, z = 1.5},
				minexptime = 0.6,
				maxexptime = 1.4,
				minsize = 1.5,
				maxsize = 3.0,
				texture = "mcl_core_sugar.png^[colorize:#FF4FA3:200",
				glow = 10,
				collisiondetection = false,
			})
		else
			for _ = 1, 8 do
				minetest.add_particle({
					pos = pos,
					velocity = {x = math.random(-150, 150) / 100, y = math.random(100, 300) / 100, z = math.random(-150, 150) / 100},
					expirationtime = 1.0,
					size = 2.0,
					texture = "mcl_core_sugar.png^[colorize:#FFD23F:200",
					glow = 10,
				})
			end
		end
	end)
	if not ok then
		-- Particles are cosmetic; never let them break gameplay.
	end
end

function mod.confetti(pos)
	if not mod.confetti_enabled() then return end
	mod.sparkle({x = pos.x, y = pos.y + 1, z = pos.z}, "confetti")
	mod.safe_sound("mcl_note_block_pling", {pos = pos, gain = 0.5})
end

-- Monotonic elapsed-time source in microseconds. mod._now_us is an override
-- hook for deterministic testing; the game always uses the engine clock.
function mod.now_us()
	if mod._now_us then return mod._now_us() end
	if minetest.get_us_time then return minetest.get_us_time() end
	return math.floor((os.clock() or 0) * 1000000)
end

-- Juggling rhythm window: taps 0.25s-2.5s apart continue the combo,
-- anything faster or slower restarts it. Pure function over an explicit
-- state table so the rhythm is deterministic and unit-testable.
mod.JUGGLE_MIN_US = 250000
mod.JUGGLE_MAX_US = 2500000

function mod.juggle_tap(state, now_us)
	state = state or {last = 0, combo = 0, best = 0}
	local gap = now_us - (state.last or 0)
	if gap >= mod.JUGGLE_MIN_US and gap <= mod.JUGGLE_MAX_US then
		state.combo = (state.combo or 0) + 1
	else
		state.combo = 1
	end
	state.last = now_us
	if state.combo > (state.best or 0) then state.best = state.combo end
	return state.combo
end

-- Balancing-attempt tracker. Call once per polling pass with the real elapsed
-- seconds: returns "cheer" periodically, "medal" once per attempt after ~60s
-- of continuous balancing, and "reset" when the player steps off (which also
-- clears the state for the next attempt). Pure and unit-testable.
mod.BALANCE_MEDAL_SECONDS = 60

function mod.update_balance(state, on_apparatus, dt)
	state = state or {ticks = 0, time = 0, awarded = false}
	if not on_apparatus then
		local was_practising = (state.ticks or 0) > 0
		state.ticks = 0
		state.time = 0
		state.awarded = false
		return was_practising and "reset" or nil
	end
	state.ticks = (state.ticks or 0) + 1
	state.time = (state.time or 0) + (dt or 0)
	if state.time >= mod.BALANCE_MEDAL_SECONDS and not state.awarded then
		state.awarded = true
		return "medal"
	end
	if state.ticks % 12 == 0 then return "cheer" end
	return nil
end

-- Single shared music-box driver used by manual toggles, Show Mode, and dug
-- boxes alike. Starting sound, storing exactly one handle per box, and
-- stopping on switch-off are all handled here so the paths cannot diverge.
mod.MUSIC_BOX_SOUND = "mcl_note_block_pling"

function mod.stop_music_at(pos)
	if not pos then return end
	local key = minetest.pos_to_string(pos)
	local handle = mod.music_handles[key]
	if handle ~= nil then
		pcall(minetest.sound_stop, handle)
		mod.music_handles[key] = nil
	end
end

function mod.set_music_box(pos, enable)
	if not pos then return end
	-- Stop any previous sound first: an already-active box must never
	-- accumulate duplicate handles.
	mod.stop_music_at(pos)
	local node = minetest.get_node(pos)
	if not node then return end
	if enable then
		if node.name ~= "theocraft_circus:music_box_on" then
			minetest.swap_node(pos, {name = "theocraft_circus:music_box_on", param2 = node.param2})
		end
		local handle = mod.safe_sound(mod.MUSIC_BOX_SOUND, {pos = pos, gain = 0.5, loop = true})
		if handle then
			mod.music_handles[minetest.pos_to_string(pos)] = handle
		end
	else
		if node.name ~= "theocraft_circus:music_box_off" then
			minetest.swap_node(pos, {name = "theocraft_circus:music_box_off", param2 = node.param2})
		end
	end
end

local function load(name)
	dofile(modpath .. "/" .. name .. ".lua")
end

load("nodes")
load("items")
load("props")
load("crafts")
load("challenges")
load("arena")
load("mode")

minetest.log("action", "[theocraft_circus] Circus Pack loaded (cheerful, safe, non-scary)")
