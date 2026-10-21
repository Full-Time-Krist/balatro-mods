--- Head Start: configurable bonuses applied at the start of every new run, on any deck.

local mod = SMODS.current_mod
local cfg = mod.config

local RARITIES = {
	{ key = "Common", label = "Обычный" },
	{ key = "Uncommon", label = "Необычный" },
	{ key = "Rare", label = "Редкий" },
	{ key = "cry_epic", label = "Эпический" },
	{ key = "Legendary", label = "Легендарный" },
	{ key = "cry_exotic", label = "Экзотический" },
}

local VOUCHER_SETS = {
	{ label = "Нет", keys = {} },
	{
		label = "Базовые",
		keys = { "v_overstock_norm", "v_clearance_sale", "v_reroll_surplus", "v_hone", "v_grabber", "v_wasteful" },
	},
	{
		label = "Все улучш.",
		keys = {
			"v_overstock_norm", "v_overstock_plus",
			"v_clearance_sale", "v_liquidation",
			"v_reroll_surplus", "v_reroll_glut",
			"v_hone", "v_glow_up",
			"v_grabber", "v_nacho_tong",
			"v_wasteful", "v_recyclomancy",
			"v_crystal_ball", "v_omen_globe",
			"v_paint_brush", "v_palette",
		},
	},
}

local function plus(v) return "+" .. v end

-- Each setting stores the index of the chosen option in cfg[key].
local SETTINGS = {
	{ key = "dollars", label = "Деньги", values = { 0, 10, 25, 50, 100, 250, 1000 }, fmt = function(v) return "+$" .. v end },
	{ key = "hands", label = "Руки", values = { 0, 1, 2, 3, 5 }, fmt = plus },
	{ key = "discards", label = "Сбросы", values = { 0, 1, 2, 3, 5 }, fmt = plus },
	{ key = "hand_size", label = "Размер руки", values = { 0, 1, 2, 3, 5 }, fmt = plus },
	{ key = "joker_slots", label = "Слоты джокеров", values = { 0, 1, 2, 3, 5 }, fmt = plus },
	{ key = "consumable_slots", label = "Слоты расходников", values = { 0, 1, 2, 3 }, fmt = plus },
	{ key = "joker_count", label = "Джокеры на старте", values = { 0, 1, 2, 3, 5 }, fmt = tostring },
	{ key = "joker_rarity", label = "Редкость джокеров", values = RARITIES, fmt = function(v) return v.label end },
	{ key = "spectrals", label = "Спектральные карты", values = { 0, 1, 2, 3 }, fmt = tostring },
	{ key = "codes", label = "Карты кода (Cryptid)", values = { 0, 1, 2, 3 }, fmt = tostring },
	{ key = "vouchers", label = "Ваучеры", values = VOUCHER_SETS, fmt = function(v) return v.label end },
}

local SETTINGS_BY_KEY = {}
for _, s in ipairs(SETTINGS) do SETTINGS_BY_KEY[s.key] = s end

local function value(key)
	local s = SETTINGS_BY_KEY[key]
	local idx = math.max(1, math.min(cfg[key] or 1, #s.values))
	return s.values[idx]
end

local function apply_head_start()
	if not cfg.enabled or G.GAME.hstart_applied then return end
	G.GAME.hstart_applied = true

	local sp = G.GAME.starting_params
	sp.dollars = sp.dollars + value("dollars")
	sp.hands = sp.hands + value("hands")
	sp.discards = sp.discards + value("discards")
	sp.hand_size = sp.hand_size + value("hand_size")
	sp.joker_slots = sp.joker_slots + value("joker_slots")
	sp.consumable_slots = sp.consumable_slots + value("consumable_slots")

	for _, v in ipairs(value("vouchers").keys) do
		if G.P_CENTERS[v] and not G.GAME.used_vouchers[v] then
			G.GAME.used_vouchers[v] = true
			G.GAME.starting_voucher_count = (G.GAME.starting_voucher_count or 0) + 1
			G.E_MANAGER:add_event(Event({
				func = function()
					Card.apply_to_run(nil, G.P_CENTERS[v])
					return true
				end,
			}))
		end
	end

	local rarity = value("joker_rarity").key
	-- Epic/Exotic only exist with Cryptid loaded
	if rarity:find("^cry_") and not G.P_JOKER_RARITY_POOLS[rarity] then rarity = "Rare" end
	local jokers, spectrals = value("joker_count"), value("spectrals")
	local codes = SMODS.ConsumableTypes.Code and value("codes") or 0

	delay(0.4)
	G.E_MANAGER:add_event(Event({
		func = function()
			for _ = 1, jokers do
				SMODS.add_card({
					set = "Joker",
					rarity = rarity,
					key_append = "hstart",
					edition = cfg.negative_jokers and "e_negative" or nil,
				})
			end
			for _ = 1, spectrals do
				SMODS.add_card({ set = "Spectral", area = G.consumeables, key_append = "hstart" })
			end
			for _ = 1, codes do
				SMODS.add_card({ set = "Code", area = G.consumeables, key_append = "hstart" })
			end
			return true
		end,
	}))
end

-- apply_to_run only runs for fresh runs (not when continuing a save),
-- after the stake modifiers and before starting_params are consumed.
local back_apply_to_run_ref = Back.apply_to_run
function Back:apply_to_run(...)
	local ret = back_apply_to_run_ref(self, ...)
	apply_head_start()
	return ret
end

G.FUNCS.hstart_cycle = function(args)
	cfg[args.cycle_config.hstart_key] = args.to_key
	SMODS.save_mod_config(mod)
end

local function cycle(s)
	local options = {}
	for i, v in ipairs(s.values) do options[i] = s.fmt(v) end
	return create_option_cycle({
		label = s.label,
		options = options,
		current_option = math.max(1, math.min(cfg[s.key] or 1, #options)),
		opt_callback = "hstart_cycle",
		hstart_key = s.key,
		colour = G.C.RED,
		w = 3,
		scale = 0.8,
		text_scale = 0.45,
	})
end

local function column(from, to)
	local nodes = {}
	for i = from, to do
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = { cycle(SETTINGS[i]) } }
	end
	return { n = G.UIT.C, config = { align = "tm", padding = 0.1 }, nodes = nodes }
end

mod.config_tab = function()
	local split = math.ceil(#SETTINGS / 2)
	return {
		n = G.UIT.ROOT,
		config = { align = "cm", padding = 0.1, r = 0.1, colour = G.C.BLACK },
		nodes = {
			{
				n = G.UIT.R,
				config = { align = "cm" },
				nodes = {
					create_toggle({ label = "Включено", ref_table = cfg, ref_value = "enabled", col = true }),
					create_toggle({ label = "Негативные джокеры", ref_table = cfg, ref_value = "negative_jokers", col = true }),
				},
			},
			{
				n = G.UIT.R,
				config = { align = "cm" },
				nodes = { column(1, split), column(split + 1, #SETTINGS) },
			},
			{
				n = G.UIT.R,
				config = { align = "cm", padding = 0.05 },
				nodes = {
					{ n = G.UIT.T, config = { text = "Применяется к новым забегам", scale = 0.35, colour = G.C.UI.TEXT_INACTIVE } },
				},
			},
		},
	}
end
