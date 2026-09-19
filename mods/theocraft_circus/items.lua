-- Circus items: costumes, juggling toys, treats, and safe celebration tools.
local mod = theocraft_circus

-- 1. Ringmaster Hat (cosmetic + cheerful tip).
minetest.register_craftitem("theocraft_circus:ringmaster_hat", {
	description = "Ringmaster Hat",
	_doc_items_longdesc = "A grand top hat for hosting the circus. Wear it in style and announce the show with the ringmaster cane.",
	inventory_image = "wool_black.png^[colorize:#FFD23F:60",
	wield_image = "wool_black.png^[colorize:#FFD23F:60",
	stack_max = 1,
	groups = {clothing = 1, circus = 1},
})

-- 2. Ringmaster Cane (announcement + sparkles, never a weapon).
minetest.register_craftitem("theocraft_circus:ringmaster_cane", {
	description = "Ringmaster Cane",
	_doc_items_longdesc = "A twirly show cane. Use it to announce acts with sparkles and a cheerful message. It cannot hurt anyone.",
	inventory_image = "default_stick.png^[colorize:#FFD23F:120",
	wield_image = "default_stick.png^[colorize:#FFD23F:120",
	stack_max = 1,
	groups = {circus = 1},
	on_use = function(itemstack, user, pointed_thing)
		if user and user:is_player() then
			local pos = user:get_pos()
			if pos then
				pos.y = pos.y + 1.2
				mod.sparkle(pos, "cane")
			end
			local name = user:get_player_name()
			minetest.chat_send_all("[Circus] " .. name .. " taps the cane: Theo's show is starting! Welcome, everyone!")
			mod.safe_sound("mcl_note_block_pling", {pos = user:get_pos(), gain = 0.6})
		end
		return itemstack
	end,
})

-- Juggling helpers: rhythm taps earn applause and medals. Timing comes from
-- the engine monotonic clock via mod.now_us; mod.juggle_tap keeps the pure
-- rhythm rule (0.25s-2.5s continues the combo, anything else restarts it).
local function juggle_use(kind, color_tex)
	return function(itemstack, user, pointed_thing)
		if not (user and user:is_player()) then return itemstack end
		local name = user:get_player_name()
		local now = mod.now_us()
		local state = mod.juggle_progress[name] or {last = 0, combo = 0, best = 0}
		mod.juggle_tap(state, now)
		mod.juggle_progress[name] = state
		local pos = user:get_pos()
		if pos then
			pos.y = pos.y + 1.6
			mod.sparkle(pos, "juggle")
		end
		if state.combo > 0 and state.combo % 10 == 0 then
			minetest.chat_send_player(name, "[Circus] Juggling combo x" .. state.combo .. "! The crowd goes wild!")
			mod.cheer(name)
			if state.combo == 30 then
				local inv = user:get_inventory()
				if inv and inv:room_for_item("main", "theocraft_circus:performer_medal 1") then
					inv:add_item("main", "theocraft_circus:performer_medal 1")
					minetest.chat_send_player(name, "[Circus] A Performer Medal for brilliant juggling!")
				end
			end
		elseif state.combo <= 3 then
			minetest.chat_send_player(name, "[Circus] Lovely " .. kind .. " juggling! Keep the rhythm going!")
		end
		return itemstack
	end
end

-- 3. Juggling Balls.
minetest.register_craftitem("theocraft_circus:juggling_balls", {
	description = "Juggling Balls",
	_doc_items_longdesc = "Soft colourful juggling balls. Use them in rhythm to build a combo and earn applause.",
	inventory_image = "wool_red.png^[colorize:#FFFFFF:40",
	wield_image = "wool_red.png^[colorize:#FFFFFF:40",
	stack_max = 16,
	groups = {circus = 1},
	on_use = juggle_use("ball", "red"),
})

-- 4. Juggling Clubs.
minetest.register_craftitem("theocraft_circus:juggling_clubs", {
	description = "Juggling Clubs",
	_doc_items_longdesc = "Stripy juggling clubs with a twirlier toss. Use in rhythm, just like the balls.",
	inventory_image = "default_stick.png^[colorize:#FF4FA3:120",
	wield_image = "default_stick.png^[colorize:#FF4FA3:120",
	stack_max = 16,
	groups = {circus = 1},
	on_use = juggle_use("club", "club"),
})

-- 5. Circus Hoop (held or placed via hoop stand).
minetest.register_craftitem("theocraft_circus:hoop", {
	description = "Circus Hoop",
	_doc_items_longdesc = "A light acrobatics hoop. Place it on a hoop stand, then leap through for applause.",
	inventory_image = "wool_yellow.png^[colorize:#FF4FA3:100",
	wield_image = "wool_yellow.png^[colorize:#FF4FA3:100",
	stack_max = 8,
	groups = {circus = 1},
	on_use = function(itemstack, user, pointed_thing)
		if user and user:is_player() then
			local pos = user:get_pos()
			if pos then
				pos.y = pos.y + 1.2
				mod.sparkle(pos, "hoop")
				minetest.chat_send_player(user:get_player_name(), "[Circus] Swish! A graceful hoop twirl!")
			end
		end
		return itemstack
	end,
})

