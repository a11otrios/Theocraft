-- Automatic circus arena builder: /build circus_arena [variant] [force].
-- Builds a complete Big Top tent with ring, seats, stage, lights, props,
-- stands, backstage, signs, and a show-start bell. Safe and cheerful:
-- existing builds are never bulldozed without the player's "force" word,
-- protected areas are left alone, and aerial gear always gets soft mats.
local mod = theocraft_circus

local VARIANTS = {
	small = {half = 6, wall = 4, ring = 2, label = "small"},
	medium = {half = 8, wall = 5, ring = 3, label = "medium"},
	large = {half = 11, wall = 6, ring = 4, label = "large"},
	rainbow = {half = 8, wall = 5, ring = 3, rainbow = true, label = "rainbow"},
	theos_show = {half = 11, wall = 6, ring = 5, rainbow = true, theo = true, label = "theos_show"},
}

local FILL_NODE = "mcl_core:dirt"
local CAP_NODE = "mcl_core:stone"

-- Node names containing any of these fragments count as natural terrain
-- (safe to flatten). Anything else solid counts as possibly important.
local NATURAL_HINTS = {
	"dirt", "grass", "sand", "gravel", "stone", "snow", "leaves", "log",
	"plant", "flower", "vine", "cactus", "water", "ice", "clay", "podzol",
	"mycelium", "moss", "root", "mushroom", "bush", "fern", "kelp",
	"seagrass", "tallgrass", "cobble", "andesite", "diorite", "granite",
	"ore", "tuff", "dripstone",
}

local function is_natural(name)
	if name == "air" then return true end
	for _, hint in ipairs(NATURAL_HINTS) do
		if name:find(hint, 1, true) then return true end
	end
	return false
end

local function is_hazard(name)
	return name:find("lava", 1, true) ~= nil
end

local function snap(n)
	return math.floor(n + 0.5)
end

local function safe_set(pos, name, param2, builder)
	local p = {x = snap(pos.x), y = snap(pos.y), z = snap(pos.z)}
	local current = minetest.get_node_or_nil(p)
	if not current or current.name == "ignore" then return false end
	if minetest.is_protected(p, builder) then return false end
	minetest.set_node(p, {name = name, param2 = param2 or 0})
	return true
end

local function safe_get(pos)
	local current = minetest.get_node_or_nil(pos)
	if not current or current.name == "ignore" then return nil end
	return current
end

-- Facing helpers (guarded: plain fallback when an API is missing).
local function facedir_to(from_pos, to_pos)
	if minetest.dir_to_facedir then
		local dir = vector.subtract(to_pos, from_pos)
		dir.y = 0
		if dir.x == 0 and dir.z == 0 then return 0 end
		local ok, facing = pcall(minetest.dir_to_facedir, dir)
		if ok and facing then return facing end
	end
	return 0
end

-- Standing-sign rotation so the text faces the viewer.
local function sign_rot(sign_pos, viewer_pos)
	if minetest.dir_to_yaw then
		local dir = vector.subtract(viewer_pos, sign_pos)
		dir.y = 0
		if dir.x ~= 0 or dir.z ~= 0 then
			local ok, yaw = pcall(minetest.dir_to_yaw, dir)
			if ok and yaw then
				local deg = (math.deg(yaw) - 1) % 360
				return math.floor(0.5 + (deg / 1.5) / 15) * 15
			end
		end
	end
	return 0
end

local SIGN_NODE = "mcl_signs:standing_sign_oak"

local function place_sign(pos, text, viewer_pos, builder)
	if minetest.registered_nodes[SIGN_NODE] then
		if safe_set(pos, SIGN_NODE, sign_rot(pos, viewer_pos or pos), builder) then
			local points = {}
			for i = 1, #text do points[#points + 1] = string.byte(text, i) end
			minetest.get_meta(pos):set_string("utext", minetest.serialize(points))
			if mcl_signs and mcl_signs.update_sign then
				pcall(mcl_signs.update_sign, pos)
			end
			return true
		end
		return false
	end
	-- Fallback when signs are unavailable: a golden banner marks the spot.
	return safe_set(pos, "theocraft_circus:banner_gold", 0, builder)
