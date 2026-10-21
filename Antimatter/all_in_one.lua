--- "Все в одном": one joker that carries the effect of every other joker.
--- Each joker is represented by a lightweight proxy (own ability table, no
--- sprites, not in any card area) that falls back to the real card for
--- everything else, so the original calculate code runs unchanged.

local KEY = "j_hstart_all_in_one"

-- Jokers left out: Cryptposting's "Всё" (itself "create every joker"; adding
-- it killed the game silently).
local SKIP = { j_crp_all = true }

-- Runtime only: proxies are rebuilt after loading a save, so scaling jokers
-- start over from their base values then.
local subs_by_card = setmetatable({}, { __mode = "k" })
local broken = {}

local function noop() end

local function make_proxy(card, center)
	-- Own T/VT only while set_ability runs (it resizes Half Joker, Wee Joker...);
	-- afterwards the proxy follows the real card's position.
	local p = setmetatable({
		ability = {},
		-- A real Card has its center set before set_ability runs; Entropy's
		-- set_ability hook turns center-less cards into "disavowed".
		config = { center = center },
		params = {},
		children = {},
		T = copy_table(card.T),
		original_T = copy_table(card.original_T or card.T),
		added_to_deck = false,
		edition = false,
		hstart_proxy = true,
		set_sprites = noop,
		juice_up = noop,
	}, { __index = card })
	Card.set_ability(p, center, true)
	p.T, p.original_T = nil, nil
	return p
end

