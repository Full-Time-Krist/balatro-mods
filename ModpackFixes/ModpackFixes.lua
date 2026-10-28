--- Modpack Fixes: compatibility fixes for this modpack.
--- Priority 1000 makes this load after Entropy (666) and Ortalab (0), so the
--- hooks below wrap or replace theirs.

-- 1. Tutorials.
-- A fresh profile can have tutorial_complete unset with no tutorial_progress,
-- which crashes the blind select screen. Treat the tutorial as skipped then.
local blind_choice_handler_ref = G.FUNCS.blind_choice_handler
G.FUNCS.blind_choice_handler = function(e)
	if not G.SETTINGS.tutorial_complete and not G.SETTINGS.tutorial_progress then
		G.SETTINGS.tutorial_complete = true
	end
	if not G.SETTINGS.entropy_tutorial_complete and not G.SETTINGS.entropy_tutorial_progress then
		G.SETTINGS.entropy_tutorial_complete = true
	end
	return blind_choice_handler_ref(e)
end

-- While Entropy's tutorial is unfinished its Play button skips deck selection
-- and forces the tutorial run. Mark it done so Play opens the run setup.
local main_menu_buttons_ref = create_UIBox_main_menu_buttons
function create_UIBox_main_menu_buttons(...)
	if not G.SETTINGS.entropy_tutorial_complete then
		G.SETTINGS.entropy_tutorial_complete = true
		G:save_settings()
	end
	return main_menu_buttons_ref(...)
end

-- 2. Entropy hooks CardArea:remove_card and reads card.config.center, but some
-- jokers (Cryptid, MoreFluff) call G.jokers:remove_card(self) with their
-- center instead of the card. Such an object is never in the area, so skip it.
local remove_card_ref = CardArea.remove_card
function CardArea:remove_card(card, ...)
	if card and not (card.config and card.config.center) then return end
	return remove_card_ref(self, card, ...)
end

-- 3. Entropy gives its stakes a fixed order 1-6 with no above_stake, so they
-- tie with the vanilla stakes and sorting can put Zenith in White's slot
-- (+15 ante, Brimstone blinds). Chain them after Gold instead.
local entropy_stakes = {
	{ "stake_entr_copper", "stake_gold" },
	{ "stake_entr_platinum", "stake_entr_copper" },
	{ "stake_entr_meteorite", "stake_entr_platinum" },
	{ "stake_entr_obsidian", "stake_entr_meteorite" },
	{ "stake_entr_iridium", "stake_entr_obsidian" },
	{ "stake_entr_zenith", "stake_entr_iridium" },
	{ "stake_entr_gfb", "stake_entr_zenith" },
}
for _, v in ipairs(entropy_stakes) do
	local stake = SMODS.Stakes[v[1]]
	if stake then
		stake.order = nil
		stake.above_stake = v[2]
	end
end

-- 4. Ortalab's blind mod badge assumes its HUD nodes exist; with other mods
-- changing the HUD they may not, which crashes when a modded blind starts.
if G.FUNCS.HUD_blind_badge then
	G.FUNCS.HUD_blind_badge = function(e)
		if not G.GAME.blind.in_blind then return end
		local mod = G.GAME.blind.config.blind.mod
		if not mod then
			e.states.visible = false
			return
		end
		e.states.visible = true
		local name = string.sub(mod.display_name, 1, 20)
		if Ortalab.config.reduced_mod_badge and e.children[2] then
			e.children[2].config.text = name
			e.children[2].config.colour = mod.badge_colour
		elseif e.children[1] and e.children[1].children[1] then
			local badge = e.children[1].children[1]
			badge.config.colour = mod.badge_colour
			if G.GAME.blind_badge then G.GAME.blind_badge.name = name end
			local text = badge.children[2]
			if text and text.config.object then
				text.config.object.colours = { mod.badge_text_colour or G.C.WHITE }
			end
		end
	end
