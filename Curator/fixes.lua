-- Small cross-mod compatibility patches, applied once on the first main menu
-- (after every mod has loaded). Found by the autotest (autotest.lua), 2026-10-25.
local F = {}

local function wrap_loc_vars(key, before)
	local center = G.P_CENTERS[key]
	if not (center and center.loc_vars) then return end
	local ref = center.loc_vars
	center.loc_vars = function(self, info_queue, card, ...)
		before(card)
		return ref(self, info_queue, card, ...)
	end
end

function F.apply()
	-- Some mod calls play_sound() with a table as pitch/volume; the sound thread then crashes the
	-- whole game ("original_volume (a table value)"). Drop non-number values.
	local play_sound_ref = play_sound
	function play_sound(sound_code, per, vol, ...)
		if (per ~= nil and type(per) ~= "number") or (vol ~= nil and type(vol) ~= "number") then
			if Curator.autotest then
				Curator.autotest.report("play_sound", sound_code, debug.traceback("non-number pitch/volume", 2))
			end
			if type(per) ~= "number" then per = nil end
			if type(vol) ~= "number" then vol = nil end
		end
		return play_sound_ref(sound_code, per, vol, ...)
	end

	-- UnStable Joker Island: default target_rank is the number 2, localize() wants a rank key;
	-- hovering it in the collection outside a run crashed the game
	wrap_loc_vars("j_unstb_joker_island", function(card)
		local extra = card and card.ability and card.ability.extra
		if type(extra) == "table" and type(extra.target_rank) == "number" then
			extra.target_rank = tostring(extra.target_rank)
		end
	end)
end

return F
