local mod = theocraft_villagers
local definition = minetest.registered_entities["mobs_mc:villager"]

if not definition then
	error("[theocraft_villagers] VoxeLibre villager entity is not registered")
end

mod.original_rightclick = definition.on_rightclick
local original_on_spawn = definition.on_spawn
local original_do_custom = definition.do_custom
local original_on_punch = definition.on_punch
local original_deal_damage = definition.deal_damage
local original_damage_mob = definition.damage_mob

-- VoxeLibre has separate paths for punches and environmental damage. Guard all
-- three entry points so the setting also covers fire, lava, falls, explosions,
-- projectiles, and damage applied directly by another mod.
function mod.villagers_invincible()
	return minetest.settings:get_bool("theocraft_villagers_invincible", false)
end

definition.on_punch = function(self, ...)
	if mod.villagers_invincible() then return end
	if original_on_punch then return original_on_punch(self, ...) end
end

definition.deal_damage = function(self, ...)
	if mod.villagers_invincible() then return end
	if original_deal_damage then return original_deal_damage(self, ...) end
end

definition.damage_mob = function(self, ...)
	if mod.villagers_invincible() then return end
	if original_damage_mob then return original_damage_mob(self, ...) end
end

definition.on_rightclick = function(self, clicker)
	if not clicker or not clicker:is_player() then return end
	mod.start_conversation(self, clicker)
end

definition.on_spawn = function(self)
	local result
	if original_on_spawn then result = original_on_spawn(self) end
	mod.ensure_identity(self)
	if self._theocraft_instruction then
		self._theocraft_instruction.next_at = 0
		self._theocraft_instruction.last_target = nil
		self._theocraft_instruction.stopped = nil
	end
	return result
end

definition.do_custom = function(self, dtime)
	mod.ensure_identity(self)
	if mod.tick_action(self) then return end   -- an explicit command owns this tick
	mod.tick_idle(self)                          -- may start an occasional stroll home
	if original_do_custom then return original_do_custom(self, dtime) end
end