end

-- 5. Ortalab's dragon coupons recolour sprites by a random boss blind. Created
-- at odd moments (e.g. as a deck card at run start) the boss key can be
-- missing from G.P_BLINDS or have no boss_colour, which crashes. Fall back
-- to vanilla bosses.
for _, key in ipairs({ "v_ortalab_seed_inv", "v_ortalab_tree_inv" }) do
	local coupon = SMODS.Centers[key]
	if coupon and coupon.create_sprites then
		local create_sprites_ref = coupon.create_sprites
		coupon.create_sprites = function(self, card)
			local extra = card.ability and card.ability.extra
			local function usable(k) return G.P_BLINDS[k or ""] and G.P_BLINDS[k].boss_colour end
			if type(extra) == "table" then
				if not usable(extra.left_dragon) then extra.left_dragon = "bl_hook" end
				if not usable(extra.right_dragon) then extra.right_dragon = "bl_final_leaf" end
			end
			return create_sprites_ref(self, card)
		end
	end
end


-- 6. Cryptid's "Crash" code card fakes crashes for real: it replaces the error
-- handler with a no-op (the game then closes silently) or spawns ever more
-- Crash cards until the game dies. "Все в одном" and HeadStart can use or
-- create code cards automatically, so make it harmless.
local crash = SMODS.Centers.c_cry_crash
if crash then
	crash.use = function(self, card, area, copier)
		card_eval_status_text(copier or card, "extra", nil, nil, nil, { message = "Crash!", colour = G.C.RED })
	end
	crash.force_use = function(self, card, area)
		self:use(card, area)
	end
end

-- 7. Ortalab's "Edition+" utility card looks up G.P_CENTERS[edition] for a
-- polled edition. In heavily modded runs (e.g. Misprint changing values on
-- set_cost) the key can end up invalid, which crashes. Same logic, guarded.
local edition_plus = SMODS.Centers["c_ortalab_edition_+"]
if edition_plus then
	local function valid_edition(e)
		if type(e) == "table" then e = e.key or (e.type and "e_" .. e.type) end
		return G.P_CENTERS[e or ""] and e or "e_foil"
	end
	edition_plus.set_ability = function(self, card, from_debuff)
		card.ability.extra = type(card.ability.extra) == "table" and card.ability.extra or { selected = 1 }
		card.ability.extra.edition = valid_edition(poll_edition("ortalab_edition_+", nil, nil, true))
		card:set_cost()
		card.ability.extra.edition = valid_edition(card.ability.extra.edition)
		local edition = G.P_CENTERS[card.ability.extra.edition]
		card.base_cost = 5 + 3 * (tonumber(edition.extra_cost) or 0)
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.2,
			func = function()
				local sound = edition.sound
				if sound and sound.sound then play_sound(sound.sound, sound.per, sound.vol) end
				card:juice_up(1, 0.5)
				return true
			end,
		}))
	end
end

-- 8. A handler of the modify_weights context (sent while building a random
-- pool) may itself build a pool, which sends modify_weights again. With many
-- such handlers (e.g. Antimatter++ with every deck) this recursed ~500 levels
-- deep and killed the game silently. Nested modify_weights is never needed.
local in_modify_weights = false
local calculate_context_ref = SMODS.calculate_context
function SMODS.calculate_context(context, return_table, ...)
	if context and context.modify_weights then
		if in_modify_weights then return return_table or {} end
		in_modify_weights = true
		local res = { xpcall(calculate_context_ref, function(err) --MPFIX_DIAG
			if mpfix_diag_traceback then mpfix_diag_traceback(err) end --MPFIX_DIAG
			return err --MPFIX_DIAG
		end, context, return_table, ...) } --MPFIX_DIAG
		in_modify_weights = false
		if not res[1] then error(res[2], 0) end
		return unpack(res, 2)
	end
	return calculate_context_ref(context, return_table, ...)
