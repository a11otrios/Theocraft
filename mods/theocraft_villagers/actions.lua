local mod = theocraft_villagers

local PATHFINDING = "gowp"
local gather_queries = {
	dirt = "group:soil",
	sand = "group:sand",
	stone = "group:stone",
	wood = "group:tree",
}
local build_materials = {
	"mcl_core:cobble",
	"mcl_core:stonebrick",
	"mcl_core:dirt",
}

local function now()
	return minetest.get_us_time() / 1000000
end

local function stop(self)
	self.state = "stand"
	self.order = "stand"
	self.waypoints = nil
	self.current_target = nil
	self._target = nil
	if self.object and self.object:get_pos() then
		self.object:set_velocity(vector.zero())
		self.object:set_acceleration(vector.zero())
	end
end

local function get_player(name)
	local player = name and minetest.get_player_by_name(name)
	if player and player:get_pos() then return player end
	return nil
end

local function is_matching_resource(node_name, resource)
	local query = gather_queries[resource]
	local group = query and query:match("^group:(.+)$")
	return group and minetest.get_item_group(node_name, group) > 0
end

local function add_drops(self, drops)
	self._theocraft_inventory = self._theocraft_inventory or {}
	for _, drop in ipairs(drops) do
		local stack = ItemStack(drop)
		if not stack:is_empty() then
			local item_name = stack:get_name()
			self._theocraft_inventory[item_name] =
				(self._theocraft_inventory[item_name] or 0) + stack:get_count()
		end
	end
end

local function finish_gather(self, target, player_name)
	local instruction = self._theocraft_instruction
	if not instruction or instruction.type ~= "gather" then return end
	local node = minetest.get_node_or_nil(target)
	if not node or not is_matching_resource(node.name, instruction.resource) then
		instruction.target = nil
		return
	end
	if minetest.is_protected(target, player_name) then
		instruction.target = nil
		return
	end

	add_drops(self, minetest.get_node_drops(node.name, ""))
	minetest.remove_node(target)
	instruction.target = nil
	instruction.remaining = instruction.remaining - 1
	instruction.next_at = now() + 0.5
	if instruction.remaining <= 0 then
		self._theocraft_instruction = {type = "stay", player = player_name}
		minetest.chat_send_player(player_name,
			self._theocraft_name .. " finished gathering. Talk to them to collect the items.")
	end
end

local function nearest_resource(origin, resource, player_name)
	local radius = 12
	local minimum = vector.offset(origin, -radius, -6, -radius)
	local maximum = vector.offset(origin, radius, 6, radius)
	local nodes = minetest.find_nodes_in_area(minimum, maximum, {gather_queries[resource]})
	local best, best_distance
	for _, pos in ipairs(nodes) do
		if not minetest.is_protected(pos, player_name) then
			local distance = vector.distance(origin, pos)
			if not best_distance or distance < best_distance then
				best, best_distance = pos, distance
			end
		end
	end
	return best
end

local function process_follow(self, instruction, player)
	local pos = self.object:get_pos()
	local player_pos = player:get_pos()
	local distance = vector.distance(pos, player_pos)
	if distance > 32 then
		self._theocraft_instruction = nil
		stop(self)
		minetest.chat_send_player(player:get_player_name(), self._theocraft_name .. " lost sight of you.")
		return
	elseif distance <= 2.4 then
		if not instruction.waiting_near_player then stop(self) end
		instruction.waiting_near_player = true
		return
	end
	instruction.waiting_near_player = nil

	if now() < (instruction.next_at or 0) then return end
	local moved = instruction.last_target and vector.distance(instruction.last_target, player_pos) or math.huge
	if self.state == PATHFINDING and moved < 3 then return end
	if self.state == PATHFINDING then stop(self) end
	instruction.last_target = vector.round(player_pos)
	instruction.next_at = now() + 1.5
	self:gopath(player_pos, nil, true)
end

local function process_come(self, instruction, player)
	if self.state == PATHFINDING then return end
	if now() < (instruction.next_at or 0) then return end
	instruction.next_at = now() + 3
	local player_name = player:get_player_name()
	local arrived = function(entity)
		entity._theocraft_instruction = {type = "stay", player = player_name}
	end
	if not self:gopath(player:get_pos(), arrived, true) then
		instruction.next_at = now() + 2
	end
end

local function process_gather(self, instruction, player)
	if instruction.remaining <= 0 then
		self._theocraft_instruction = {type = "stay", player = player:get_player_name()}
		return
	end
	if self.state == PATHFINDING then return end
	if now() < (instruction.next_at or 0) then return end

	local target = instruction.target
	if not target or not is_matching_resource(minetest.get_node(target).name, instruction.resource) then
		target = nearest_resource(self.object:get_pos(), instruction.resource, player:get_player_name())
		instruction.target = target
	end
	if not target then
		instruction.next_at = now() + 4
		minetest.chat_send_player(player:get_player_name(),
			self._theocraft_name .. " cannot find nearby " .. instruction.resource .. ".")
		self._theocraft_instruction = {type = "stay", player = player:get_player_name()}
		return
	end

	local captured_target = vector.new(target)
	local player_name = player:get_player_name()
	instruction.next_at = now() + 2
	if not self:gopath(target, function(entity)
		finish_gather(entity, captured_target, player_name)
	end, true) then
		instruction.target = nil
	end
end

