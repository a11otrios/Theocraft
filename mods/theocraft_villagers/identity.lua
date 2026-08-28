local mod = theocraft_villagers

local names = {
	"Ada", "Alden", "Anika", "Bram", "Cora", "Dara", "Elian", "Esme",
	"Farah", "Galen", "Hana", "Ivo", "Jora", "Kellan", "Lina", "Mara",
	"Niko", "Orla", "Pavel", "Rhea", "Soren", "Talia", "Uma", "Vero",
}

local profession_labels = {
	armorer = "armorer",
	butcher = "butcher",
	cartographer = "cartographer",
	cleric = "cleric",
	farmer = "farmer",
	fisherman = "fisher",
	fletcher = "fletcher",
	leatherworker = "leatherworker",
	librarian = "librarian",
	mason = "mason",
	nitwit = "wanderer",
	shepherd = "shepherd",
	toolsmith = "toolsmith",
	unemployed = "village helper",
	weaponsmith = "weaponsmith",
}

local bio_templates = {
	"A practical %s who knows the paths and people around this village.",
	"A thoughtful %s who enjoys helping travellers with sensible jobs.",
	"A cheerful %s with a sharp memory for local places and resources.",
	"A reserved %s who values clear promises and useful work.",
}

local function stable_number(value)
	local total = 0
	for i = 1, #value do
		total = (total * 33 + value:byte(i)) % 2147483647
	end
	return total
end

local function short(value, maximum)
	value = tostring(value or ""):gsub("[%c]", " "):gsub("%s+", " ")
	value = value:match("^%s*(.-)%s*$") or ""
	return value:sub(1, maximum)
end

function mod.ensure_identity(self)
	if not self._id or self._id == "" then
		self._id = mcl_util.gen_uuid()
	end

	local seed = stable_number(self._id)
	if not self._theocraft_name or self._theocraft_name == "" then
		self._theocraft_name = names[(seed % #names) + 1]
	end

	if not self._theocraft_bio or self._theocraft_bio == "" then
		local profession = profession_labels[self._profession] or
			short((self._profession or "villager"):gsub("_", " "), 32)
		local template = bio_templates[(math.floor(seed / #names) % #bio_templates) + 1]
		self._theocraft_bio = string.format(template, profession)
	end

	-- A human-friendly "birthday" (DDMMYY) stamped once, so villagers that share a
	-- name can still be told apart and targeted precisely by /tcfind and /tcrevive.
	if not self._theocraft_born or self._theocraft_born == "" then
		self._theocraft_born = os.date("%d%m%y")
	end

	self._theocraft_name = short(self._theocraft_name, 40)
	self._theocraft_bio = short(self._theocraft_bio, 180)
	if self.nametag ~= self._theocraft_name then
		self.nametag = self._theocraft_name
		if self.update_tag then
			self:update_tag()
		elseif self.object and self.object:get_pos() then
			self.object:set_properties({nametag = self._theocraft_name})
		end
	end
	return self._theocraft_name, self._theocraft_bio
end

function mod.identity_snapshot(self)
	local name, bio = mod.ensure_identity(self)
	local pos = self.object and self.object:get_pos()
	if pos then
		pos = vector.round(pos)
	end
	return {
		id = self._id,
		name = name,
		bio = bio,
		profession = profession_labels[self._profession] or self._profession or "villager",
		position = pos,
		-- Birthday (DDMMYY), stamped once at creation. The gateway can use it to
		-- pick a voice (e.g. keep older villagers on the original TTS engine).
		born = self._theocraft_born,
	}
end
