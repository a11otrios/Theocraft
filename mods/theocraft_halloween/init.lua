theocraft_halloween = {}
local mod = theocraft_halloween
local storage = minetest.get_mod_storage()

local TREAT_ITEMS = {
	{name = "theocraft_halloween:candy", min = 2, max = 4, label = "Halloween candy"},
	{name = "theocraft_halloween:candy_corn", min = 3, max = 6, label = "candy corn"},
	{name = "theocraft_halloween:caramel_apple", min = 1, max = 1, label = "a caramel apple"},
}

local VILLAGER_LINES = {
	"Happy Halloween!",
	"A treat for you. Mind the bats tonight!",
	"No tricks this time--enjoy your treat!",
	"The village saved something sweet for you.",
}

function mod.is_enabled()
	local override = storage:get_string("enabled")
	if override == "true" then return true end
	if override == "false" then return false end
	return minetest.settings:get_bool("theocraft_halloween_enabled", true)
end

function mod.set_enabled(enabled)
	storage:set_string("enabled", enabled and "true" or "false")
end

local function give_item(player, stack)
	local inventory = player:get_inventory()
	if not inventory then return false end
	local leftover = inventory:add_item("main", stack)
	if not leftover:is_empty() then
		minetest.add_item(player:get_pos(), leftover)
	end
	return true
end

local function claim_key(player_name, source_id)
	return "claim:" .. minetest.sha1(player_name .. "\0" .. source_id)
end