end

local function fill_crate(pos, items)
	local inv = minetest.get_meta(pos):get_inventory()
	if not inv then return end
	if inv:get_size("main") == 0 then inv:set_size("main", 24) end
	for _, item in ipairs(items) do
		inv:add_item("main", item)
	end
end

-- Survey the footprint, pick the flattest nearby spot, and (unless forced)
-- refuse when the area looks built-up or contains hazards.
local function survey(player, half, clear_h, force)
	local origin = player:get_pos()
	origin.y = origin.y + 0.5
	local look = player:get_look_dir()
	local fx, fz = 0, 1
	if look and (look.x ~= 0 or look.z ~= 0) then
		if math.abs(look.x) >= math.abs(look.z) then
			fx = (look.x > 0) and 1 or -1
			fz = 0
		else
			fx = 0
			fz = (look.z > 0) and 1 or -1
		end
	end
	local right = {x = -fz, z = fx}

	local function ground_at(x, z)
		for y = snap(origin.y) + 8, snap(origin.y) - 40, -1 do
			local node = safe_get({x = x, y = y, z = z})
			if node == nil then return nil end
			if node.name ~= "air" and minetest.registered_nodes[node.name] then
				local def = minetest.registered_nodes[node.name]
				if def.walkable then return y end
			end
		end
		return nil
	end

	local base_gx, base_gz = snap(origin.x) + fx * (half + 2), snap(origin.z) + fz * (half + 2)
	local best = nil
	local offsets = {{0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {2, 0}, {0, 2}}
	for _, off in ipairs(offsets) do
		local cx = base_gx + off[1] * (half + 1)
		local cz = base_gz + off[2] * (half + 1)
		local lo, hi, suspicious, hazards, waters, samples = nil, nil, 0, 0, 0, 0
		local failed = false
		for a = -half, half, 2 do
			for b = -half, half, 2 do
				local x = cx + right.x * a + fx * b
				local z = cz + right.z * a + fz * b
				local gy = ground_at(x, z)
				if not gy then failed = true break end
				samples = samples + 1
				if not lo or gy < lo then lo = gy end
				if not hi or gy > hi then hi = gy end
				for y = gy, gy + clear_h do
					local node = safe_get({x = x, y = y, z = z})
					if node and node.name ~= "air" then
						if is_hazard(node.name) then
							hazards = hazards + 1
						elseif node.name:find("water", 1, true) then
							waters = waters + 1
						elseif not is_natural(node.name) then
							suspicious = suspicious + 1
						end
					end
				end
			end
			if failed then break end
		end
		if not failed then
			local score = (hi - lo) * 20 + suspicious * 3 + hazards * 100
			if not best or score < best.score then
				best = {cx = cx, cz = cz, lo = lo, hi = hi,
					suspicious = suspicious, hazards = hazards,
					waters = waters, score = score}
			end
		end
	end
	if not best then return nil, "No open ground in front of you. Please move somewhere with solid land nearby." end
	if best.hazards > 0 and not force then
		return nil, "That spot has hot lava in it. Please pick a safer meadow, or add force to build anyway."
	end
	if best.suspicious > 25 and not force then
		return nil, "That spot already has about " .. best.suspicious ..
			" built blocks in it. I don't want to squash anyone's build! " ..
			"Move to an open meadow, or run the command again with force at the end to build here anyway."
	end
	return {cx = best.cx, floor = best.hi, fx = fx, fz = fz,
		right = right, suspicious = best.suspicious,
		roughness = best.hi - best.lo, forced = force}, nil
end

-- Flatten: fill hollows with dirt, clear the headroom. force also clears
-- player-made blocks (never in protected areas); hazards become stone.
local function flatten(site, half, clear_h, builder)
	local F = site.floor
	for a = -half, half do
		for b = -half, half do
			local x = site.cx + site.right.x * a + site.fx * b
			local z = site.cz + site.right.z * a + site.fz * b
			local surface = nil
			for y = F + clear_h, F - 12, -1 do
				local node = safe_get({x = x, y = y, z = z})
				if node == nil then break end
				if surface == nil then
					if node.name ~= "air" then surface = y end
				end
				if y > F then
					if node.name ~= "air" then
						local clearable = is_natural(node.name)
							or node.name:find("water", 1, true)
							or site.forced
						if clearable and not minetest.is_protected({x = x, y = y, z = z}, builder) then
							if is_hazard(node.name) then
								minetest.set_node({x = x, y = y, z = z}, {name = CAP_NODE})
							else
								minetest.set_node({x = x, y = y, z = z}, {name = "air"})
							end
						end
					end
				elseif y < F and y >= surface then
					-- Below floor but exposed (overhang edge): leave solid ground alone.
				end
			end
			if surface ~= nil and surface < F then
				for y = surface + 1, F do
					local p = {x = x, y = y, z = z}
					local node = safe_get(p)
					if node and (node.name == "air" or node.name:find("water", 1, true)) then
						safe_set(p, FILL_NODE, 0, builder)
					end
				end
			end
		end
	end
end

local RAINBOW_CANVAS = {
	"theocraft_circus:canvas_red",
	"theocraft_circus:canvas_yellow",
	"theocraft_circus:canvas_blue",
	"theocraft_circus:canvas_purple",
	"theocraft_circus:canvas_white",
}

local function build_arena(player, name, variant, force)
	local cfg = VARIANTS[variant]
	local half, wall_h, ring_r = cfg.half, cfg.wall, cfg.ring
	local rainbow, theo = cfg.rainbow, cfg.theo
	local clear_h = wall_h + 12

	local site, err = survey(player, half, clear_h, force)
	if not site then
		-- Retry path is handled by the caller with force; surface the message.
		return false, err
	end
	flatten(site, half, clear_h, name)

	local F = site.floor
	local placed = 0
	-- World position of the ring centre: signs face this so they read
	-- naturally from the middle of the show.
	local hub = {x = site.cx, y = F + 1, z = site.cz}
	local function put(la, lb, y, node, param2)
		local x = site.cx + site.right.x * la + site.fx * lb
		local z = site.cz + site.right.z * la + site.fz * lb
		if safe_set({x = x, y = y, z = z}, node, param2, name) then
			placed = placed + 1
			return {x = x, y = y, z = z}
		end
		return nil
	end
	local function face_to(la, lb, ta, tb)
		local fx = site.cx + site.right.x * la + site.fx * lb
		local fz = site.cz + site.right.z * la + site.fz * lb
		local tx = site.cx + site.right.x * ta + site.fx * tb
		local tz = site.cz + site.right.z * ta + site.fz * tb
		return facedir_to({x = fx, y = F, z = fz}, {x = tx, y = F, z = tz})
	end
	-- Local +b points toward the entrance (player side).
	local entrance_b = half

	-- Floor: sawdust everywhere, blue path, red ring with gold heart.
	for a = -half, half do
		for b = -half, half do
			local dist = math.sqrt(a * a + b * b)
			local node = "theocraft_circus:ring_sawdust"
			if dist <= 1.5 then
				node = "theocraft_circus:ring_gold"
			elseif dist <= ring_r then
				node = "theocraft_circus:ring_red"
			elseif math.abs(a) <= 1 and b > ring_r and b <= half then
				node = "theocraft_circus:ring_blue"
			end
			put(a, b, F, node)
		end
	end

	-- Walls with entrance gap, alternating canvas (rainbow cycles colours).
	local canvas_a = "theocraft_circus:canvas_striped_red"
	local canvas_b = "theocraft_circus:canvas_white"
	if rainbow then canvas_a = "theocraft_circus:canvas_striped_blue" end
	for y = 1, wall_h do
		for a = -half, half do
			for _, b in ipairs({-half, half}) do
				if not (b == entrance_b and math.abs(a) <= 1 and y <= 3) then
					local node = (((a + b) % 2 + 2) % 2 == 0) and canvas_a or canvas_b
					if rainbow then
						node = RAINBOW_CANVAS[(((a + b + y) % #RAINBOW_CANVAS) + #RAINBOW_CANVAS) % #RAINBOW_CANVAS + 1]
					end
					put(a, b, F + y, node)
				end
			end
		end
		for b = -half + 1, half - 1 do
			for _, a in ipairs({-half, half}) do
				local node = (((a + b) % 2 + 2) % 2 == 0) and canvas_a or canvas_b
				if rainbow then
					node = RAINBOW_CANVAS[(((a + b + y) % #RAINBOW_CANVAS) + #RAINBOW_CANVAS) % #RAINBOW_CANVAS + 1]
				end
				put(a, b, F + y, node)
			end
		end
	end

	-- Corner poles with golden tips.
	local pole_node = theo and "theocraft_circus:pole_gold" or "theocraft_circus:pole_red"
	for _, c in ipairs({{-half, -half}, {half, -half}, {-half, half}, {half, half}}) do
		for y = 1, wall_h + 1 do put(c[1], c[2], F + y, pole_node) end
		put(c[1], c[2], F + wall_h + 2, "theocraft_circus:spotlight_off", 0)
	end

	-- Stepped pyramid roof with golden finial.
	local level = 0
	while true do
		local inset = level + 1
		local span = half - inset
		if span * 2 + 1 < 3 then break end
		local y = F + wall_h + 1 + level
		for a = -span, span do
			for _, b in ipairs({-span, span}) do
				local node = (((a + b + level) % 2 + 2) % 2 == 0) and canvas_a or canvas_b
				if rainbow then
					node = RAINBOW_CANVAS[(((a + b + level) % #RAINBOW_CANVAS) + #RAINBOW_CANVAS) % #RAINBOW_CANVAS + 1]
				end
				put(a, b, y, node)
			end
		end
		for b = -span + 1, span - 1 do
			for _, a in ipairs({-span, span}) do
				local node = (((a + b + level) % 2 + 2) % 2 == 0) and canvas_a or canvas_b
				if rainbow then
					node = RAINBOW_CANVAS[(((a + b + level) % #RAINBOW_CANVAS) + #RAINBOW_CANVAS) % #RAINBOW_CANVAS + 1]
				end
				put(a, b, y, node)
			end
		end
		level = level + 1
		if level > 8 then break end
	end
	local cap_inset = level + 1
	local cap_span = half - cap_inset
	if cap_span < 1 then cap_span = 1 end
	for a = -cap_span, cap_span do
		for b = -cap_span, cap_span do
			put(a, b, F + wall_h + 1 + level, "theocraft_circus:ring_gold")
		end
	end
	put(0, 0, F + wall_h + 2 + level, "theocraft_circus:pole_gold")
	put(0, 0, F + wall_h, "theocraft_circus:fairy_light")

	-- Fairy lights glowing around the inside walls.
	for a = -half + 1, half - 1, 2 do
		put(a, -half + 1, F + wall_h, "theocraft_circus:fairy_light")
		if not (math.abs(a) <= 2) then
			put(a, half - 1, F + wall_h, "theocraft_circus:fairy_light")
		end
	end
	for b = -half + 2, half - 2, 2 do
		put(-half + 1, b, F + wall_h, "theocraft_circus:fairy_light")
		put(half - 1, b, F + wall_h, "theocraft_circus:fairy_light")
	end

	-- Banners hung along the walls (rainbow for rainbow/theos_show).
	local banner_nodes = {"theocraft_circus:banner_red", "theocraft_circus:banner_blue"}
	if rainbow or theo then
		banner_nodes = {"theocraft_circus:banner_rainbow", "theocraft_circus:banner_gold"}
	end
	local bi = 1
	for a = -half + 2, half - 2, 4 do
		put(a, -half, F + 3, banner_nodes[bi])
		bi = (bi % #banner_nodes) + 1
		if math.abs(a) > 2 then
			put(a, half, F + 4, banner_nodes[bi])
			bi = (bi % #banner_nodes) + 1
		end
	end

	-- Audience seats in arcs facing the ring (skipping entrance and stage).
	local rows = {}
	local r = ring_r + 2
	while r <= half - 1 do rows[#rows + 1] = r r = r + 2 end
	local seat_nodes = {"theocraft_circus:seat_red", "theocraft_circus:seat_blue"}
	for ri, rad in ipairs(rows) do
		for deg = 0, 350, 12 do
			local rad_a = math.rad(deg)
			-- Local angle: 90 degrees points at the entrance (+b).
			local ang_from_entrance = math.abs(((deg - 90 + 540) % 360) - 180)
			local ang_from_stage = math.abs(((deg - 270 + 540) % 360) - 180)
			if ang_from_entrance > 22 and ang_from_stage > 30 then
				local a = math.floor(math.cos(rad_a) * rad + 0.5)
				local b = math.floor(math.sin(rad_a) * rad + 0.5)
				if math.abs(a) < half and math.abs(b) < half then
					local node = seat_nodes[((a + b) % 2 + 2) % 2 + 1]
					if ri > 1 and (a + b) % 5 == 0 then
						node = "theocraft_circus:seat_vip"
					end
					put(a, b, F + 1, node, face_to(a, b, 0, 0))
				end
			end
		end
	end

	-- Stage opposite the entrance, with curtain backdrop and show boxes.
	local back = -(half - 1)
	local curtain_node = theo and "theocraft_circus:curtain_gold_closed"
		or "theocraft_circus:curtain_red_closed"
	for a = -4, 4 do
		put(a, back, F + 1, curtain_node, face_to(a, back, 0, half))
		put(a, back, F + 2, curtain_node, face_to(a, back, 0, half))
		for b = back + 1, back + 3 do
			put(a, b, F + 1, "theocraft_circus:stage")
		end
	end
	if theo then
		for a = -4, 4 do put(a, back + 4, F + 1, "theocraft_circus:ring_gold") end
	end
	put(-5, back + 2, F + 1, "theocraft_circus:applause_box", face_to(-5, back + 2, 0, 0))
	put(5, back + 2, F + 1, "theocraft_circus:music_box_off", face_to(5, back + 2, 0, 0))
	local stage_sign = put(0, back + 3, F + 2, "air", 0)
	if stage_sign then
		place_sign(stage_sign, theo and "Theo the Ringmaster" or "Stage", hub, name)
	end

	-- Spotlight poles aimed at the ring (extra for theos_show).
	local spots = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}
	if theo then
		spots = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}, {-2, 0}, {2, 0}, {0, -2}, {0, 2}}
	end
	for _, s in ipairs(spots) do
		local a, b = s[1] * (ring_r + 1), s[2] * (ring_r + 1)
		if math.abs(a) < half - 1 and math.abs(b) < half - 1 then
			for y = 1, 3 do put(a, b, F + y, pole_node) end
			put(a, b, F + 4, "theocraft_circus:spotlight_on", face_to(a, b, 0, 0))
		end
	end

	-- Tightrope run over soft mats (east side).
	local rope_b = 2
	local rope_a0 = 2
	put(rope_a0, rope_b, F + 1, "theocraft_circus:practice_mat_red")
	put(rope_a0, rope_b, F + 2, "theocraft_circus:tightrope_anchor")
	put(rope_a0, rope_b, F + 3, "theocraft_circus:tightrope_anchor")
	for a = rope_a0 + 1, rope_a0 + 4 do
		put(a, rope_b, F + 1, "theocraft_circus:practice_mat_red")
		put(a, rope_b, F + 3, "theocraft_circus:tightrope")
	end
	put(rope_a0 + 5, rope_b, F + 1, "theocraft_circus:practice_mat_red")
	put(rope_a0 + 5, rope_b, F + 2, "theocraft_circus:tightrope_anchor")
	put(rope_a0 + 5, rope_b, F + 3, "theocraft_circus:tightrope_anchor")
	local p = put(rope_a0 + 2, rope_b + 1, F + 1, "air", 0)
	if p then place_sign(p, "Tightrope Practice", hub, name) end

	-- Trapeze frame over mats (west side).
	local trz_b, trz_a = 0, -4
	for da = -1, 1 do
		for db = -1, 1 do
			put(trz_a + da, trz_b + db, F, "theocraft_circus:practice_mat_blue")
		end
	end
	for _, da in ipairs({-1, 1}) do
		for y = 1, 4 do put(trz_a + da, trz_b, F + y, pole_node) end
	end
	put(trz_a, trz_b, F + 4, pole_node, 1)
	put(trz_a, trz_b, F + 3, "theocraft_circus:trapeze")
	p = put(trz_a, trz_b + 2, F + 1, "air", 0)
	if p then place_sign(p, "Trapeze Zone", hub, name) end

	-- Hoop-jump row with mats.
	for i = 0, 2 do
		local a, b = 3 + i, half - 3
		put(a, b, F, "theocraft_circus:practice_mat_red")
		put(a, b, F + 1, "theocraft_circus:hoop_stand", face_to(a, b, a, b - 4))
	end
	p = put(4, half - 4, F + 1, "air", 0)
	if p then place_sign(p, "Hoop Jump Challenge", hub, name) end

	-- Trampoline on mats.
	for da = -1, 1 do
		for db = -1, 1 do
			put(-3 + da, half - 4 + db, F, "theocraft_circus:practice_mat_blue")
		end
	end
	put(-3, half - 4, F + 1, "theocraft_circus:trampoline")
	p = put(-3, half - 5, F + 1, "air", 0)
	if p then place_sign(p, "Mini Trampoline", hub, name) end

	-- Rola bola balance corner on mats.
	put(-2, -2, F, "theocraft_circus:practice_mat_red")
	put(-3, -2, F, "theocraft_circus:practice_mat_red")
	put(-2, -2, F + 1, "theocraft_circus:rola_bola")
	put(-3, -2, F + 1, "theocraft_circus:rola_bola")
	p = put(-2, -1, F + 1, "air", 0)
	if p then place_sign(p, "Balance Corner", hub, name) end

	-- Juggling corner with a stocked crate.
	local jug = put(half - 3, back + 1, F + 1, "theocraft_circus:crate", face_to(half - 3, back + 1, 0, 0))
	if jug then
		fill_crate(jug, {"theocraft_circus:juggling_balls 2", "theocraft_circus:acrobat_ribbon 1"})
	end
	p = put(half - 3, back + 2, F + 1, "air", 0)
	if p then place_sign(p, "Juggling Corner", hub, name) end

	-- Popcorn and prize stands near the entrance.
	put(3, half - 2, F + 1, "theocraft_circus:popcorn_stand", face_to(3, half - 2, 0, 0))
	p = put(3, half - 1, F + 1, "air", 0)
	if p then place_sign(p, "Popcorn Stand", hub, name) end
	put(-3, half - 2, F + 1, "theocraft_circus:prize_stand", face_to(-3, half - 2, 0, 0))
	p = put(-3, half - 1, F + 1, "air", 0)
	if p then place_sign(p, "Prize Stand", hub, name) end

	-- Backstage nook with storage crates.
	local bs_a, bs_b = -(half - 3), back + 1
	put(bs_a - 1, bs_b, F + 1, curtain_node, face_to(bs_a - 1, bs_b, 0, 0))
	put(bs_a, bs_b - 1, F + 1, curtain_node, face_to(bs_a, bs_b - 1, 0, 0))
	put(bs_a, bs_b, F + 1, "theocraft_circus:crate", face_to(bs_a, bs_b, 0, 0))
	local costume = put(bs_a - 1, bs_b - 1, F + 1, "theocraft_circus:crate", face_to(bs_a - 1, bs_b - 1, 0, 0))
	if costume and theo then
		fill_crate(costume, {
			"theocraft_circus:ringmaster_hat 1",
			"theocraft_circus:ringmaster_cane 1",
			"theocraft_circus:juggling_balls 1",
			"theocraft_circus:hoop 1",
			"theocraft_circus:confetti_popper 2",
			"theocraft_circus:music_disc 1",
			"theocraft_circus:performer_medal 1",
		})
	end
	p = put(bs_a, bs_b + 1, F + 1, "air", 0)
	if p then place_sign(p, "Backstage", hub, name) end

	-- Entrance: ticket booths, welcome sign, show bell with its sign.
	put(-2, half + 1, F + 1, "theocraft_circus:ticket_booth", face_to(-2, half + 1, 0, 0))
	put(2, half + 1, F + 1, "theocraft_circus:ticket_booth", face_to(2, half + 1, 0, 0))
	local bell = put(1, half - 2, F + 1, "theocraft_circus:performance_bell")
	p = put(1, half - 1, F + 1, "air", 0)
	if p then place_sign(p, "Press the Bell to Start the Show!",
		{x = p.x + site.fx * 3, y = p.y, z = p.z + site.fz * 3}, name) end
	local wx = site.cx + site.right.x * 0 + site.fx * (half + 2)
	local wz = site.cz + site.right.z * 0 + site.fz * (half + 2)
	local wpos = {x = wx, y = F + 1, z = wz}
	if safe_set(wpos, "air", 0, name) then
		place_sign(wpos, "Welcome to Theo's Circus!",
			{x = wx + site.fx * 3, y = F + 1, z = wz + site.fz * 3}, name)
	end
	p = put(0, ring_r + 1, F + 1, "air", 0)
	if p then place_sign(p, "Main Ring", hub, name) end

	-- Magical finale: confetti over the ring.
	local center = {x = site.cx, y = F + 1, z = site.cz}
	local waves = theo and 5 or 3
	for i = 1, waves do
		minetest.after(i * 0.5, function()
			mod.sparkle({x = center.x, y = center.y + 2, z = center.z}, "confetti")
			mod.safe_sound("mcl_note_block_pling", {pos = center, gain = 0.5})
		end)
	end
	return true, {placed = placed, center = center, bell = bell, variant = variant}
end

minetest.register_chatcommand("build", {
	params = "circus_arena [small | medium | large | rainbow | theos_show] [force]",
	description = "Magically build a complete Theo-friendly circus arena in front of you",
	func = function(name, param)
		local words = {}
		for word in (param or ""):lower():gmatch("%S+") do words[#words + 1] = word end
		if words[1] ~= "circus_arena" then
			return false, "Usage: /build circus_arena [small|medium|large|rainbow|theos_show] [force]"
		end
		local variant = words[2] or "medium"
		if not VARIANTS[variant] then
			return false, "Unknown arena: " .. variant ..
				". Try small, medium, large, rainbow, or theos_show."
		end
		local force = words[3] == "force" or words[2] == "force"
		if words[2] == "force" then variant = "medium" end
		local player = minetest.get_player_by_name(name)
		if not player then return false, "You must be in the game to build a circus." end

		local ok, result = build_arena(player, name, variant, force)
		if not ok then return false, result end

		local cfg = VARIANTS[variant]
		local extra = ""
		if cfg.theo then
			extra = " Theo's grand show ring, rainbow banners, golden stage, and a hidden costume chest backstage!"
		elseif cfg.rainbow then
			extra = " Rainbow roof and banners!"
		end
		minetest.chat_send_player(name, "[Circus] Ta-daa! Your " .. variant ..
			" circus arena appeared like magic!" .. extra ..
			" Ring the bell by the entrance to start the show!")
		return true, "Built the " .. variant .. " circus arena. Have fun performing!"
	end,
})
