--- Antimatter set: a deck, seal, sticker, enhancement, edition and sleeve that
--- each combine every other object of their kind.

local AM_COLOUR = HEX("9B5DE5")

SMODS.Atlas({ key = "antimatter", path = "hstart_antimatter.png", px = 71, py = 95 })

local function collect(effects, ret, card)
	if type(ret) == "table" and next(ret) then
		ret.card = ret.card or card
		effects[#effects + 1] = ret
	end
end

local function merged(effects)
	if #effects > 0 then return SMODS.merge_effects(effects) end
end

-- The combined seal/edition can create cards, whose emplace context makes
-- every antimatter card calculate again, and so on until the game dies.
-- While one of them is calculating, nested calls of the same kind do nothing.
local busy = {}
local function guarded(kind, fn, ...)
	if busy[kind] then return end
	busy[kind] = true
	local res = { pcall(fn, ...) }
	busy[kind] = nil
	if not res[1] then error(res[2], 0) end
	return unpack(res, 2)
end

---------------------------------------------------------------------------
-- Deck: Antimatter with every compatible deck selected, plus "Все в одном".
---------------------------------------------------------------------------
-- G.P_CENTERS is only filled at injection; the registered object exists now.
local am = Cryptid and SMODS.Centers.b_cry_antimatter
if am then
	-- {run setup page suffix, G.GAME.cry_selected_* suffix} -> choice
	local EDECK_CHOICES = {
		[{ "ed", "edition" }] = "e_hstart_antimatter",
		[{ "enh", "enhancement" }] = "m_hstart_antimatter",
		[{ "sk", "sticker" }] = "hstart_antimatter",
		[{ "st", "suit" }] = "hstart_Antimatter",
		[{ "sl", "seal" }] = "hstart_antimatter",
	}

	local function all_decks()
		local decks = {}
		for _, c in ipairs(G.P_CENTER_POOLS.Back) do
			if c.key ~= am.key and c.key ~= "b_hstart_antimatter_plus" and Cryptid.antimatter_compat(c.key, true) then
				decks[c.key] = true
			end
		end
		return decks
	end

	SMODS.Back({
		key = "antimatter_plus",
		atlas = "cry_atlasdeck",
		prefix_config = { atlas = false },
		pos = { x = 2, y = 0 },
		unlocked = true,
		discovered = true,
		config = copy_table(am.config),
		loc_txt = {
			name = "Антиматерия++",
			text = {
				"Колода {C:attention}Антиматерии{} со",
				"{C:attention}всеми{} колодами сразу",
				"Старт с джокером {C:dark_edition}Все в одном{}",
			},
		},
		apply = function(self, back)
			-- Antimatter reads the decks picked on its run setup page, which is
			-- only shown for the original deck: select every deck here instead.
			local decks = all_decks()
			SMODS.RunSelect.Setup.choices.cry_antimatter = decks
			G.GAME.cry_antimatter_decks = SMODS.shallow_copy(decks)
			-- Cryptid's Edition/Enhancement/Sticker/Suit/Seal decks use the
			-- antimatter versions from this mod.
			for kind, choice in pairs(EDECK_CHOICES) do
				SMODS.RunSelect.Setup.choices["cry_edeck_" .. kind[1]] = choice
				G.GAME["cry_selected_" .. kind[2]] = choice
			end
			-- Until the first blind, no joker but "Все в одном" may join the run.
			G.GAME.hstart_aio_only = true
			am.apply(am, back)
			G.E_MANAGER:add_event(Event({
				func = function()
					SMODS.add_card({ key = "j_hstart_all_in_one", edition = "e_negative" })
					return true
				end,
			}))
		end,
		calculate = function(self, back, context)
			return am.calculate(am, back, context)
		end,
	})
end

-- While G.GAME.hstart_aio_only is set (start of an Antimatter++ run), other
-- jokers neither apply their add_to_deck effects nor get emplaced.
local AIO = "j_hstart_all_in_one"
local function blocked_joker(card)
	return G.GAME and G.GAME.hstart_aio_only and not card.hstart_proxy
		and card.ability and card.ability.set == "Joker"
		and card.config and card.config.center and card.config.center.key ~= AIO
end

local add_to_deck_ref = Card.add_to_deck
function Card:add_to_deck(...)
	if blocked_joker(self) then return end
	return add_to_deck_ref(self, ...)
end

local emplace_ref = CardArea.emplace
function CardArea:emplace(card, ...)
	if card and self == G.jokers and blocked_joker(card) then
		card:remove()
		return
	end
	return emplace_ref(self, card, ...)
end

local set_blind_ref = Blind.set_blind
function Blind:set_blind(blind, ...)
	-- start_run calls set_blind(nil) to reset; only a real blind ends the block.
	if blind and G.GAME then G.GAME.hstart_aio_only = nil end
	return set_blind_ref(self, blind, ...)
end

---------------------------------------------------------------------------
-- Seal: every seal at once. The card briefly wears each seal (with that
-- seal's own saved ability) while its effect is evaluated.
---------------------------------------------------------------------------
local SEAL = "hstart_antimatter"

local function each_seal(card, fn)
	local own_seal, own_ability = card.seal, card.ability.seal
	card.ability.hstart_seals = card.ability.hstart_seals or {}
	for _, obj in ipairs(G.P_CENTER_POOLS.Seal) do
		local key = obj.key
		if key ~= SEAL then
			local ab = card.ability.hstart_seals[key]
			if not ab then
				ab = {}
				for k, v in pairs(obj.config or {}) do
					ab[k] = type(v) == "table" and copy_table(v) or v
				end
				card.ability.hstart_seals[key] = ab
			end
			card.seal, card.ability.seal = key, ab
			local ok, err = pcall(fn, key, obj)
			if not ok then sendWarnMessage(("Antimatter seal, %s: %s"):format(key, tostring(err)), "Antimatter") end
		end
	end
	card.seal, card.ability.seal = own_seal, own_ability
end

SMODS.Seal({
	key = "antimatter",
	atlas = "hstart_antimatter",
	pos = { x = 0, y = 0 },
	badge_colour = AM_COLOUR,
	weight = 1,
	loc_txt = {
		name = "Печать антиматерии",
		label = "Печать антиматерии",
		text = { "Обладает эффектами", "{C:attention}всех печатей{}" },
	},
	calculate = function(self, card, context)
		return guarded("seal", function()
			local effects, triggered = {}, nil
			each_seal(card, function()
				local ret, trig = card:calculate_seal(context)
				if trig then triggered = true end
				collect(effects, ret, card)
			end)
			return merged(effects), triggered
		end)
	end,
	get_p_dollars = function(self, card)
		local total = 0
		each_seal(card, function(key, obj)
			if obj.get_p_dollars then
				total = total + obj:get_p_dollars(card)
			elseif key == "Gold" then
				total = total + 3
			end
		end)
		return total
	end,
})

-- Blue seal is hardcoded in the end of round effect, outside calculate_seal.
local end_of_round_ref = Card.get_end_of_round_effect
function Card:get_end_of_round_effect(...)
	if self.seal ~= SEAL then return end_of_round_ref(self, ...) end
	self.seal = "Blue"
	local ok, ret = pcall(end_of_round_ref, self, ...)
	self.seal = SEAL
	if not ok then error(ret, 0) end
	return ret
end

---------------------------------------------------------------------------
-- Sticker: applying it applies every other sticker.
---------------------------------------------------------------------------
-- Entropy's "link" gives every card the same link id, after which Entropy
-- mirrors each change of one card onto all others: on a whole deck that
-- loops until the game dies. Entropy's "desync" force-triggers the card on a
-- random context; on a joker that creates cards (e.g. Code Joker) the new
-- card's emplace context triggers it again, endlessly.
local STICKER_SKIP = { link = true, desync = true }

SMODS.Sticker({
	key = "antimatter",
	atlas = "hstart_antimatter",
	pos = { x = 1, y = 0 },
	badge_colour = AM_COLOUR,
	rate = 0.02,
	sets = { Joker = true },
	needs_enable_flag = false,
	loc_txt = {
		name = "Наклейка антиматерии",
		label = "Наклейка антиматерии",
		text = { "Обладает эффектами", "{C:attention}всех наклеек{}" },
	},
	apply = function(self, card, val)
		card.ability[self.key] = val
		-- A sticker's apply can change the card again and come back here.
		if card.hstart_applying_stickers then return end
		card.hstart_applying_stickers = true
		for key, s in pairs(SMODS.Stickers) do
			if key ~= self.key and not STICKER_SKIP[key] then
				local ok, err = pcall(s.apply, s, card, val)
				if not ok then sendWarnMessage(("Antimatter sticker, %s: %s"):format(key, tostring(err)), "Antimatter") end
			end
		end
		card.hstart_applying_stickers = nil
	end,
})

---------------------------------------------------------------------------
-- Enhancement: counts as every enhancement (Steamodded quantum enhancements).
---------------------------------------------------------------------------
local ENH = "m_hstart_antimatter"

-- Art of Entropy's Prismatic card when available.
local has_prismatic = next(SMODS.find_mod("entr")) ~= nil

SMODS.Enhancement({
	key = "antimatter",
	atlas = has_prismatic and "entr_enhancements" or "cry_atlasdeck",
	prefix_config = { atlas = false },
	pos = has_prismatic and { x = 0, y = 1 } or { x = 2, y = 0 },
	weight = 1,
	loc_txt = {
		name = "Улучшение антиматерии",
		text = { "Считается картой", "со {C:attention}всеми улучшениями{}" },
	},
})

local get_enhancements_ref = SMODS.get_enhancements
function SMODS.get_enhancements(card, extra_only)
	local ret = get_enhancements_ref(card, extra_only) or {}
	if card.config and card.config.center and card.config.center.key == ENH then
		for _, e in ipairs(G.P_CENTER_POOLS.Enhanced) do
			if e.key ~= ENH then ret[e.key] = true end
		end
	end
	return ret
end

---------------------------------------------------------------------------
-- Edition: every edition at once, plus a slot like Negative.
---------------------------------------------------------------------------
local EDITION = "e_hstart_antimatter"

local function edition_data(e)
	local data = {}
	for k, v in pairs(e.config or {}) do
		data[k] = type(v) == "table" and copy_table(v) or v
	end
	local t = e.key:sub(3)
	data[t], data.type, data.key = true, t, e.key
	return data
end

SMODS.Edition({
	key = "antimatter",
	shader = "cry_astral",
	prefix_config = { shader = false },
	config = { card_limit = 1 },
	in_shop = true,
	weight = 1,
	extra_cost = 10,
	sound = { sound = "negative", per = 1.5, vol = 0.4 },
	get_weight = function(self) return self.weight end,
	loc_txt = {
		name = "Антиматерия",
		label = "Антиматерия",
		text = { "Обладает эффектами", "{C:attention}всех изданий{}", "{C:dark_edition}+1{} слот" },
	},
	on_apply = function(card)
		-- Code that checks card.edition.holo, .polychrome, ... sees them all.
		for _, e in ipairs(G.P_CENTER_POOLS.Edition) do
			if e.key ~= "e_base" and e.key ~= EDITION then card.edition[e.key:sub(3)] = true end
		end
	end,
	calculate = function(self, card, context)
		return guarded("edition", function()
			local own = card.edition
			own.hstart_subs = own.hstart_subs or {}
			local effects = {}
			for _, e in ipairs(G.P_CENTER_POOLS.Edition) do
				if e.key ~= "e_base" and e.key ~= EDITION and type(e.calculate) == "function" then
					own.hstart_subs[e.key] = own.hstart_subs[e.key] or edition_data(e)
					card.edition = own.hstart_subs[e.key]
					local ok, ret = pcall(e.calculate, e, card, context)
					card.edition = own
					if ok then
						collect(effects, ret, card)
					else
						sendWarnMessage(("Antimatter edition, %s: %s"):format(e.key, tostring(ret)), "Antimatter")
					end
				end
			end
			return merged(effects)
		end)
	end,
})

---------------------------------------------------------------------------
-- Sleeve: every sleeve at once.
---------------------------------------------------------------------------
if CardSleeves then
	local SLEEVE = "sleeve_hstart_antimatter"

	local function each_sleeve(fn)
		for _, s in ipairs(G.P_CENTER_POOLS.Sleeve) do
			if s.key ~= SLEEVE and s.key ~= "sleeve_casl_none" then
				local ok, err = pcall(fn, s)
				if not ok then sendWarnMessage(("Antimatter sleeve, %s: %s"):format(s.key, tostring(err)), "Antimatter") end
			end
		end
	end

	CardSleeves.Sleeve({
		key = "antimatter",
		atlas = "cry_atlasSleeves",
		prefix_config = { atlas = false },
		pos = { x = 0, y = 1 },
		unlocked = true,
		discovered = true,
		loc_txt = {
			name = "Рукав антиматерии++",
			text = { "Обладает эффектами", "{C:attention}всех рукавов{}" },
		},
		apply = function(self, sleeve)
			each_sleeve(function(s)
				if s.loc_vars then s:loc_vars() end
				s:apply(s)
			end)
		end,
		trigger_effect = function(self, args)
			each_sleeve(function(s)
				if s.trigger_effect ~= CardSleeves.Sleeve.trigger_effect then s:trigger_effect(args) end
			end)
		end,
		calculate = function(self, sleeve, context)
			-- Deprecated final_scoring_step passes chips/mult along as return values.
			if context.context == "final_scoring_step" then
				each_sleeve(function(s)
					if type(s.calculate) == "function" then
						local chips, mult = s:calculate(s, context)
						context.chips, context.mult = chips or context.chips, mult or context.mult
					end
				end)
				return context.chips, context.mult
			end
			local effects = {}
			each_sleeve(function(s)
				if type(s.calculate) == "function" then collect(effects, (s:calculate(s, context))) end
			end)
			return merged(effects)
		end,
		calc_dollar_bonus = function(self, sleeve)
			local total = 0
			each_sleeve(function(s)
				if s.calc_dollar_bonus then total = total + (s:calc_dollar_bonus(s) or 0) end
			end)
			return total > 0 and total or nil
		end,
	})
end

---------------------------------------------------------------------------
-- Suit: a card of this suit counts as every suit.
---------------------------------------------------------------------------
local SUIT = "hstart_Antimatter"

SMODS.Atlas({ key = "suit_cards", path = "hstart_suit_cards.png", px = 71, py = 95 })
SMODS.Atlas({ key = "suit_ui", path = "hstart_suit_ui.png", px = 18, py = 18 })

SMODS.Suit({
	key = "Antimatter",
	card_key = "HSAM",
	lc_atlas = "hstart_suit_cards",
	hc_atlas = "hstart_suit_cards",
	lc_ui_atlas = "hstart_suit_ui",
	hc_ui_atlas = "hstart_suit_ui",
	pos = { y = 0 },
	ui_pos = { x = 0, y = 0 },
	lc_colour = AM_COLOUR,
	hc_colour = AM_COLOUR,
	loc_txt = {
		singular = "Антиматерия",
		plural = "Антиматерия",
	},
	-- Not in starting decks; can show up on new cards (packs, spectrals, ...).
	in_pool = function(self, args)
		return not (args and args.initial_deck)
	end,
})

local is_suit_ref = Card.is_suit
function Card:is_suit(suit, bypass_debuff, flush_calc)
	if self.base and self.base.suit == SUIT and not SMODS.has_no_suit(self) and (bypass_debuff or not self.debuff) then
		return true
	end
	return is_suit_ref(self, suit, bypass_debuff, flush_calc)
end