local function grant_treat(player, source_id)
	local today = os.date("%Y-%m-%d")
	local key = claim_key(player:get_player_name(), source_id)
	if storage:get_string(key) == today then
		return false, "You already collected a treat here today. Try another villager or bowl."
	end

	local treat = TREAT_ITEMS[math.random(#TREAT_ITEMS)]
	local count = math.random(treat.min, treat.max)
	if not give_item(player, ItemStack(treat.name .. " " .. count)) then
		return false, "There was nowhere to put the treat."
	end
	storage:set_string(key, today)
	return true, string.format("You received %s%s.", treat.label, count > 1 and (" x" .. count) or "")
end

function mod.trick_or_treat(villager, player)
	if not mod.is_enabled() then return "Halloween mode is off." end
	if not villager or not player then return "No villager is close enough." end
	local id = villager._id or villager._theocraft_name or tostring(villager.object)
	local received, result = grant_treat(player, "villager:" .. id)
	if not received then return result end
	local line = VILLAGER_LINES[math.random(#VILLAGER_LINES)]
	if theocraft_villagers and theocraft_villagers.villager_say then
		theocraft_villagers.villager_say(villager, player:get_player_name(), line)
	end
	return line .. " " .. result
end

local candy_eat = minetest.item_eat(2)
minetest.register_craftitem("theocraft_halloween:candy", {
	description = "Halloween Candy",
	_doc_items_longdesc = "A brightly wrapped Halloween sweet obtained from villagers or crafted from sugar.",
	inventory_image = "mcl_core_sugar.png^[colorize:#F05A19:150",
	wield_image = "mcl_core_sugar.png^[colorize:#F05A19:150",
	stack_max = 64,
	on_place = candy_eat,
	on_secondary_use = candy_eat,
	groups = {food = 2, eatable = 2},
	_mcl_saturation = 0.6,
	touch_interaction = "short_dig_long_place",
})

local candy_corn_eat = minetest.item_eat(2)
minetest.register_craftitem("theocraft_halloween:candy_corn", {
	description = "Candy Corn",
	_doc_items_longdesc = "A handful of orange, yellow, and white Halloween sweets.",
	inventory_image = "mcl_core_sugar.png^[colorize:#FFB000:175",
	wield_image = "mcl_core_sugar.png^[colorize:#FFB000:175",
	stack_max = 64,
	on_place = candy_corn_eat,
	on_secondary_use = candy_corn_eat,
	groups = {food = 2, eatable = 2},
	_mcl_saturation = 0.6,
	touch_interaction = "short_dig_long_place",
})

local caramel_apple_eat = minetest.item_eat(5)
minetest.register_craftitem("theocraft_halloween:caramel_apple", {
	description = "Caramel Apple",
	_doc_items_longdesc = "A crisp apple covered in sticky caramel for Halloween.",
	inventory_image = "default_apple.png^[colorize:#8A451F:95",
	wield_image = "default_apple.png^[colorize:#8A451F:95",
	stack_max = 64,
	on_place = caramel_apple_eat,
	on_secondary_use = caramel_apple_eat,
	groups = {food = 2, eatable = 5, compostability = 65},
	_mcl_saturation = 3.0,
	touch_interaction = "short_dig_long_place",
})

minetest.register_node("theocraft_halloween:treat_bowl", {
	description = "Halloween Treat Bowl",
	_doc_items_longdesc = "A decorative bowl that offers each player one Halloween treat per day.",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	tiles = {"farming_pumpkin_face_light.png"},
	use_texture_alpha = "clip",
	node_box = {
		type = "fixed",
		fixed = {
			{-0.38, -0.50, -0.38, 0.38, -0.40, 0.38},
			{-0.38, -0.40, -0.38, -0.28, -0.12, 0.38},
			{ 0.28, -0.40, -0.38,  0.38, -0.12, 0.38},
			{-0.28, -0.40, -0.38,  0.28, -0.12, -0.28},
			{-0.28, -0.40,  0.28,  0.28, -0.12, 0.38},
		},
	},
	selection_box = {type = "fixed", fixed = {-0.4, -0.5, -0.4, 0.4, -0.1, 0.4}},
	collision_box = {type = "fixed", fixed = {-0.4, -0.5, -0.4, 0.4, -0.1, 0.4}},
	groups = {handy = 1, axey = 1, decorative = 1, dig_by_piston = 1},
	sounds = mcl_sounds.node_sound_wood_defaults(),
	_mcl_blast_resistance = 1,
	_mcl_hardness = 1,
	on_rightclick = function(pos, node, clicker, itemstack)
		if not clicker or not clicker:is_player() then return itemstack end
		if not mod.is_enabled() then
			minetest.chat_send_player(clicker:get_player_name(), "Halloween mode is off.")
			return itemstack
		end
		local _, message = grant_treat(clicker, "bowl:" .. minetest.pos_to_string(pos))
		minetest.chat_send_player(clicker:get_player_name(), message)
		return itemstack
	end,
})

minetest.register_craft({
	output = "theocraft_halloween:candy 4",
	type = "shapeless",
	recipe = {"mcl_core:sugar", "mcl_core:paper", "mcl_dye:orange"},
})

minetest.register_craft({
	output = "theocraft_halloween:candy_corn 6",
	type = "shapeless",
	recipe = {"mcl_core:sugar", "mcl_dye:orange", "mcl_dye:yellow", "mcl_dye:white"},
})

minetest.register_craft({
	output = "theocraft_halloween:caramel_apple",
	type = "shapeless",
	recipe = {"mcl_core:apple", "mcl_core:sugar"},
})

minetest.register_craft({
	output = "theocraft_halloween:treat_bowl",
	recipe = {
		{"theocraft_halloween:candy", "theocraft_halloween:candy_corn", "theocraft_halloween:candy"},
		{"", "mcl_core:bowl", ""},
	},
})

local ambience_timer = 0
minetest.register_globalstep(function(dtime)
	ambience_timer = ambience_timer + dtime
	if ambience_timer < 20 then return end
	ambience_timer = 0
	if not mod.is_enabled() or not minetest.settings:get_bool("theocraft_halloween_bats", true) then return end
	local time = minetest.get_timeofday()
	if time >= 0.20 and time <= 0.80 then return end
	if not minetest.registered_entities["mobs_mc:bat"] then return end

	for _, player in ipairs(minetest.get_connected_players()) do
		if math.random() <= 0.35 then
			local player_pos = player:get_pos()
			local bat_count = 0
			for _, object in ipairs(minetest.get_objects_inside_radius(player_pos, 18)) do
				local entity = object:get_luaentity()
				if entity and entity.name == "mobs_mc:bat" then bat_count = bat_count + 1 end
			end
			if bat_count < 3 then
				local spawn_pos = vector.add(player_pos, {
					x = math.random(-8, 8), y = math.random(3, 7), z = math.random(-8, 8),
				})
				local node = minetest.get_node_or_nil(spawn_pos)
				local def = node and minetest.registered_nodes[node.name]
				if def and not def.walkable then
					minetest.add_entity(spawn_pos, "mobs_mc:bat")
				end
			end
		end
	end
end)

local function give_kit(player)
	local items = {
		"mcl_farming:pumpkin_face_light 8",
		"mcl_core:cobweb 16",
		"theocraft_halloween:treat_bowl 2",
		"theocraft_halloween:candy 16",
		"theocraft_halloween:candy_corn 16",
		"theocraft_halloween:caramel_apple 4",
	}
	for _, item in ipairs(items) do give_item(player, ItemStack(item)) end
end

minetest.register_chatcommand("halloween", {
	params = "on | off | status | kit",
	description = "Control Theocraft Halloween mode or receive a decoration starter kit",
	privs = {server = true},
	func = function(name, param)
		param = (param or "status"):lower():match("^%s*(.-)%s*$")
		if param == "on" then
			mod.set_enabled(true)
			return true, "Halloween mode enabled."
		elseif param == "off" then
			mod.set_enabled(false)
			return true, "Halloween mode disabled."
		elseif param == "kit" then
			local player = minetest.get_player_by_name(name)
			if not player then return false, "Player is not available." end
			give_kit(player)
			return true, "Halloween decoration kit added to your inventory."
		elseif param == "status" or param == "" then
			return true, "Halloween mode is " .. (mod.is_enabled() and "enabled." or "disabled.")
		end
		return false, "Use /halloween on, off, status, or kit."
	end,
})

minetest.log("action", "[theocraft_halloween] Halloween feature pack loaded")
