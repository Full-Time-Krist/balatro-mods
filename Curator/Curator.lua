--- Curator: keeps a large mod pack coherent.
--- * bans.lua lists jokers/consumables that duplicate another mod's card; they are removed
---   from every random pool (still visible in the collection, still creatable by key).
--- * fixes.lua holds small cross-mod compatibility patches.
--- * Dev helper: a "curator_dump_request" file in the save directory makes the game write
---   curator_dump.lua (all jokers/consumables with English text) and quit.

Curator = Curator or {}
local mod = SMODS.current_mod
Curator.mod = mod

local function load_file(name)
	local src = NFS.read(mod.path .. name)
	if not src then return nil end
	local chunk, err = load(src, "=[Curator " .. name .. "]")
	if not chunk then
		sendErrorMessage("Curator: " .. tostring(err), "Curator")
		return nil
	end
	local ok, res = pcall(chunk)
	if not ok then
		sendErrorMessage("Curator: " .. tostring(res), "Curator")
		return nil
	end
	return res
end

-- ---------------------------------------------------------------- bans

Curator.bans = load_file("bans.lua") or {}
Curator.banned = {}

local function never() return false end

local function apply_bans()
	if mod.config.bans == false then return end
	local n = 0
	for key, why in pairs(Curator.bans) do
		local center = G.P_CENTERS[key]
		if center and not Curator.banned[key] then
			Curator.banned[key] = why
			center.curator_in_pool = center.in_pool
			center.in_pool = never
			n = n + 1
		end
	end
	sendInfoMessage("Curator: removed " .. n .. " duplicate cards from pools", "Curator")
end

-- ---------------------------------------------------------------- fixes

local fixes = load_file("fixes.lua")

-- ---------------------------------------------------------------- dump

local function enc(v, out)
	local t = type(v)
	if t == "string" then
		out[#out + 1] = string.format("%q", v)
	elseif t == "number" or t == "boolean" then
		out[#out + 1] = tostring(v)
	elseif t == "table" then
		out[#out + 1] = "{"
		for k, x in pairs(v) do
			if type(k) == "string" or type(k) == "number" then
				local tx = type(x)
				if tx == "string" or tx == "number" or tx == "boolean" or tx == "table" then
					out[#out + 1] = "[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]="
					enc(x, out)
					out[#out + 1] = ","
				end
			end
		end
		out[#out + 1] = "}"
	else
		out[#out + 1] = "nil"
	end
end

local function read_loc(path)
	local src = NFS.read(path)
	if not src then return nil end
	local chunk = load(src)
	if not chunk then return nil end
	local ok, res = pcall(chunk)
	return ok and type(res) == "table" and res or nil
end

local function strip(text)
	if type(text) ~= "table" then return text end
	local out = {}
	for _, line in ipairs(text) do
		if type(line) == "table" then
			for _, l in ipairs(line) do out[#out + 1] = tostring(l) end
		else
			out[#out + 1] = tostring(line)
		end
	end
	return out
end

-- loc_txt gets rewritten during injection; keep the authors' English for the dump
local loc_snapshot = {}
if love.filesystem.getInfo("curator_dump_request") then
	for key, obj in pairs(SMODS.Centers or {}) do
		if type(obj.loc_txt) == "table" then loc_snapshot[key] = copy_table(obj.loc_txt) end
	end
end

local function dump()
	local en = { vanilla = read_loc("localization/en-us.lua") }
	if not en.vanilla then
		local src = love.filesystem.read("localization/en-us.lua")
		local chunk = src and load(src)
		en.vanilla = chunk and chunk()
	end
	for id, m in pairs(SMODS.Mods) do
		if m.path and m.can_load ~= false then
			en[id] = read_loc(m.path .. "localization/en-us.lua") or read_loc(m.path .. "localization/default.lua") or read_loc(m.path .. "localization/Default.lua")
		end
	end
	local function find_text(center)
		local lt = loc_snapshot[center.key] or center.loc_txt
		if type(lt) == "table" then
			local e = lt["en-us"] or lt["default"] or (lt.name and lt)
			if e and e.text then return e.name, e.text end
		end
		local mod_id = center.mod and center.mod.id or "vanilla"
		for _, src in ipairs({ mod_id, "vanilla" }) do
			local d = en[src] and en[src].descriptions and en[src].descriptions[center.set]
			local e = d and d[center.key]
			if e then return e.name, e.text end
		end
		for _, l in pairs(en) do
			local d = l.descriptions and l.descriptions[center.set]
			local e = d and d[center.key]
			if e then return e.name, e.text end
		end
		local cur = G.localization.descriptions[center.set]
		local e = cur and cur[center.key]
		if e then return e.name, e.text end
	end
	local consumable = { Tarot = true, Planet = true, Spectral = true }
	for k in pairs(SMODS.ConsumableTypes or {}) do consumable[k] = true end
	local cards = {}
	for key, c in pairs(G.P_CENTERS) do
		if c.set == "Joker" or consumable[c.set] then
			local name, text = find_text(c)
			cards[#cards + 1] = {
				key = key,
				set = c.set,
				mod = c.mod and c.mod.id or "vanilla",
				rarity = c.rarity,
				cost = c.cost,
				bp = c.blueprint_compat,
				hidden = c.hidden or c.no_collection or nil,
				custom_pool = c.in_pool and true or nil,
				config = c.config,
				name = name,
				text = strip(text),
				ru = G.localization.descriptions[c.set] and G.localization.descriptions[c.set][key]
					and G.localization.descriptions[c.set][key].name,
			}
		end
	end
	local out = { "return " }
	enc(cards, out)
	love.filesystem.write("curator_dump.lua", table.concat(out))
end

-- ---------------------------------------------------------------- hooks

local injected = false
local main_menu_ref = Game.main_menu
function Game:main_menu(...)
	if not injected then
		injected = true
		apply_bans()
		if fixes and fixes.apply then
			local ok, err = pcall(fixes.apply)
			if not ok then sendErrorMessage("Curator fixes: " .. tostring(err), "Curator") end
		end
	end
	local ret = main_menu_ref(self, ...)
	if not Curator.autotest and (love.filesystem.getInfo("curator_autotest_request")
		or (love.filesystem.getInfo("curator_autotest_state.lua") and not (love.filesystem.read("curator_autotest_state.lua") or ""):find("done=true"))) then
		Curator.autotest = load_file("autotest.lua")
		if Curator.autotest then Curator.autotest.start() end
	end
	if love.filesystem.getInfo("curator_dump_request") then
		love.filesystem.remove("curator_dump_request")
		dump()
		if not love.filesystem.getInfo("rufill_dump_request") then love.event.quit() end
	end
	return ret
end

mod.config_tab = function()
	return { n = G.UIT.ROOT, config = { r = 0.1, align = "cm", padding = 0.2, colour = G.C.BLACK, minw = 6 }, nodes = {
		create_toggle({ label = "Убрать дубликаты из пулов (нужен перезапуск)", ref_table = mod.config, ref_value = "bans" }),
	} }
end
