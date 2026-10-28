--- WASD Navigation: the keyboard drives the game's own gamepad controls, so
--- every menu, card and button (mods' too) can be reached without the mouse.
--- The game then shows gamepad hints (Xbox glyphs) next to buttons; moving the
--- mouse switches back to normal mouse control.

WASDNav = {}
local WN = WASDNav

-- Keyboard key -> gamepad button.
WN.keys = {
	w = "dpup", a = "dpleft", s = "dpdown", d = "dpright",
	space = "a",         -- (A)  press the selected button / pick a card; hold + A/D drags it
	f = "b",             -- (B)  back, deselect the hand
	e = "x",             -- (X)  play hand, reroll the shop, skip blind
	q = "y",             -- (Y)  discard, leave the shop, select blind
	z = "leftshoulder",  -- (LB) sell, previous tab
	c = "rightshoulder", -- (RB) use, next tab
	tab = "back",        -- run info
}

-- Gamepad triggers are axes, read every frame from the "gamepad": holding the
-- key counts as a pulled trigger. LT peeks at the remaining deck, RT opens it.
WN.triggers = { triggerleft = "1", triggerright = "3" }
local trigger_keys = {}
for _, key in pairs(WN.triggers) do trigger_keys[key] = true end

-- Keys held down right now, with the button they pressed.
local down = {}

local function get_axis(_, axis)
	local key = WN.triggers[axis]
	return key and down[key] and 1 or 0
end

-- Typing, rebinding a Handy key and Ctrl/Alt combos keep the keyboard as is.
local function captured(key)
	local C = G and G.CONTROLLER
	if not C or C.text_input_hook then return end
	if Handy and Handy.controller and Handy.controller.binding and Handy.controller.binding.get_current() then return end
	if love.keyboard.isDown("lctrl", "rctrl", "lalt", "ralt", "lgui", "rgui") then return end
	return WN.keys[key] or trigger_keys[key]
end

local keypressed_ref = love.keypressed
function love.keypressed(key, ...)
	if not down[key] and captured(key) then
		local C = G.CONTROLLER
		C.keyboard_controller.getGamepadAxis = get_axis
		C.keyboard_controller.setVibration = function() end
		down[key] = WN.keys[key] or true
		if WN.keys[key] then
			love.gamepadpressed(C.keyboard_controller, WN.keys[key])
		else
			C:set_gamepad(C.keyboard_controller)
			C:set_HID_flags("button")
		end
		return
	end
	return keypressed_ref(key, ...)
end

local keyreleased_ref = love.keyreleased
function love.keyreleased(key, ...)
	local button = down[key]
	if button then
		down[key] = nil
		if button ~= true then love.gamepadreleased(G.CONTROLLER.keyboard_controller, button) end
		return
	end
	return keyreleased_ref(key, ...)
end

---------------------------------------------------------------------------
-- Key hints: every button that shows a gamepad glyph gets the keyboard key
-- that presses it instead, with the mouse too.
---------------------------------------------------------------------------

WN.show_hints = true

local key_names = { space = "Space", tab = "Tab" }
local function key_name(key)
	return key_names[key] or key:upper()
end

-- Gamepad button -> keyboard label. Built on use, since the A/B swap
-- setting (G.button_mapping) changes which button a key ends up pressing.
local function hint_of(button)
	if button == "start" then return "Esc" end
	if button == "guide" then button = "back" end
	for key, pressed in pairs(WN.keys) do
		if (G.button_mapping[pressed] or pressed) == button then return key_name(key) end
	end
	for axis, key in pairs(WN.triggers) do
		if axis == button then return key_name(key) end
	end
end

-- Handy takes some buttons over (play, discard, reroll, buy/sell...) and
-- lists its own keyboard keys for them; show those next to ours.
local function hint_for(e)
	local override = e.handy_gamepad_override
	local label = hint_of(override and override.button or e.config.focus_args.button)
	local extra = override and override.module and override.module.keys_1
	if extra and #extra > 0 then
		local handy = table.concat(extra, "+")
		label = label and (label .. " / " .. handy) or handy
	end
	return label
end

local function make_hint(e, label)
	local args = e.config.focus_args
	local align = args.orientation or "cr"
	return UIBox({
		definition = {
			n = G.UIT.ROOT,
			config = { align = "cm", padding = 0.04, r = 0.05, colour = { 0, 0, 0, 0.6 } },
			nodes = {
				{ n = G.UIT.T, config = { text = label, scale = (args.scale or 0.45) * 0.6, colour = G.C.UI.TEXT_LIGHT } },
			},
		},
		config = {
			align = align,
			offset = args.offset or (align == "bm" and { x = 0, y = 0.02 } or { x = 0.1, y = 0.02 }),
			major = e, parent = e,
		},
	})
end

local function remove_hint(e)
	if e.children.wasdnav_hint then
		e.children.wasdnav_hint:remove()
		e.children.wasdnav_hint = nil
	end
	e.wasdnav_label = nil
end

-- Runs every frame for each element with a gamepad hint.
local set_button_pip_ref = G.FUNCS.set_button_pip
G.FUNCS.set_button_pip = function(e, ...)
	local ret = set_button_pip_ref(e, ...)
	if e.REMOVED or not e.config.focus_args then return ret end
	local label = WN.show_hints and hint_for(e)
	if label ~= e.wasdnav_label then
		remove_hint(e)
		if label then
			e.children.wasdnav_hint = make_hint(e, label)
			e.children.wasdnav_hint.states.collide.can = false
			e.wasdnav_label = label
		end
	end
	-- The glyph (vanilla's or Handy's) stays hidden under the key hint.
	if label and e.children.button_pip then e.children.button_pip.states.visible = false end
	return ret
end
