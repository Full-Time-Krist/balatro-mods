--- RuFill: Russian translations for strings other mods left in English.
--- The translations live in localization/ru.lua; this mod has the highest priority,
--- so SMODS loads that file after every other mod's and it overrides their English fallbacks.

-- Entropy generates a "Blind Token" for every blind in English only; rebuild them
-- from the (already translated) blind names right before the game parses descriptions.
local function translate_blind_tokens()
	local desc = G.localization and G.localization.descriptions
	if not (desc and desc.CBlind and desc.Blind) then return end
	for key, entry in pairs(desc.CBlind) do
		local blind = desc.Blind[key:gsub("^c_entr_", "")]
		local name = blind and type(blind.name) == "string" and blind.name or "блайнд"
		entry.name = "Жетон: " .. name
		entry.text = { "Используйте, чтобы сменить", "текущий или следующий", "блайнд" }
	end
end

-- Some mods (Entropy via Cryptid hooks) reload their English files after startup,
-- overwriting ours. Re-apply our table after any other mod's localization load.
local rufill_mod = SMODS.current_mod
local ru_table
local function merge(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" and type(v[1]) ~= "string" and type(dst[k]) == "table" then
			merge(v, dst[k])
		else
			dst[k] = v
		end
	end
end
local function reapply()
	if G.SETTINGS.language ~= "ru" or not G.localization then return end
	if not ru_table then
		local chunk = load(NFS.read(rufill_mod.path .. "localization/ru.lua"))
		ru_table = chunk and chunk() or {}
	end
	merge(ru_table, G.localization)
end

local own_loaded = false
local load_mod_localization_ref = SMODS.load_mod_localization
local function load_mod_localization(path, mod_id, depth, ...)
	local ret = load_mod_localization_ref(path, mod_id, depth, ...)
	if not depth then
		if mod_id == rufill_mod.id then
			own_loaded = true
		elseif own_loaded then
			reapply()
		end
	end
	return ret
end
SMODS.load_mod_localization = load_mod_localization
SMODS.handle_loc_file = load_mod_localization

local init_localization_ref = init_localization
function init_localization(...)
	if G.SETTINGS.language == "ru" then translate_blind_tokens() end
	return init_localization_ref(...)
end

-- Dev helper: if "rufill_dump_request" exists in the save directory, dump every
-- localization string with Latin letters and no Cyrillic, then quit the game.
local function untranslated(s)
	return s:find("%a") and not s:find("[\208\209][\128-\191]")
end

local function serialize(v, indent)
	if type(v) == "string" then return string.format("%q", v) end
	if type(v) ~= "table" then return tostring(v) end
	local pad = indent .. "\t"
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) == "number"
	end)
	local out = { "{\n" }
	for _, k in ipairs(keys) do
		local key = type(k) == "number" and ("[" .. k .. "]") or string.format("[%q]", k)
		out[#out + 1] = pad .. key .. " = " .. serialize(v[k], pad) .. ",\n"
	end
	out[#out + 1] = indent .. "}"
	return table.concat(out)
end

-- Collects whole entries (e.g. a joker's name + text) that contain any untranslated string.
local function collect(src)
	if type(src) == "string" then return untranslated(src) and src or nil end
	if type(src) ~= "table" then return nil end
	local res, any = {}, false
	for k, v in pairs(src) do
		if not (type(k) == "string" and k:find("_parsed$")) then
			local sub = collect(v)
			if sub ~= nil then res[k] = sub; any = true end
		end
	end
	return any and res or nil
end

local function entry_level(desc)
	-- descriptions.<Set>.<key> are copied whole so the translator sees full context
	local out = {}
	for set, entries in pairs(desc or {}) do
		for key, entry in pairs(entries) do
			if collect(entry) then
				out[set] = out[set] or {}
				local copy = {}
				for k, v in pairs(entry) do
					if not (type(k) == "string" and k:find("_parsed$")) then copy[k] = v end
				end
				out[set][key] = copy
			end
		end
	end
	return out
end

local main_menu_ref = Game.main_menu
function Game:main_menu(...)
	local ret = main_menu_ref(self, ...)
	if love.filesystem.getInfo("rufill_dump_request") then
		love.filesystem.remove("rufill_dump_request")
		local dump = {
			descriptions = entry_level(G.localization.descriptions),
			misc = collect(G.localization.misc),
		}
		for k, v in pairs(G.localization) do
			if k ~= "descriptions" and k ~= "misc" then dump[k] = collect(v) end
		end
		love.filesystem.write("rufill_dump.lua", "return " .. serialize(dump, ""))
		love.event.quit()
	end
	return ret
end