-- 6. Acrobat Ribbon (swirly trail).
minetest.register_craftitem("theocraft_circus:acrobat_ribbon", {
	description = "Acrobat Ribbon",
	_doc_items_longdesc = "A rainbow ribbon that paints a swirly trail of sparkles when waved.",
	inventory_image = "wool_magenta.png^[colorize:#FFFFFF:60",
	wield_image = "wool_magenta.png^[colorize:#FFFFFF:60",
	stack_max = 8,
	groups = {circus = 1},
	on_use = function(itemstack, user, pointed_thing)
		if user and user:is_player() then
			local pos = user:get_pos()
			if pos then
				for i = 1, 3 do
					mod.sparkle({x = pos.x + math.sin(i) * 0.8, y = pos.y + 1 + i * 0.2, z = pos.z + math.cos(i) * 0.8}, "ribbon")
				end
				minetest.chat_send_player(user:get_player_name(), "[Circus] Beautiful ribbon swirls!")
			end
		end
		return itemstack
	end,
})

-- 7. Ticket (roleplay entry).
minetest.register_craftitem("theocraft_circus:ticket", {
	description = "Circus Ticket",
	_doc_items_longdesc = "A golden circus admission ticket. Hand them out at the ticket booth for roleplay entry.",
	inventory_image = "default_paper.png^[colorize:#FFD23F:140",
	wield_image = "default_paper.png^[colorize:#FFD23F:140",
	stack_max = 64,
	groups = {circus = 1},
})

-- 8. Popcorn (small fun food).
local popcorn_food = tonumber(minetest.settings:get("theocraft_circus_popcorn_food")) or 2
local popcorn_eat = minetest.item_eat and minetest.item_eat(popcorn_food) or nil
minetest.register_craftitem("theocraft_circus:popcorn", {
	description = "Circus Popcorn",
	_doc_items_longdesc = "Warm, buttery circus popcorn. A small happy snack for watching the show.",
	inventory_image = "mcl_core_sugar.png^[colorize:#FFD23F:170",
	wield_image = "mcl_core_sugar.png^[colorize:#FFD23F:170",
	stack_max = 64,
	groups = {food = 2, eatable = 2, circus = 1},
	_mcl_saturation = 0.8,
	on_place = popcorn_eat,
	on_secondary_use = popcorn_eat,
	touch_interaction = "short_dig_long_place",
})

-- 9. Confetti Popper (safe celebration: particles + sound only).
minetest.register_craftitem("theocraft_circus:confetti_popper", {
	description = "Confetti Popper",
	_doc_items_longdesc = "A safe party popper that bursts into colourful confetti. No explosion, no damage, just celebration.",
	inventory_image = "default_paper.png^[colorize:#FF4FA3:140",
	wield_image = "default_paper.png^[colorize:#FF4FA3:140",
	stack_max = 32,
	groups = {circus = 1},
	on_use = function(itemstack, user, pointed_thing)
		if user and user:is_player() then
			local pos = user:get_pos()
			if pos then
				pos.y = pos.y + 1.4
				for _ = 1, 3 do mod.sparkle(pos, "confetti") end
				mod.safe_sound("mcl_note_block_pling", {pos = pos, gain = 0.7})
				if mod.is_theo_mode() then
					minetest.chat_send_all("[Circus] Hooray! Confetti for " .. user:get_player_name() .. "! The crowd goes wild!")
				end
			end
			if not minetest.is_creative_enabled(user:get_player_name()) then
				itemstack:take_item(1)
			end
		end
		return itemstack
	end,
})

-- 10. Performer Medal (reward for challenges).
minetest.register_craftitem("theocraft_circus:performer_medal", {
	description = "Performer Medal",
	_doc_items_longdesc = "A shiny gold medal awarded for completing circus challenges with kindness and style.",
	inventory_image = "mcl_core_gold_nugget.png^[colorize:#FFD23F:120",
	wield_image = "mcl_core_gold_nugget.png^[colorize:#FFD23F:120",
	stack_max = 16,
	groups = {circus = 1},
})

-- 11. Circus Music Disc (plays a cheerful jingle via note-block plings).
minetest.register_craftitem("theocraft_circus:music_disc", {
	description = "Circus Music Disc",
	_doc_items_longdesc = "An upbeat circus tune on a rainbow disc. Use it for a burst of happy music.",
	inventory_image = "wool_cyan.png^[colorize:#FFD23F:80",
	wield_image = "wool_cyan.png^[colorize:#FFD23F:80",
	stack_max = 8,
	groups = {circus = 1},
	on_use = function(itemstack, user, pointed_thing)
		if user and user:is_player() then
			local pos = user:get_pos()
			if pos then
				for i = 1, 5 do
					minetest.after(i * 0.22, function()
						mod.safe_sound("mcl_note_block_pling", {pos = pos, gain = 0.6})
						mod.sparkle({x = pos.x, y = pos.y + 1.5, z = pos.z}, "music")
					end)
				end
				minetest.chat_send_player(user:get_player_name(), "[Circus] Oom-pah-pah! The circus band plays!")
			end
		end
		return itemstack
	end,
})

-- 12. Magic Wand (harmless sparkles for shows).
minetest.register_craftitem("theocraft_circus:magic_wand", {
	description = "Circus Magic Wand",
	_doc_items_longdesc = "A twinkly wand for magic acts. It only makes gentle sparkles and happy gasps — nothing scary.",
	inventory_image = "default_stick.png^[colorize:#B388FF:140",
	wield_image = "default_stick.png^[colorize:#B388FF:140",
	stack_max = 1,
	groups = {circus = 1},
	on_use = function(itemstack, user, pointed_thing)
		if user and user:is_player() then
			local pos = user:get_pos()
			local target = pos and {x = pos.x, y = pos.y + 1.4, z = pos.z} or nil
			if target then
				mod.sparkle(target, "magic")
				mod.safe_sound("mcl_note_block_pling", {pos = pos, gain = 0.5})
				minetest.chat_send_player(user:get_player_name(), "[Circus] Ta-daa! Gentle circus magic!")
			end
		end
		return itemstack
	end,
})
