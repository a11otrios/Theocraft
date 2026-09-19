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
