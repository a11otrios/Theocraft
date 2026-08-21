local mod = theocraft_villagers
local definition = minetest.registered_entities["mobs_mc:villager"]

if not definition then
	error("[theocraft_villagers] VoxeLibre villager entity is not registered")
end

mod.original_rightclick = definition.on_rightclick
local original_on_spawn = definition.on_spawn
local original_do_custom = definition.do_custom

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
