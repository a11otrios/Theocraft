local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)

theocraft_villagers = {
	modname = modname,
	modpath = modpath,
	sessions = {},
	histories = {},
	pending = {},
	storage = minetest.get_mod_storage(),
	-- request_http_api() only returns the handle when called from a mod's
	-- init.lua top-level scope (the engine's security check rejects calls made
	-- from dofile'd sub-files). Grab it here and hand it to llm.lua.
	http = minetest.request_http_api and minetest.request_http_api() or nil,
}

local function load(name)
	dofile(modpath .. "/" .. name .. ".lua")
end

load("identity")
load("policy")
load("landmarks")
load("actions")
load("llm")
load("speech")
load("locate")
load("ui")
load("integration")

minetest.log("action", "[theocraft_villagers] LLM villager integration loaded")
