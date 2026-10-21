--- Equality Deck: every card in the deck has the rank picked on the run setup
--- screen (suits stay as usual).

local DECK = "b_hstart_equality"

SMODS.Back({
	key = "equality",
	atlas = "centers",
	prefix_config = { atlas = false },
	pos = { x = 1, y = 3 },
	unlocked = true,
	discovered = true,
	loc_txt = {
		name = "Колода равенства",
		text = {
			"У всех карт колоды",
			"{C:attention}одинаковое значение{},",
			"выбранное перед забегом",
		},
	},
	apply = function(self, back)
		local rank = G.GAME.hstart_equality_rank
		if not SMODS.Ranks[rank or ""] then rank = "Ace" end
		G.E_MANAGER:add_event(Event({
			func = function()
				for _, card in ipairs(G.playing_cards) do
					SMODS.change_base(card, nil, rank)
				end
				return true
			end,
		}))
	end,
})

SMODS.RunSelectPage({
	key = "equality_rank",
	include_deck_preview = true,
	page = 2,
	area_type = "deck",
	random_select = true,
	generate_pool = function(self)
		local pool = {}
		for _, key in ipairs(SMODS.Rank.obj_buffer) do
			pool[#pool + 1] = SMODS.Ranks[key]
		end
		return pool
	end,
	optional = function(self)
		return SMODS.RunSelect.Setup.choices.deck_choice == DECK
	end,
	quick_start_text = function()
		local last = G.PROFILES[G.SETTINGS.profile].last_choices
		if last.deck_choice ~= DECK then return end
		if not SMODS.Ranks[last.hstart_equality_rank or ""] then last.hstart_equality_rank = "Ace" end
		return localize(last.hstart_equality_rank, "ranks")
	end,
	set_default = function(self, choice)
		return SMODS.Ranks[choice or ""] and choice or "Ace"
	end,
	selected_text = function(self, selection)
		if selection then return localize(selection, "ranks") end
	end,
	create_selection_card = function(self, rank, card_number, area)
		local card = Card(area.T.x, area.T.y, G.CARD_W, G.CARD_H, nil, G.P_CENTERS.c_base)
		card.no_ui = true
		card.ability.hstart_rank_choice = rank
		SMODS.change_base(card, "Spades", rank)
		return card
	end,
	handle_choice = function(self, choice, remove)
		if remove then
			SMODS.RunSelect.Setup.choices[self.key] = nil
		else
			-- choose_random passes a bare {config = {center = {key = ...}}}.
			SMODS.RunSelect.Setup.choices[self.key] = choice.ability and choice.ability.hstart_rank_choice
				or choice.config.center.key
		end
	end,
	-- The default picks only pool entries with .unlocked, which ranks lack.
	choose_random = function(self)
		local options = {}
		for _, rank in ipairs(self.pool) do options[#options + 1] = rank.key end
		play_sound("whoosh1", math.random() * 0.2 + 0.99, 0.35)
		self:handle_choice({ config = { center = { key = pseudorandom_element(options, pseudoseed(os.time())) } } })
	end,
	start_run = function(self, choice)
		G.GAME.hstart_equality_rank = choice
	end,
})
