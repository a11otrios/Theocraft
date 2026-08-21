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

-- ---------------------------------------------------------------------------
-- Landmark-based actions. All reuse self:gopath toward a fixed position, then
-- do something on arrival. Positions are captured on apply, so a landmark moving
-- later doesn't redirect a villager mid-journey.

local ARRIVE = 2.5   -- blocks: "close enough" to a landmark
-- The mob pathfinder (mcl_mobs PATHFINDING_SEARCH_DISTANCE) only searches a
-- 25-block square, so it can't reach a far landmark in one gopath call. We hop
-- toward distant targets in short legs that always stay inside that window.
local STEP = 18

-- Find a standing spot (air with solid ground under it) near column x,z, close
-- to y_hint. Returns nil if the area isn't loaded or has no footing.
local function ground_near(x, z, y_hint)
	for dy = 8, -8, -1 do
		local here = minetest.get_node({x = x, y = y_hint + dy, z = z})
		local below = minetest.get_node({x = x, y = y_hint + dy - 1, z = z})
		if here.name ~= "ignore" and below.name ~= "ignore" then
			local hdef = minetest.registered_nodes[here.name]
			local bdef = minetest.registered_nodes[below.name]
			if hdef and bdef and hdef.walkable == false and bdef.walkable == true then
				return {x = x, y = y_hint + dy, z = z}
			end
		end
	end
	return nil
end

-- A reachable sub-target on the way to dest: dest itself when close, otherwise a
-- point ~STEP blocks along the line to it, dropped onto local ground.
local function step_target(pos, dest)
	if vector.distance(pos, dest) <= STEP then return dest end
	local dir = vector.direction(pos, dest)
	local mid = vector.add(pos, vector.multiply(dir, STEP))
	local x, z = math.floor(mid.x + 0.5), math.floor(mid.z + 0.5)
	return ground_near(x, z, math.floor(pos.y + 0.5)) or {x = x, y = pos.y, z = z}
end

-- Take one leg of the journey toward dest. Returns whether a path was started.
local function walk_to(self, dest)
	return self:gopath(step_target(self.object:get_pos(), dest), nil, true) ~= false
end

local function process_goto(self, instruction)
	if not instruction.pos then
		self._theocraft_instruction = {type = "stay", player = instruction.player}
		return
	end
	local pos = self.object:get_pos()
	if vector.distance(pos, instruction.pos) <= ARRIVE then
		self._theocraft_instruction = {type = "stay", player = instruction.player}
		minetest.chat_send_player(instruction.player,
			self._theocraft_name .. " arrived at " .. (instruction.landmark or "the spot") .. ".")
		return
	end
	if self.state == PATHFINDING then return end
	if now() < (instruction.next_at or 0) then return end
	instruction.next_at = now() + 3
	if walk_to(self, instruction.pos) then
		instruction.fails = 0
	else
		instruction.next_at = now() + 2
		instruction.fails = (instruction.fails or 0) + 1
		if instruction.fails >= 6 then   -- genuinely stuck: stop nagging the pathfinder
			minetest.chat_send_player(instruction.player,
				self._theocraft_name .. " can't find a way to " .. (instruction.landmark or "there") .. ".")
			self._theocraft_instruction = {type = "stay", player = instruction.player}
		end
	end
end