local function build_subs(card, added)
	-- set_ability marks every joker as used, which would empty the shop pool.
	local used_jokers = copy_table(G.GAME.used_jokers)
	local subs = { list = {}, by_key = {}, by_name = {} }
	-- Register early: set_ability calls SMODS.find_card, which reaches get_subs.
	subs_by_card[card] = subs
	for _, center in ipairs(G.P_CENTER_POOLS.Joker) do
		if center.key ~= KEY and not SKIP[center.key] and not broken[center.key] then
			local ok, p = pcall(make_proxy, card, center)
			if ok then
				p.added_to_deck = added
				subs.list[#subs.list + 1] = p
				subs.by_key[center.key] = p
				-- Some run modifiers rewrite the ability right away and drop the name.
				if p.ability.name ~= nil then subs.by_name[p.ability.name] = p end
			else
				broken[center.key] = true
				sendWarnMessage(("Could not build %s: %s"):format(center.key, tostring(p)), "Antimatter")
			end
		end
	end
	G.GAME.used_jokers = used_jokers
	return subs
end

local function get_subs(card)
	-- A card without proxies here was loaded from a save: if its add_to_deck
	-- effects were applied before, they are already part of the saved state.
	return subs_by_card[card] or build_subs(card, card.ability.hstart_applied and true or false)
end

local function alive(p)
	-- Some jokers transform themselves via set_ability; a proxy that is no
	-- longer a joker would feed non-joker data to joker code.
	if p.config.center.set ~= "Joker" then return false end
	return not (p.hstart_dead or rawget(p, "removed") or rawget(p, "REMOVED") or rawget(p, "getting_sliced"))
end

local each_sub

-- Apply every joker's add_to_deck effects (hand size, slots, ...) once per card.
local function apply_add_to_deck(card, from_debuff)
	each_sub(card, function(p)
		if not p.added_to_deck then Card.add_to_deck(p, from_debuff) end
	end)
	card.ability.hstart_applied = true
end

function each_sub(card, fn)
	for _, p in ipairs(get_subs(card).list) do
		if alive(p) then
			local ok, err = pcall(fn, p)
			if not ok then
				p.hstart_dead = true
				broken[p.config.center.key] = true
				sendWarnMessage(("Disabled %s: %s"):format(p.config.center.key, tostring(err)), "Antimatter")
			end
		end
	end
end

-- Let passive jokers (Four Fingers, Showman, Oops! All 6s, ...) see their
-- proxy as if that joker were owned.
local function owned_cards(count_debuffed)
	local res = {}
	if not (G.jokers and G.jokers.cards) then return res end
	for _, v in ipairs(G.jokers.cards) do
		if v.config and v.config.center.key == KEY and (count_debuffed or not v.debuff) then res[#res + 1] = v end
	end
	return res
end

local find_card_ref = SMODS.find_card
function SMODS.find_card(key, count_debuffed)
	local res = find_card_ref(key, count_debuffed)
	if key ~= KEY then
		for _, card in ipairs(owned_cards(count_debuffed)) do
			local p = get_subs(card).by_key[key]
			if p and alive(p) and p.config.center.key == key then res[#res + 1] = p end
		end
	end
	return res
end

local find_joker_ref = find_joker
function find_joker(name, non_debuff)
	local res = find_joker_ref(name, non_debuff)
	for _, card in ipairs(owned_cards(non_debuff)) do
		local p = get_subs(card).by_name[name]
		if p and alive(p) and p.ability.name == name then res[#res + 1] = p end
	end
	return res
end

local function calculate_all(self, card, context)
	if not card.ability.hstart_applied and not context.blueprint then apply_add_to_deck(card) end
	-- Probability modifiers pass their running value from one joker to the next.
	if context.mod_probability or context.fix_probability then
		local num, den = context.numerator, context.denominator
		each_sub(card, function(p)
			local ret = Card.calculate_joker(p, context)
			if type(ret) == "table" then
				num = ret.numerator or num
				den = ret.denominator or den
				context.numerator, context.denominator = num, den
			end
		end)
		return { numerator = num, denominator = den }
	end

	if context.check_enhancement then
		local enh = {}
		each_sub(card, function(p)
			local ret = Card.calculate_joker(p, context)
			if type(ret) == "table" then
				for k, v in pairs(ret) do enh[k] = v end
			end
		end)
		return next(enh) and enh or nil
	end

	local effects, triggered = {}, nil
	each_sub(card, function(p)
		local ret, trig = Card.calculate_joker(p, context)
		if trig then triggered = true end
		if type(ret) == "table" and next(ret) then
			-- Show messages on the real card, not on the invisible proxy.
			local e = ret
			while type(e) == "table" do
				if e.card == p then e.card = card end
				if e.message_card == p then e.message_card = card end
				e = e.extra
			end
			effects[#effects + 1] = ret
		end
	end)
	if #effects > 0 then return SMODS.merge_effects(effects), triggered end
	return nil, triggered
end

-- Art of Cryptposting's "Всё" (with its floating layer) when available,
-- otherwise the Antimatter Deck.
local has_all_art = next(SMODS.find_mod("cryptposting")) ~= nil

SMODS.Joker({
	key = "all_in_one",
	atlas = has_all_art and "crp_joker" or "cry_atlasdeck",
	prefix_config = { atlas = false },
	pos = has_all_art and { x = 4, y = 7 } or { x = 2, y = 0 },
	soul_pos = has_all_art and { x = 6, y = 7, extra = { x = 5, y = 7 } } or nil,
	rarity = 4,
	cost = 50,
	unlocked = true,
	discovered = true,
	blueprint_compat = true,
	eternal_compat = true,
	perishable_compat = false,
	loc_txt = {
		name = "Все в одном",
		text = {
			"Обладает эффектами",
			"{C:attention}всех остальных джокеров{}",
			"{C:inactive}(джокеров внутри: #1#)",
		},
	},
	in_pool = function() return false end,
	loc_vars = function(self, info_queue, card)
		local subs = subs_by_card[card]
		local n = 0
		if subs then
			for _, p in ipairs(subs.list) do
				if alive(p) then n = n + 1 end
			end
		else
			n = #G.P_CENTER_POOLS.Joker - 1
		end
		return { vars = { n } }
	end,
	add_to_deck = function(self, card, from_debuff)
		if not subs_by_card[card] then build_subs(card, false) end
		apply_add_to_deck(card, from_debuff)
	end,
	remove_from_deck = function(self, card, from_debuff)
		each_sub(card, function(p)
			if p.added_to_deck then Card.remove_from_deck(p, from_debuff) end
		end)
	end,
	calculate = function(self, card, context)
		-- A sub-joker's effect can trigger a nested context; the same card
		-- recalculating inside itself can loop until the game dies.
		if card.hstart_calculating then return end
		card.hstart_calculating = true
		local res = { pcall(calculate_all, self, card, context) }
		card.hstart_calculating = nil
		if not res[1] then error(res[2], 0) end
		return unpack(res, 2)
	end,
})