end

-- 9. Sound runs in a separate thread that only understands plain numbers.
-- Some effects pass Talisman big numbers (tables) as volume/pitch, which kills
-- the sound thread and the game. Convert them before sending.
local function plain_number(v)
	if type(v) == "table" then
		v = (to_number and to_number(v)) or tonumber(tostring(v))
	end
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
	return v
end
local play_sound_ref = play_sound
function play_sound(sound_code, per, vol, ...)
	local pitch_mod = G.PITCH_MOD
	if pitch_mod ~= nil then G.PITCH_MOD = plain_number(pitch_mod) or 1 end
	local ret = play_sound_ref(sound_code, plain_number(per), plain_number(vol), ...)
	G.PITCH_MOD = pitch_mod
	return ret
end

-- 10. Entropy.rubber_ball_scoring(cards) iterates cards without a nil check;
-- some scoring paths pass nil. Treat it as no cards.
if Entropy and Entropy.rubber_ball_scoring then
	local rubber_ball_scoring_ref = Entropy.rubber_ball_scoring
	function Entropy.rubber_ball_scoring(cards, ...)
		return rubber_ball_scoring_ref(cards or {}, ...)
	end
end

-- 11. SMODS.in_scoring(card, scoring_hand) is also reached with a nil
-- scoring hand in heavily modded runs (same cause as #10). No hand means the
-- card is not scoring.
local in_scoring_ref = SMODS.in_scoring
function SMODS.in_scoring(card, scoring_hand, ...)
	if not scoring_hand then return nil end
	return in_scoring_ref(card, scoring_hand, ...)
end

-- 12. Entropy counts shop rerolls in current_round.times_rerolled but only
-- resets it in end_round, so it is nil until the first round of a run ends
-- (or in a run saved before Entropy was added) and rerolling crashes.
local reroll_shop_ref = G.FUNCS.reroll_shop
G.FUNCS.reroll_shop = function(e)
	local round = G.GAME and G.GAME.current_round
	if round and type(round.times_rerolled) ~= "number" then round.times_rerolled = 0 end
	return reroll_shop_ref(e)
end

-- 13. Cryptid's Abstract enhancement reads card.ability.extra in calculate.
-- Quantum enhancement checks (e.g. Paperback's Sleeved) can run it while the
-- card is still being turned Abstract and extra is not set yet. Skip until it is.
local abstract = SMODS.Centers.m_cry_abstract
if abstract and abstract.calculate then
	local abstract_calculate_ref = abstract.calculate
	abstract.calculate = function(self, card, context)
		if not (card and card.ability and type(card.ability.extra) == "table") then return end
		return abstract_calculate_ref(self, card, context)
	end
end

-- 14. Cryptid's Rigged sticker (from ://SEED) now only doubles the odds
-- (1 in 7 -> 2 in 7). Restore the old behaviour: listed odds are guaranteed.
local rigged = SMODS.Stickers.cry_rigged
if rigged then
	rigged.calculate = function(self, card, context)
		if context.mod_probability and context.trigger_obj == card then
			return {
				numerator = context.denominator,
			}
		end
	end
end

-- 15. joker_buffer / consumeable_buffer reserve slots for cards that are about
-- to be created and should drop back to 0 once they are. Some effect in this
-- modpack raises them without lowering them, and the run save keeps the stale
-- value, so "must have room" checks (Copy/Paste, Cartomancer, ...) fail forever.
-- Clear them when a run is loaded and once each round has finished.
local function reset_card_buffers()
	if G.GAME then
		G.GAME.joker_buffer = 0
		G.GAME.consumeable_buffer = 0
	end
end
local buffers_start_run_ref = Game.start_run
function Game:start_run(...)
	local ret = buffers_start_run_ref(self, ...)
	reset_card_buffers()
	return ret
end
local buffers_end_round_ref = end_round
function end_round(...)
	local ret = buffers_end_round_ref(...)
	G.E_MANAGER:add_event(Event({
		func = function()
			reset_card_buffers()
			return true
		end,
	}))
	return ret
end
-- The leak also happens mid-round (e.g. in the shop), so resetting once per
-- round is not enough. A card being created always has a pending event, so a
-- non-zero buffer while the event queue has been empty for a moment is stale.
local stale_buffer_time = 0
local buffers_update_ref = Game.update
function Game:update(dt, ...)
	local ret = buffers_update_ref(self, dt, ...)
	local game = G.GAME
	local queue = G.E_MANAGER and G.E_MANAGER.queues and G.E_MANAGER.queues.base
	if game and queue and ((game.joker_buffer or 0) ~= 0 or (game.consumeable_buffer or 0) ~= 0) and #queue == 0 then
		stale_buffer_time = stale_buffer_time + dt
		if stale_buffer_time > 0.5 then
			print(("MPFIX: reset stale card buffers (jokers %s, consumables %s, state %s)"):format(
				tostring(game.joker_buffer), tostring(game.consumeable_buffer), tostring(G.STATE)))
			reset_card_buffers()
			stale_buffer_time = 0
		end
	else
		stale_buffer_time = 0
	end
	return ret
end

-- 16. SDM_0's Bakery goods (Wedding Cake etc.) are passive and can never be
-- used, but some effects put them in the joker slots, where they sit with a
-- dead Use button. There, Use moves them to the consumable slots instead.
-- add_to_deck/remove_from_deck are not called, so their slot bonuses are kept
-- as they are rather than removed and added again.
local function is_bakery_in_jokers(card)
	return card and G.jokers and card.area == G.jokers and card.ability.consumeable
		and SDM_0s_Stuff_Funcs and SDM_0s_Stuff_Funcs.is_bakery_good(card)
end
local function has_consumable_room(card)
	local negative = card.edition and card.edition.negative
	return negative or #G.consumeables.cards < G.consumeables.config.card_limit
end
local use_and_sell_buttons_ref = G.UIDEF.use_and_sell_buttons
function G.UIDEF.use_and_sell_buttons(card, ...)
	local t = use_and_sell_buttons_ref(card, ...)
	if is_bakery_in_jokers(card) then
		local function retarget(node)
			if type(node) ~= "table" then return end
			if node.config and node.config.func == "can_use_consumeable" then
				node.config.func = "mpfix_can_move_bakery"
			end
			for _, child in ipairs(node.nodes or {}) do retarget(child) end
		end
		retarget(t)
	end
	return t
end
G.FUNCS.mpfix_can_move_bakery = function(e)
	local card = e.config.ref_table
	if is_bakery_in_jokers(card) and G.consumeables and has_consumable_room(card) and not G.CONTROLLER.locked then
		e.config.colour = G.C.RED
		e.config.button = "mpfix_move_bakery"
	else
		e.config.colour = G.C.UI.BACKGROUND_INACTIVE
		e.config.button = nil
	end
end
G.FUNCS.mpfix_move_bakery = function(e)
	local card = e.config.ref_table
	if not is_bakery_in_jokers(card) then return end
	G.jokers:remove_from_highlighted(card, true)
	G.jokers:remove_card(card)
	G.consumeables:emplace(card)
	play_sound("card1", 0.8, 0.6)
end

-- 18. Entropy's #define and Inherit install their collection click handlers in
-- an init function, but Entropy registers them straight through SMODS, which
-- never calls init (only Cryptid's own loader does). So picking a card in the
-- collection just selected it and the menu stayed open. Run init ourselves.
for _, key in ipairs({ "c_entr_define", "c_entr_inherit" }) do
	local center = SMODS.Centers[key]
	if center and type(center.init) == "function" and not center.mpfix_initialized then
		center.mpfix_initialized = true
		center:init()
	end
end

-- 17. Wedding Cake adds its +X joker / consumable slots once, when obtained,
-- and removes the *current* X when lost. Cryptid value changes (e.g.
-- ://MULTIPLY) raise X afterwards, so the card shows +131072 but gives +1, and
-- losing it would take away 131072 slots. Keep the bonus equal to X at all
-- times and remove exactly what was given.
local wedding_cake = SMODS.Centers.c_sdm_wedding_cake
if wedding_cake then
	local function slots_of(card)
		local n = card.ability.extra and card.ability.extra.amount or 0
		n = (to_number and to_number(n)) or tonumber(n) or 0
		if n ~= n or n == math.huge or n == -math.huge then return nil end
		return math.floor(n)
	end
	local function change_slots(diff)
		if diff == 0 then return end
		G.jokers.config.card_limit = G.jokers.config.card_limit + diff
		G.consumeables.config.card_limit = G.consumeables.config.card_limit + diff
	end
	-- Cards from before this fix: assume the amount the card had when obtained.
	local function applied_of(card)
		if card.ability.mpfix_wc_applied then return card.ability.mpfix_wc_applied end
		local base = wedding_cake.config.extra.amount
		return G.GAME.used_vouchers.v_sdm_bakery_factory and base * 2 or base
	end
	wedding_cake.add_to_deck = function(self, card, from_debuff)
		SMODS.Bakery.add_to_deck(self, card, from_debuff)
		if not from_debuff then
			local n = slots_of(card) or 0
			change_slots(n)
			card.ability.mpfix_wc_applied = n
		end
	end
	wedding_cake.remove_from_deck = function(self, card, from_debuff)
		if not from_debuff then
			change_slots(-applied_of(card))
			card.ability.mpfix_wc_applied = 0
		end
	end
	local wc_update_ref = Game.update
	function Game:update(dt, ...)
		local ret = wc_update_ref(self, dt, ...)
		if G.jokers and G.consumeables and G.GAME then
			for _, area in ipairs({ G.jokers, G.consumeables }) do
				for _, card in ipairs(area.cards) do
					if card.config.center == wedding_cake and card.added_to_deck and not card.debuff then
						local want, have = slots_of(card), applied_of(card)
						if want and want ~= have then
							change_slots(want - have)
							card.ability.mpfix_wc_applied = want
						end
					end
				end
			end
		end
		return ret
	end
end

-- 19. Paperback's EGO gift patch for the mouse buttons also lands in
-- G.UIDEF.card_focus_ui (the buttons shown when a card is selected with a
-- gamepad or WASDNav). There it returns a bare UI definition instead of a
-- UIBox, which crashes the card draw, and leaves card.ability.consumeable
-- cleared for good. Do what the patch meant: build the normal focus UI with
-- the gift treated as non-consumable (no Use button).
if G.UIDEF.card_focus_ui then
	local card_focus_ui_ref = G.UIDEF.card_focus_ui
	function G.UIDEF.card_focus_ui(card, ...)
		local ability = card.ability
		local is_ego_gift = PB_UTIL and PB_UTIL.is_ego_gift
		local ret
		if is_ego_gift and ability and is_ego_gift(card) then
			local consumeable = ability.consumeable
			ability.consumeable = nil
			PB_UTIL.is_ego_gift = function() return false end
			local ok, res = pcall(card_focus_ui_ref, card, ...)
			PB_UTIL.is_ego_gift = is_ego_gift
			ability.consumeable = consumeable
			if not ok then error(res, 0) end
			ret = res
		else
			ret = card_focus_ui_ref(card, ...)
		end
		-- Any other patch returning a bare definition: show it as a UIBox.
		if type(ret) == "table" and not ret.VT then
			ret = UIBox({ definition = ret, config = { align = "cr", offset = { x = -0.4, y = 0 }, parent = card } })
		end
		return ret
	end
end

--MPFIX_DIAG_BEGIN (temporary: find out where the game silently closes)
local diag_timer = 0
local diag_update_ref = love.update
function love.update(dt)
	diag_timer = diag_timer + dt
	if diag_timer >= 5 then
		diag_timer = 0
		local page = SMODS.RunSelect and SMODS.RunSelect.Internals and SMODS.RunSelect.Internals.current_page
		print(("MPFIX diag: lua %.0f MB, state %s, run setup page %s, deck %s"):format(
			collectgarbage("count") / 1024, tostring(G.STATE), tostring(page),
			tostring(SMODS.RunSelect and SMODS.RunSelect.Setup and SMODS.RunSelect.Setup.choices and SMODS.RunSelect.Setup.choices.deck_choice)))
	end
	return diag_update_ref(dt)
end
-- Flushed trace of every event run during the first seconds of a run.
local diag_trace_until = 0
local diag_file = io.open(love.filesystem.getSaveDirectory() .. "/mpfix_trace.txt", "w")
function mpfix_diag_traceback(err)
	if not diag_file then return end
	local tb = debug.traceback(tostring(err), 2)
	local n = 0
	for line in tb:gmatch("[^\n]+") do
		n = n + 1
		if n <= 80 or n % 50 == 0 then diag_file:write(line, "\n") end
	end
	diag_file:write("total traceback lines: ", n, "\n")
	diag_file:flush()
end
local function diag_trace(msg)
	if diag_file and G.TIMERS and G.TIMERS.REAL < diag_trace_until then
		diag_file:write(msg, "\n")
		diag_file:flush()
	end
end
local diag_add_event_ref = EventManager.add_event
function EventManager:add_event(event, ...)
	if event and type(event.func) == "function" and not event.mpfix_traced then
		event.mpfix_traced = true
		local info = debug.getinfo(event.func, "S")
		local where = info and (info.short_src .. ":" .. tostring(info.linedefined)) or "?"
		local func = event.func
		event.func = function(...)
			diag_trace("event " .. where)
			return func(...)
		end
	end
	return diag_add_event_ref(self, event, ...)
end
local diag_add_to_deck_ref = Card.add_to_deck
function Card:add_to_deck(...)
	diag_trace("add_to_deck " .. tostring(self.config and self.config.center and self.config.center.key))
	local ret = diag_add_to_deck_ref(self, ...)
	diag_trace("add_to_deck done")
	return ret
end
-- Record deeply nested calculation contexts (runaway recursion).
local diag_ctx_depth = 0
local diag_calc_ref = SMODS.calculate_context
function SMODS.calculate_context(context, ...)
	diag_ctx_depth = diag_ctx_depth + 1
	if diag_ctx_depth >= 15 then
		local keys = {}
		for k in pairs(context or {}) do keys[#keys + 1] = tostring(k) end
		diag_trace(("deep context %d: %s"):format(diag_ctx_depth, table.concat(keys, ",")))
	end
	-- No pcall here: it would add C stack depth itself. An error ends the
	-- game anyway, so a stale counter does not matter.
	local res = { diag_calc_ref(context, ...) }
	diag_ctx_depth = diag_ctx_depth - 1
	return unpack(res)
end
local diag_start_run_ref = Game.start_run
function Game:start_run(args, ...)
	diag_trace_until = (G.TIMERS and G.TIMERS.REAL or 0) + 120
	diag_trace("start_run")
	print("MPFIX diag: start_run begin")
	local ret = diag_start_run_ref(self, args, ...)
	print("MPFIX diag: start_run end")
	return ret
end
local diag_apply_ref = Back.apply_to_run
function Back:apply_to_run(...)
	print("MPFIX diag: apply_to_run " .. tostring(self.effect and self.effect.center and self.effect.center.key))
	local ret = diag_apply_ref(self, ...)
	print("MPFIX diag: apply_to_run done")
	return ret
end
--MPFIX_DIAG_END
