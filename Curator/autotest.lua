--- Curator autotest: a bot that plays runs with random groups of jokers from different mods,
--- uses every consumable on random cards and builds every card's tooltip. Errors inside cards,
--- events and scoring are caught, written to curator_autotest.log and the game keeps going.
--- Started by a "curator_autotest_request" file in the save directory; quits when done.
--- Progress survives a hard crash: curator_autotest_state.lua remembers the position.

local T = {}
local LOG = "curator_autotest.log"
local STATE = "curator_autotest_state.lua"
local GROUP = 5

local seen = {}
local current = "init"
local errors = 0

local function log(line)
	love.filesystem.append(LOG, line .. "\n")
end

local function short_tb(tb)
	local out, prev = {}, {}
	local limit = tostring(tb):find("stack overflow") and 80 or 8
	for l in tostring(tb):gmatch("[^\n]+") do
		if #out >= limit then break end
		if not l:find("autotest.lua") and not l:find("%[C%]: in function 'xpcall'") and not prev[l] then
			out[#out + 1] = l
			if limit > 8 then prev[l] = true end -- recursion: show each frame once
		end
	end
	return table.concat(out, "\n    ")
end

local function report(where, key, err)
	local msg = tostring(err):gsub("\n.*", "")
	local id = where .. "|" .. tostring(key) .. "|" .. msg
	if seen[id] then return end
	seen[id] = true
	errors = errors + 1
	T.recent = (T.recent or 0) + 1
	log(string.format("ERR [%s] key=%s during=%s\n    %s", where, tostring(key), current, short_tb(err)))
end
T.report = report

local function tb(e)
	local out = debug.traceback(e, 2)
	if tostring(e):find("stack overflow") then
		-- LuaJIT cuts the middle of deep tracebacks; list the distinct frames under the recursion
		local frames, seen_f = {}, {}
		for lvl = 2, 30000 do
			local info = debug.getinfo(lvl, "Sln")
			if not info then break end
			local id = info.short_src .. ":" .. (info.currentline or 0)
			if not seen_f[id] then
				seen_f[id] = true
				frames[#frames + 1] = id .. " " .. tostring(info.name)
			end
		end
		out = out .. "\n    distinct frames:\n    " .. table.concat(frames, "\n    ", 1, math.min(#frames, 40))
	end
	return out
end

local function center_key(card)
	return card and card.config and card.config.center and card.config.center.key or "?"
end

-- ---------------------------------------------------------------- guards

local function guard_method(cls, name, fallback)
	local orig = cls[name]
	if type(orig) ~= "function" then return end
	cls[name] = function(self, ...)
		local res = { xpcall(orig, tb, self, ...) }
		if res[1] then return unpack(res, 2) end
		report("Card:" .. name, center_key(self), res[2])
		return fallback
	end
end

local function install_guards()
	for _, name in ipairs({ "calculate_joker", "calculate_seal", "calculate_edition", "calculate_enhancement",
		"use_consumeable", "calculate_dollar_bonus", "add_to_deck", "remove_from_deck", "generate_UIBox_ability_table",
		"update", "draw", "set_ability", "set_edition", "set_seal", "get_chip_bonus", "get_chip_mult",
		"get_chip_x_mult", "get_p_dollars", "redeem", "open", "set_cost", "start_dissolve", "sell_card", "juice_up" }) do
		guard_method(Card, name, nil)
	end
	guard_method(Card, "can_use_consumeable", false)
	-- UI callbacks (e.g. HUD badges) run every frame from UIElement:update
	local ui_update = UIElement.update
	UIElement.update = function(self, dt)
		local ok, err = xpcall(ui_update, tb, self, dt)
		if not ok then report("UIElement:update", self.config and self.config.func or "?", err) end
	end
	guard_method(Card, "can_sell_card", false)

	local init_ref = Event.init
	function Event:init(config)
		init_ref(self, config)
		local f = self.func
		local where = current
		self.func = function(...)
			local res = { xpcall(f, tb, ...) }
			if res[1] then return unpack(res, 2) end
			report("Event", where, res[2])
			return true
		end
	end

	for _, name in ipairs({ "evaluate_play", "draw_from_deck_to_hand", "draw_from_play_to_discard", "draw_from_hand_to_discard" }) do
		local orig = G.FUNCS[name]
		if orig then
			G.FUNCS[name] = function(...)
				local ok, err = xpcall(orig, tb, ...)
				if not ok then report("G.FUNCS." .. name, current, err) end
			end
		end
	end
	-- Amulet scores inside a coroutine; its errors would end the game, so catch them with the
	-- coroutine's own traceback and stop that scoring
	local co = Talisman and Talisman.coroutine
	if co and co.resume then
		co.resume = function(...)
			local state = Talisman.scoring_coroutine
			if not state then return end
			state.yield = love.timer.getTime()
			state.frames = state.frames + 1
			local ok, err = coroutine.resume(state.coroutine, ...)
			if not ok then
				report("scoring", current, debug.traceback(state.coroutine, tostring(err)))
				pcall(co.forcestop)
				Talisman.scoring_coroutine = nil
			end
		end
	end
	local calc_ref = SMODS.calculate_context
	SMODS.calculate_context = function(...)
		local res = { xpcall(calc_ref, tb, ...) }
		if res[1] then return unpack(res, 2) end
		report("SMODS.calculate_context", current, res[2])
	end
end

-- ---------------------------------------------------------------- card lists

local jokers, consumables, all_cards = {}, {}, {}

-- Antimatter's all-in-one joker carries every joker's ability at once: too heavy for a smoke test
local SKIP = { j_hstart_all_in_one = true }

local function free_memory()
	if MEMSAVER and MEMSAVER.unload_atlases then pcall(MEMSAVER.unload_atlases) end
	collectgarbage("collect")
end

local function build_lists()
	local cons_sets = { Tarot = true, Planet = true, Spectral = true }
	for k in pairs(SMODS.ConsumableTypes or {}) do cons_sets[k] = true end
	cons_sets.CBlind = nil -- Entropy blind tokens: one per blind, mostly identical
	for key, c in pairs(G.P_CENTERS) do
		if SKIP[key] then
		elseif c.set == "Joker" then
			jokers[#jokers + 1] = key
		elseif cons_sets[c.set] then
			consumables[#consumables + 1] = key
		end
		if not SKIP[key] and (c.set == "Joker" or cons_sets[c.set] or c.set == "Voucher" or c.set == "Enhanced") then
			all_cards[#all_cards + 1] = key
		end
	end
	table.sort(jokers); table.sort(consumables); table.sort(all_cards)
	-- fixed shuffle so groups mix mods and a restart continues the same order
	local rng = 12345
	local function shuffle(t)
		for i = #t, 2, -1 do
			rng = (rng * 1103515245 + 12345) % 2147483648
			local j = rng % i + 1
			t[i], t[j] = t[j], t[i]
		end
	end
	shuffle(jokers); shuffle(consumables)
end

-- ---------------------------------------------------------------- persistent state

local st = { tooltip = 1, joker = 1, cons = 1, runs = 0, done = false }

local function save_state()
	local parts = {}
	for k, v in pairs(st) do parts[#parts + 1] = k .. "=" .. tostring(v) end
	love.filesystem.write(STATE, "return {" .. table.concat(parts, ",") .. "}")
end

local function load_state()
	local src = love.filesystem.read(STATE)
	if src then
		local ok, t = pcall(load(src))
		if ok and type(t) == "table" then for k, v in pairs(t) do st[k] = v end end
	end
end

-- ---------------------------------------------------------------- bot

local last_progress = 0
local state_since, last_state = 0, nil
local stuck_tries = 0
local phase = 0
local wait_until = 0

local function now() return love.timer.getTime() end

local function queue_idle()
	for _, ev in ipairs(G.E_MANAGER.queues.base or {}) do
		if not ev.no_delete and ev.blocking ~= false then return false end
	end
	return true
end

local function random_from(t, n)
	local out, used = {}, {}
	for _ = 1, math.min(n, #t) do
		local i
		repeat i = math.random(#t) until not used[i]
		used[i] = true
		out[#out + 1] = t[i]
	end
	return out
end

local function highlight(area, n)
	area:unhighlight_all()
	local limit = area.config.highlighted_limit
	area.config.highlighted_limit = math.max(limit or 5, n)
	for _, c in ipairs(random_from(area.cards, n)) do area:add_to_highlighted(c, true) end
	area.config.highlighted_limit = limit
end

local function add_card(key, area)
	current = "add " .. key
	local ok, err = xpcall(function()
		SMODS.add_card({ key = key, area = area, skip_materialize = true, no_edition = true })
	end, tb)
	if not ok then report("add_card", key, err) end
end

local function clear_area(area)
	for i = #area.cards, 1, -1 do
		local c = area.cards[i]
		current = "remove " .. center_key(c)
		local ok, err = xpcall(function() c:remove() end, tb)
		if not ok then report("remove", center_key(c), err) end
	end
end

local function tooltip_pass()
	-- a few per frame so the game keeps drawing
	for _ = 1, 25 do
		local key = all_cards[st.tooltip]
		if not key then return true end
		current = "tooltip " .. key
		local ok, err = xpcall(function()
			local center = G.P_CENTERS[key]
			T.area = T.area or CardArea(G.ROOM.T.w + 5, 0, G.CARD_W, G.CARD_H, { card_limit = 1e9, type = "title" })
			local card = Card(T.area.T.x, T.area.T.y, G.CARD_W, G.CARD_H, nil, center, { bypass_discovery_center = true })
			T.area:emplace(card)
			card:generate_UIBox_ability_table()
			card:remove()
		end, tb)
		if not ok then report("tooltip", key, err) end
		st.tooltip = st.tooltip + 1
	end
	if st.tooltip % 200 < 25 then free_memory() end
	return false
end

local function new_run()
	free_memory()
	st.runs = st.runs + 1
	save_state()
	current = "new run"
	if G.STAGE == G.STAGES.RUN then G:delete_run() end
	G.FUNCS.start_run(nil, { stake = 1, seed = "CURATOR" .. st.runs })
	wait_until = now() + 3
end

local function step_hand()
	local g = G.GAME
	g.current_round.hands_left = math.max(g.current_round.hands_left, 5)
	g.current_round.discards_left = math.max(g.current_round.discards_left, 5)
	G.jokers.config.card_limit = math.max(G.jokers.config.card_limit, GROUP + 2)
	G.consumeables.config.card_limit = math.max(G.consumeables.config.card_limit, 4)

	phase = phase % 4 + 1
	if phase == 1 then
		-- next joker group
		if st.joker > #jokers then return "jokers-done" end
		log(string.format("group %d at %.0fs", st.joker, now()))
		local first = st.joker
		st.joker = st.joker + GROUP
		save_state()
		if first % 100 < GROUP then free_memory() end
		clear_area(G.jokers)
		for i = first, math.min(first + GROUP - 1, #jokers) do add_card(jokers[i], G.jokers) end
	elseif phase == 2 or phase == 4 then
		-- use one consumable on random cards / jokers
		local key = consumables[st.cons]
		if key then
			st.cons = st.cons + 1
			save_state()
			clear_area(G.consumeables)
			add_card(key, G.consumeables)
			local c = G.consumeables.cards[1]
			if c then
				local cfg = c.ability and c.ability.consumeable or {}
				highlight(G.hand, math.max(1, math.min(cfg.max_highlighted or 2, #G.hand.cards)))
				if math.random() < 0.5 and #G.jokers.cards > 0 then highlight(G.jokers, 1) end
				current = "use " .. key .. " with " .. table.concat((function()
					local t = {}
					for _, j in ipairs(G.jokers.cards) do t[#t + 1] = center_key(j) end
					return t
				end)(), ",")
				if c:can_use_consumeable() then
					G.FUNCS.use_card({ config = { ref_table = c } })
				end
			end
		end
	elseif phase == 3 then
		if #G.hand.cards == 0 then return "empty" end
		local jk = {}
		for _, j in ipairs(G.jokers.cards) do jk[#jk + 1] = center_key(j) end
		G.jokers:unhighlight_all()
		if math.random() < 0.25 and g.current_round.discards_left > 0 then
			current = "discard with " .. table.concat(jk, ",")
			highlight(G.hand, math.min(3, #G.hand.cards))
			G.FUNCS.discard_cards_from_highlighted(nil)
		else
			current = "play with " .. table.concat(jk, ",")
			highlight(G.hand, math.min(5, #G.hand.cards))
			G.FUNCS.play_cards_from_highlighted(nil)
		end
	end
end

local function select_blind()
	local deck = G.GAME.blind_on_deck
	local opt = deck and G.blind_select_opts and G.blind_select_opts[string.lower(deck)]
	local btn = opt and opt:get_UIE_by_ID("select_blind_button")
	if btn then
		current = "select blind " .. deck
		G.FUNCS.select_blind(btn)
		return true
	end
end

local function finish()
	st.done = true
	save_state()
	log(string.format("DONE errors=%d runs=%d jokers=%d consumables=%d tooltips=%d", errors, st.runs, #jokers, #consumables, #all_cards))
	love.event.quit()
end

local function tick()
	if wait_until > now() then return end
	if G.OVERLAY_MENU and G.STAGE == G.STAGES.RUN then G.FUNCS.exit_overlay_menu() end
	if G.STAGE ~= G.STAGES.RUN then
		if G.STAGE == G.STAGES.MAIN_MENU and not G.OVERLAY_MENU then new_run() end
		return
	end
	-- the blind select screen is built by events: act as soon as its button exists
	if G.STATE == G.STATES.BLIND_SELECT and G.blind_select_opts and select_blind() then
		wait_until = now() + 1
		return
	end
	if not queue_idle() then
		if now() - last_progress > 12 then
			log("HANG during=" .. current .. " state=" .. tostring(G.STATE))
			report("hang", current, "queue did not finish in 12s")
			if G.STATE ~= G.STATES.BLIND_SELECT then G.E_MANAGER:clear_queue() end
			stuck_tries = stuck_tries + 1
			last_progress = now()
			if stuck_tries > 2 then stuck_tries = 0; new_run() end
		end
		return
	end
	last_progress = now()
	local s = G.STATE
	if s ~= last_state then last_state, state_since = s, now() end
	-- stuck in a state the bot cannot act in (e.g. scoring aborted mid-hand): start over
	if s ~= G.STATES.SELECTING_HAND and now() - state_since > 20 then
		log("STUCK state=" .. tostring(s) .. " during=" .. current)
		report("stuck", current, "state " .. tostring(s) .. " for 20s")
		state_since = now()
		return new_run()
	end
	if st.tooltip <= #all_cards then
		if tooltip_pass() then log("tooltips done") end
		save_state()
		return
	end
	if (T.recent or 0) > 15 then
		-- an error cascade means the run is broken (e.g. endless recursion); start over
		log("CASCADE during=" .. current .. ", restarting run")
		T.recent = 0
		return new_run()
	end
	if s == G.STATES.SELECTING_HAND then
		stuck_tries = 0
		T.recent = 0
		if #G.deck.cards + #G.hand.cards < 8 then return new_run() end
		local r = step_hand()
		if r == "jokers-done" then
			if st.cons > #consumables then return finish() end
			-- keep using consumables with the last group
			st.joker = #jokers + 1
			phase = 1
		elseif r == "empty" then
			G.FUNCS.draw_from_deck_to_hand(nil)
		end
		wait_until = now() + 0.05
	elseif s == G.STATES.BLIND_SELECT then
		if not select_blind() then wait_until = now() + 0.5 end
	elseif s == G.STATES.ROUND_EVAL then
		current = "cash out"
		G.FUNCS.cash_out({ config = {} })
		wait_until = now() + 0.5
	elseif s == G.STATES.SHOP then
		current = "leave shop"
		G.FUNCS.toggle_shop({ config = {} })
		wait_until = now() + 0.5
	elseif s == G.STATES.GAME_OVER then
		new_run()
	elseif s == G.STATES.TAROT_PACK or s == G.STATES.PLANET_PACK or s == G.STATES.SPECTRAL_PACK
		or s == G.STATES.STANDARD_PACK or s == G.STATES.BUFFOON_PACK or s == G.STATES.SMODS_BOOSTER_OPENED then
		current = "skip pack"
		if G.FUNCS.skip_booster then G.FUNCS.skip_booster({ config = {} }) end
		wait_until = now() + 0.5
	end
end

function T.start()
	love.filesystem.remove("curator_autotest_request")
	load_state()
	if st.done then
		st = { tooltip = 1, joker = 1, cons = 1, runs = 0, done = false }
		love.filesystem.write(LOG, "")
	end
	log(string.format("START %s tooltip=%d joker=%d cons=%d", os.date(), st.tooltip, st.joker, st.cons))
	install_guards()
	build_lists()
	math.randomseed(st.runs * 7919 + st.joker)
	G.SETTINGS.GAMESPEED = 64
	G.SETTINGS.tutorial_complete = true
	last_progress = now()
	local update_ref = Game.update
	function Game:update(dt)
		local ok_u, err_u = xpcall(update_ref, tb, self, dt)
		if not ok_u then report("Game:update", current, err_u) end
		local ok, err = xpcall(tick, tb)
		if not ok then report("bot", current, err) end
	end
	-- a hard crash still ends here: note what was being tested so the next start skips it
	local handler = love.errorhandler
	love.errorhandler = function(msg)
		log("CRASH during=" .. current .. "\n    " .. short_tb(debug.traceback(tostring(msg), 2)))
		save_state()
		return handler(msg)
	end
end

return T
