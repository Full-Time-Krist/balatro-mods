--- Antimatter: "Все в одном" joker, Antimatter++ deck and sleeve, antimatter
--- seal/sticker/enhancement/edition/suit and the Equality deck.
--- Uses the "hstart" prefix it had as part of Head Start, so keys and saves
--- stay the same.

local mod = SMODS.current_mod
local cfg = mod.config

SMODS.load_file("all_in_one.lua")()
SMODS.load_file("antimatter.lua")()
SMODS.load_file("equality.lua")()

local AIO = "j_hstart_all_in_one"

-- cfg.all_in_one: every new run starts with "Все в одном".
local back_apply_to_run_ref = Back.apply_to_run
function Back:apply_to_run(...)
	local ret = back_apply_to_run_ref(self, ...)
	if cfg.all_in_one then
		G.E_MANAGER:add_event(Event({
			func = function()
				SMODS.add_card({ key = AIO, edition = "e_negative" })
				return true
			end,
		}))
	end
	return ret
end

-- One-shot request (cfg.grant_all_in_one): on the next run start or continue,
-- replace every joker with "Все в одном".
local start_run_ref = Game.start_run
function Game:start_run(...)
	local ret = start_run_ref(self, ...)
	if cfg.grant_all_in_one then
		cfg.grant_all_in_one = false
		SMODS.save_mod_config(mod)
		G.E_MANAGER:add_event(Event({
			func = function()
				local jokers = {}
				for i, card in ipairs(G.jokers.cards) do jokers[i] = card end
				for _, card in ipairs(jokers) do
					card:remove()
				end
				SMODS.add_card({ key = AIO, edition = "e_negative" })
				return true
			end,
		}))
	end
	return ret
end

mod.config_tab = function()
	return {
		n = G.UIT.ROOT,
		config = { align = "cm", padding = 0.1, r = 0.1, colour = G.C.BLACK },
		nodes = {
			{
				n = G.UIT.R,
				config = { align = "cm" },
				nodes = {
					create_toggle({ label = "Все в одном на старте", ref_table = cfg, ref_value = "all_in_one", col = true }),
				},
			},
		},
	}
end
