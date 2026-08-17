local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)

theocraft_villagers = {
	modname = modname,
	modpath = modpath,
	sessions = {},
	histories = {},
	pending = {},
	storage = minetest.get_mod_storage(),
}

local function load(name)
	dofile(modpath .. "/" .. name .. ".lua")
end

load("identity")
load("policy")
load("actions")
load("llm")
load("ui")
load("integration")

minetest.log("action", "[theocraft_villagers] LLM villager integration loaded")