local function process_patrol(self, instruction)
	local points = instruction.points
	if not points or #points < 2 then
		self._theocraft_instruction = {type = "stay", player = instruction.player}
		return
	end
	local idx = instruction.index or 1
	local target = points[idx]
	local pos = self.object:get_pos()
	if vector.distance(pos, target) <= ARRIVE then
		if self.state == PATHFINDING then stop(self) end
		instruction.index = (idx % #points) + 1   -- advance, wrapping to the start
		instruction.next_at = now() + 3            -- brief pause at each stop
		return
	end
	if self.state == PATHFINDING then return end
	if now() < (instruction.next_at or 0) then return end
	instruction.next_at = now() + 4
	if not walk_to(self, target) then
		instruction.next_at = now() + 2
	end
end

local function process_guard(self, instruction)
	local pos = self.object:get_pos()
	if not instruction.pos then
		instruction.pos = vector.round(pos)   -- no landmark: guard where we stand
	end
	local distance = vector.distance(pos, instruction.pos)
	if distance <= ARRIVE then
		if self.state ~= "stand" then stop(self) end
		return
	end
	if distance > 4 then
		if self.state == PATHFINDING then return end
		if now() < (instruction.next_at or 0) then return end
		instruction.next_at = now() + 3
		walk_to(self, instruction.pos)
	end
end

-- Empty the villager's carried items into a container within reach of `near_pos`.
local function deposit_to_chest(self, near_pos, player_name)
	local chest = minetest.find_node_near(near_pos, 3, {"group:container"})
	if not chest or minetest.is_protected(chest, player_name) then return false end
	local inv = minetest.get_meta(chest):get_inventory()
	if not inv or not inv:get_list("main") then return false end
	local remaining, moved = {}, false
	for item_name, count in pairs(self._theocraft_inventory or {}) do
		local leftover = inv:add_item("main", ItemStack(item_name .. " " .. count))
		if leftover:get_count() < count then moved = true end
		if not leftover:is_empty() then remaining[item_name] = leftover:get_count() end
	end
	self._theocraft_inventory = remaining
	return moved
end

local function process_deliver(self, instruction, player)
	local pos = self.object:get_pos()
	local target = instruction.to_player and player:get_pos() or instruction.pos
	if not target then
		self._theocraft_instruction = {type = "stay", player = instruction.player}
		return
	end
	local player_name = player:get_player_name()
	local reach = instruction.to_player and 2.5 or 3
	if vector.distance(pos, target) <= reach then
		if instruction.to_player then
			mod.take_inventory(self, player)
			minetest.chat_send_player(player_name, self._theocraft_name .. " handed you what they carried.")
		elseif deposit_to_chest(self, instruction.pos, player_name) then
			minetest.chat_send_player(player_name,
				self._theocraft_name .. " stashed the goods at " .. (instruction.landmark or "the spot") .. ".")
		else
			minetest.chat_send_player(player_name,
				self._theocraft_name .. " reached " .. (instruction.landmark or "the spot") .. ", but found no chest to fill.")
		end
		self._theocraft_instruction = {type = "stay", player = player_name}
		return
	end
	if self.state == PATHFINDING then
		if not instruction.to_player then return end
		-- following a moving player: only re-path once they've drifted
		local moved = instruction.last and vector.distance(instruction.last, target) or math.huge
		if moved < 3 then return end
		stop(self)
	end
	if now() < (instruction.next_at or 0) then return end
	instruction.next_at = now() + 2
	instruction.last = vector.round(target)
	if not self:gopath(target, nil, true) then
		instruction.next_at = now() + 2
	end
end

-- Autonomous homeward stroll: paths toward a point, then clears itself so the
-- villager returns to vanilla wandering. Never ends in "stay".
local function process_roam(self, instruction)
	local pos = self.object:get_pos()
	if not instruction.pos or vector.distance(pos, instruction.pos) <= ARRIVE then
		self._theocraft_instruction = nil
		stop(self)
		return
	end
	if self.state == PATHFINDING then return end
	if now() < (instruction.next_at or 0) then return end
	instruction.attempts = (instruction.attempts or 0) + 1
	if instruction.attempts > 3 then       -- unreachable: give up quietly
		self._theocraft_instruction = nil
		return
	end
	instruction.next_at = now() + 3
	if not self:gopath(instruction.pos, function(entity)
		if entity._theocraft_instruction and entity._theocraft_instruction.type == "roam" then
			entity._theocraft_instruction = nil
		end
	end, false) then
		self._theocraft_instruction = nil
	end
end

-- ---------------------------------------------------------------------------
-- Home house-building. Unlike `build` (instant, in front of the player, from the
-- player's inventory) this walks the villager to its own home, finds a clear
-- footprint there (or on a nearby ring if home is occupied), and raises a small
-- house for free.

-- Where a villager drifts back to when idle: its own home if set (via
-- /tcsethome), otherwise the shared village landmark.
local function idle_home(self)
	local home = self._theocraft_home
	if type(home) == "table" then
		if home.landmark then
			local lm = mod.get_landmark(home.landmark)
			if lm and lm.x then return lm end
		elseif home.x then
			return home
		end
	end
	return mod.get_village and mod.get_village()
end

local HOUSE = {
	wall   = "mcl_core:sprucewood",
	roof   = "mcl_core:wood",
	floor  = "mcl_core:wood",
	window = "mcl_core:glass",
}
local HOUSE_R = 2         -- half-width -> 5x5 footprint
local HOUSE_H = 3         -- wall height in blocks
local BUILD_ARRIVE = 6    -- blocks: "home enough" to start building

-- Is the wall/interior box for a house centred on `c` clear to build and
-- unprotected? Checks the standing volume, not the floor beneath it.
local function house_fits(c, player_name)
	for dx = -HOUSE_R, HOUSE_R do
		for dz = -HOUSE_R, HOUSE_R do
			for dy = 0, HOUSE_H do
				local p = {x = c.x + dx, y = c.y + dy, z = c.z + dz}
				if minetest.is_protected(p, player_name or "") then return false end
				local node = minetest.get_node_or_nil(p)
				if not node then return false end   -- unloaded: don't build blind
				if node.name ~= "air" then
					local def = minetest.registered_nodes[node.name]
					if not (def and def.buildable_to) then return false end
				end
			end
		end
	end
	return true
end

-- First ground spot where a house fits: home itself, then points on rings around
-- it so an occupied home falls back to a clear neighbour. nil if nothing fits.
local function find_house_base(home, player_name)
	local offsets = {{0, 0}}
	for _, r in ipairs({6, 8, 10, 12}) do
		for _, d in ipairs({{r, 0}, {-r, 0}, {0, r}, {0, -r}, {r, r}, {-r, -r}, {r, -r}, {-r, r}}) do
			offsets[#offsets + 1] = d
		end
	end
	for _, o in ipairs(offsets) do
		local g = ground_near(home.x + o[1], home.z + o[2], home.y)
		if g and house_fits(g, player_name) then return g end
	end
	return nil
end

-- Raise a hollow 5x5 house on `base` (an air spot on the ground): plank floor,
-- spruce walls with a doorway and glass windows, plank roof.
local function build_house(base)
	local door_z = base.z - HOUSE_R   -- doorway on the -z wall, centre column
	for dx = -HOUSE_R, HOUSE_R do
		for dz = -HOUSE_R, HOUSE_R do
			local x, z = base.x + dx, base.z + dz
			local edge = math.abs(dx) == HOUSE_R or math.abs(dz) == HOUSE_R
			minetest.set_node({x = x, y = base.y - 1, z = z}, {name = HOUSE.floor})
			minetest.set_node({x = x, y = base.y + HOUSE_H, z = z}, {name = HOUSE.roof})
			for dy = 0, HOUSE_H - 1 do
				local p = {x = x, y = base.y + dy, z = z}
				if edge then
					local doorway = z == door_z and dx == 0 and dy < 2
					if doorway then
						minetest.set_node(p, {name = "air"})
					elseif dy == 1 and (dx == 0 or dz == 0) then
						minetest.set_node(p, {name = HOUSE.window})   -- window at wall mid
					else
						minetest.set_node(p, {name = HOUSE.wall})
					end
				else
					minetest.set_node(p, {name = "air"})             -- hollow interior
				end
			end
		end
	end
end

-- Walk home, then build a house there (or on a clear spot nearby). If the walk
-- genuinely stalls, build where the villager is standing instead.
local function process_buildhome(self, instruction)
	local player_name = instruction.player
	if not instruction.pos then
		self._theocraft_instruction = {type = "stay", player = player_name}
		return
	end
	local pos = self.object:get_pos()
	local stuck = (instruction.stuck or 0) >= 6
	if vector.distance(pos, instruction.pos) <= BUILD_ARRIVE or stuck then
		local anchor = stuck and vector.round(pos) or instruction.pos
		local base = find_house_base(anchor, player_name)
		if base then
			build_house(base)
			minetest.chat_send_player(player_name, string.format(
				"%s built a house at %d, %d, %d.", self._theocraft_name, base.x, base.y, base.z))
		else
			minetest.chat_send_player(player_name,
				self._theocraft_name .. " couldn't find a clear spot to build near home.")
		end
		self._theocraft_instruction = {type = "stay", player = player_name}
		return
	end
	if self.state == PATHFINDING then return end
	if now() < (instruction.next_at or 0) then return end
	instruction.next_at = now() + 3
	if walk_to(self, instruction.pos) then
		instruction.stuck = 0
	else
		instruction.next_at = now() + 2
		instruction.stuck = (instruction.stuck or 0) + 1
	end
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
	elseif action.type == "buildhome" then
		local home = idle_home(self)
		if not home or not home.x then
			return {ok = false, message = "I have no home yet. Set one with /tcsethome."}
		end
		self._theocraft_instruction = {
			type = "buildhome", player = player_name,
			pos = {x = home.x, y = home.y, z = home.z}, next_at = 0,
		}
		stop(self)
		return {ok = true, message = "Heading home to build a house."}
	elseif action.type == "goto" then
		local lm = mod.get_landmark(action.landmark)
		if not lm or not lm.x then return {ok = false, message = "I don't know where that is."} end
		self._theocraft_instruction = {
			type = "goto", player = player_name, landmark = lm.name,
			pos = {x = lm.x, y = lm.y, z = lm.z}, next_at = 0,
		}
		stop(self)
	elseif action.type == "guard" then
		local pos, label
		if action.landmark then
			local lm = mod.get_landmark(action.landmark)
			if not lm or not lm.x then return {ok = false, message = "I don't know where that is."} end
			pos, label = {x = lm.x, y = lm.y, z = lm.z}, lm.name
		end
		self._theocraft_instruction = {type = "guard", player = player_name, pos = pos, landmark = label, next_at = 0}
		stop(self)
	elseif action.type == "patrol" then
		local points = {}
		for _, name in ipairs(action.landmarks or {}) do
			local lm = mod.get_landmark(name)
			if lm and lm.x then points[#points + 1] = {x = lm.x, y = lm.y, z = lm.z} end
		end
		if #points < 2 then return {ok = false, message = "I need two places I know to patrol between."} end
		self._theocraft_instruction = {type = "patrol", player = player_name, points = points, index = 1, next_at = 0}
		stop(self)
	elseif action.type == "deliver" then
		local pos, label, to_player
		if action.landmark then
			local lm = mod.get_landmark(action.landmark)
			if not lm or not lm.x then return {ok = false, message = "I don't know where that is."} end
			pos, label = {x = lm.x, y = lm.y, z = lm.z}, lm.name
		else
			to_player = true
		end
		self._theocraft_instruction = {
			type = "deliver", player = player_name, pos = pos, landmark = label, to_player = to_player, next_at = 0,
		}
		stop(self)
	end
	return {ok = true}
end

function mod.tick_action(self)
	local instruction = self._theocraft_instruction
	if not instruction then return false end
	local t = instruction.type
	if t == "stay" then
		if not instruction.stopped then
			stop(self)
			instruction.stopped = true
		end
		return true
	end
	-- The stock villager AI sets self.jump = false whenever a player is nearby
	-- (so villagers hold still to trade). While WE drive movement that AI no
	-- longer runs, so re-enable jumping or she stalls on any 1-block rise.
	self.jump = true
	-- Actions that steer toward a fixed spot need no player present.
	if t == "goto" then process_goto(self, instruction); return true end
	if t == "buildhome" then process_buildhome(self, instruction); return true end
	if t == "patrol" then process_patrol(self, instruction); return true end
	if t == "guard" then process_guard(self, instruction); return true end
	if t == "roam" then process_roam(self, instruction); return true end
	-- Player-dependent actions.
	local player = get_player(instruction.player)
	if not player then
		self._theocraft_instruction = nil
		stop(self)
		return false
	end
	if t == "follow" then
		process_follow(self, instruction, player)
	elseif t == "come" then
		process_come(self, instruction, player)
	elseif t == "gather" then
		process_gather(self, instruction, player)
	elseif t == "deliver" then
		process_deliver(self, instruction, player)
	else
		self._theocraft_instruction = nil
		return false
	end
	return true
end

-- Idle behaviour: with no command, a villager occasionally strolls back toward
-- its home so the place feels lived-in. Runs only when free, on a per-villager
-- random timer, and only when the villager has wandered well away from home.
function mod.tick_idle(self)
	if self._theocraft_instruction then return end
	local village = idle_home(self)
	if not village or not village.x then return end
	local t = now()
	if not self._theocraft_next_roam then
		self._theocraft_next_roam = t + 30 + math.random(0, 90)
		return
	end
	if t < self._theocraft_next_roam then return end
	self._theocraft_next_roam = t + 45 + math.random(0, 75)

	local pos = self.object and self.object:get_pos()
	if not pos then return end
	local center = {x = village.x, y = village.y, z = village.z}
	if vector.distance(pos, center) <= 24 then return end   -- already home-ish; let it wander
	self._theocraft_instruction = {
		type = "roam",
		pos = {x = center.x + math.random(-6, 6), y = center.y, z = center.z + math.random(-6, 6)},
		next_at = 0,
	}
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