local function horizontal_basis(player)
	local direction = player:get_look_dir()
	local forward
	if math.abs(direction.x) > math.abs(direction.z) then
		forward = {x = direction.x >= 0 and 1 or -1, y = 0, z = 0}
	else
		forward = {x = 0, y = 0, z = direction.z >= 0 and 1 or -1}
	end
	return forward, {x = -forward.z, y = 0, z = forward.x}
end

local function blueprint_positions(player, blueprint)
	local player_pos = player:get_pos()
	local forward, side = horizontal_basis(player)
	local base = vector.add(vector.round(player_pos), vector.multiply(forward, 3))
	local positions = {}
	if blueprint == "wall" then
		for y = 0, 2 do
			for x = -2, 2 do
				positions[#positions + 1] = vector.add(base, vector.add(vector.multiply(side, x), {x = 0, y = y, z = 0}))
			end
		end
	elseif blueprint == "shelter" then
		for y = 0, 2 do
			for x = -1, 1 do
				for z = -1, 1 do
					local edge = math.abs(x) == 1 or math.abs(z) == 1
					local doorway = z == -1 and x == 0 and y < 2
					if edge and not doorway then
						positions[#positions + 1] = vector.add(base,
							vector.add(vector.multiply(side, x), vector.add(vector.multiply(forward, z), {x = 0, y = y, z = 0})))
					end
				end
			end
		end
		for x = -1, 1 do
			for z = -1, 1 do
				positions[#positions + 1] = vector.add(base,
					vector.add(vector.multiply(side, x), vector.add(vector.multiply(forward, z), {x = 0, y = 3, z = 0})))
			end
		end
	end
	return positions
end

local function choose_material(inventory, count, player_name)
	if minetest.is_creative_enabled(player_name) then return build_materials[1], true end
	for _, item_name in ipairs(build_materials) do
		if inventory:contains_item("main", ItemStack(item_name .. " " .. count)) then
			return item_name, false
		end
	end
	return nil, false
end

local function build(player, blueprint)
	local player_name = player:get_player_name()
	local positions = blueprint_positions(player, blueprint)
	if #positions == 0 or #positions > 64 then return false, "That blueprint is unavailable." end
	for _, pos in ipairs(positions) do
		local node = minetest.get_node_or_nil(pos)
		local def = node and minetest.registered_nodes[node.name]
		if not node or (node.name ~= "air" and not (def and def.buildable_to)) then
			return false, "The build area must be clear."
		end
		if minetest.is_protected(pos, player_name) then
			return false, "That area is protected."
		end
	end

	local inventory = player:get_inventory()
	local material, creative = choose_material(inventory, #positions, player_name)
	if not material then
		return false, "You need " .. #positions .. " matching cobblestone, stone-brick, or dirt blocks."
	end
	if not creative then
		inventory:remove_item("main", ItemStack(material .. " " .. #positions))
	end
	for _, pos in ipairs(positions) do
		minetest.set_node(pos, {name = material})
	end
	return true, "Built a " .. blueprint .. " using " .. #positions .. " blocks."
end

function mod.apply_action(self, player, action)
	action = mod.normalise_action(action)
	local player_name = player:get_player_name()
	if action.type == "none" then return {ok = true} end
	if action.type == "follow" then
		self._theocraft_instruction = {type = "follow", player = player_name, next_at = 0}
		stop(self)
	elseif action.type == "stay" then
		self._theocraft_instruction = {type = "stay", player = player_name}
		stop(self)
	elseif action.type == "come" then
		self._theocraft_instruction = {type = "come", player = player_name, next_at = 0}
		stop(self)
	elseif action.type == "gather" then
		self._theocraft_instruction = {
			type = "gather",
			player = player_name,
			resource = action.resource,
			remaining = action.count,
			next_at = 0,
		}
		stop(self)
	elseif action.type == "build" then
		local ok, message = build(player, action.blueprint)
		return {ok = ok, message = message}
	end
	return {ok = true}
end

function mod.tick_action(self)
	local instruction = self._theocraft_instruction
	if not instruction then return false end
	if instruction.type == "stay" then
		if not instruction.stopped then
			stop(self)
			instruction.stopped = true
		end
		return true
	end
	local player = get_player(instruction.player)
	if not player then
		self._theocraft_instruction = nil
		stop(self)
		return false
	end
	if instruction.type == "follow" then
		process_follow(self, instruction, player)
	elseif instruction.type == "come" then
		process_come(self, instruction, player)
	elseif instruction.type == "gather" then
		process_gather(self, instruction, player)
	else
		self._theocraft_instruction = nil
		return false
	end
	return true
end

function mod.inventory_summary(self)
	local lines = {}
	for item_name, count in pairs(self._theocraft_inventory or {}) do
		if count > 0 then
			local def = minetest.registered_items[item_name]
			lines[#lines + 1] = (def and def.description or item_name) .. " x" .. count
		end
	end
	table.sort(lines)
	return #lines > 0 and table.concat(lines, ", ") or "Nothing collected"
end

function mod.take_inventory(self, player)
	local inventory = player:get_inventory()
	local remaining = {}
	for item_name, count in pairs(self._theocraft_inventory or {}) do
		local leftover = inventory:add_item("main", ItemStack(item_name .. " " .. count))
		if not leftover:is_empty() then remaining[item_name] = leftover:get_count() end
	end
	self._theocraft_inventory = remaining
end
