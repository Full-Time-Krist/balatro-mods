--- Consumable Zoom: a button under the consumable slots, the joker slots and an
--- opened booster pack shows all of its cards full size in a grid over the
--- table. The cards stay in their area, so using, selling, picking, tooltips
--- and drag-to-reorder keep working.

ConsumableZoom = {}
local CZ = ConsumableZoom

local GAP_X, PAD = 0.15, 0.25
local BUTTON_H = 0.6

-- anchor: where the grid hangs from the area.
--   top_right     right edges line up, grows down (consumables, top right)
--   top_center    centred on the area, grows down (jokers)
--   bottom_center centred on the area, grows up (booster pack, above the hand)
CZ.specs = {
	{
		id = "jokers", min_cards = 6, gap_y = 0.35, anchor = "top_center",
		area = function() return G.jokers end,
		button = { align = "bm", offset = { x = 0, y = 0.25 } },
	},
	{
		id = "consumeables", min_cards = 3, gap_y = 0.35, anchor = "top_right",
		area = function() return G.consumeables end,
		button = { align = "bm", offset = { x = 0, y = 0.25 } },
	},
	{
		-- Pack cards get big Use/Select buttons underneath, hence the larger gap.
		id = "pack", min_cards = 5, gap_y = 0.8, tail = 0.6, anchor = "bottom_center",
		area = function() return G.pack_cards end,
		button = { align = "tm", offset = { x = 0, y = -0.15 } },
	},
}

local function spec_of(area)
	if not area then return end
	for _, spec in ipairs(CZ.specs) do
		if spec.area() == area then return spec end
	end
end

-- Horizontal room: from the left edge of the joker row to the right edge of
-- the consumable slots (falls back to the area itself).
local function region(area)
	local left = G.jokers and G.jokers.T.x or area.T.x
	local right = G.consumeables and (G.consumeables.T.x + G.consumeables.T.w) or (area.T.x + area.T.w)
	return math.min(left, area.T.x), math.max(right, area.T.x + area.T.w)
end

local function clamp_scroll(spec, max_scroll)
	spec.scroll = math.max(0, math.min(spec.scroll or 0, max_scroll))
end

-- Grid that fits the region horizontally. If its rows don't fit vertically,
-- only a window of them is shown and the rest is reached by scrolling.
local function compute_layout(spec, area)
	local n = #area.cards
	local cw, ch = area.card_w or G.CARD_W, G.CARD_H
	local left, right = region(area)
	if spec.anchor == "top_right" then right = area.T.x + area.T.w end
	local cols = math.floor((right - left + GAP_X) / (cw + GAP_X))
	cols = math.max(1, math.min(n, cols))
	local rows = math.ceil(n / cols)
	local w = cols * cw + (cols - 1) * GAP_X

	local up = spec.anchor == "bottom_center"
	local area_bottom = area.T.y + area.T.h
	local max_h = up and (area_bottom - 0.3 - BUTTON_H - 2 * PAD)
		or (G.ROOM.T.h - 0.3 - area.T.y - BUTTON_H - 2 * PAD)
	local row_step = ch + spec.gap_y
	local full_h = (rows - 1) * row_step + ch
	local scrollable = full_h > max_h
	-- Room below the last row for the buttons under pack cards.
	if scrollable then full_h = full_h + (spec.tail or 0) end
	local h = scrollable and math.max(ch, max_h) or full_h
	local max_scroll = math.max(0, full_h - h)
	clamp_scroll(spec, max_scroll)

	local x0
	if spec.anchor == "top_right" then
		x0 = area.T.x + area.T.w - w
	else
		x0 = area.T.x + area.T.w / 2 - w / 2
		x0 = math.max(left, math.min(x0, right - w))
	end
	-- vy0/h: the visible window; y0: top of the first row (scrolled).
	local vy0 = up and (area_bottom - h) or area.T.y
	return {
		cols = cols, rows = rows, cw = cw, ch = ch, row_step = row_step, w = w, h = h,
		x0 = x0, vy0 = vy0, y0 = vy0 - spec.scroll, scroll = spec.scroll, up = up,
		scrollable = scrollable, full_h = full_h, max_scroll = max_scroll,
	}
end

local function cursor_in_room()
	return G.CURSOR.T.x - G.ROOM.T.x, G.CURSOR.T.y - G.ROOM.T.y
end

local function open_layout_of(area)
	local spec = spec_of(area)
	if spec and spec.open and spec.last_area == area and spec.layout and spec.layout.scrollable then
		return spec.layout
	end
end

-- Cards (and their Use/Sell buttons) scrolled out of the window can't be
-- clicked through the panel edge or the table around it.
local function clipped_away(area, point)
	local L = open_layout_of(area)
	if not L then return false end
	local y = point.y - G.ROOM.T.y
	return y < L.vy0 - PAD * 0.9 or y > L.vy0 + L.h + PAD * 0.9
end

local function grid_row(L, card)
	return math.floor((card.T.y + card.T.h / 2 - L.y0 - L.ch / 2) / L.row_step + 0.5)
end

local function align_grid(spec, area)
	if #area.cards == 0 then return end
	local L = compute_layout(spec, area)
	spec.layout = L
	-- While a card is dragged, order by its spot in the grid (row, then x).
	local dragged = G.CONTROLLER.dragging.target
	if dragged and dragged.area == area then
		table.sort(area.cards, function(a, b)
			local ra, rb = grid_row(L, a), grid_row(L, b)
			if ra ~= rb then return ra < rb end
			return a.T.x < b.T.x
		end)
	end
	for k, card in ipairs(area.cards) do
		if not card.states.drag.is and not card.disable_align then
			local col, row = (k - 1) % L.cols, math.floor((k - 1) / L.cols)
			card.T.r = 0
			card.T.x = L.x0 + col * (L.cw + GAP_X) + 0.5 * (L.cw - card.T.w)
			card.T.y = L.y0 + row * L.row_step + 0.5 * (L.ch - card.T.h)
				- (card.highlighted and G.HIGHLIGHT_H / 2 or 0)
		end
	end
end

local function toggle_button(spec)
	return UIBox_button({
		button = "czoom_toggle",
		label = { localize(spec.open and "czoom_close" or "czoom_open") },
		minw = 1.8, minh = 0.45, scale = 0.35, col = false,
		colour = spec.open and G.C.RED or G.C.SECONDARY_SET.Tarot,
	})
end

-- UIBox_button has no ref_table argument, so find the button node and set it.
local function with_spec(node, spec)
	if type(node) ~= "table" then return node end
	if node.config and node.config.button == "czoom_toggle" then node.config.ref_table = spec end
	for _, child in ipairs(node.nodes or {}) do with_spec(child, spec) end
	return node
end

local function make_button(spec, area)
	return UIBox({
		definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = { with_spec(toggle_button(spec), spec) } },
		config = { align = spec.button.align, offset = spec.button.offset, major = area, parent = area, bond = "Strong" },
	})
end

-- Dark backdrop behind the grid, with the close button below it (above it
-- for grids that grow upwards).
local function make_panel(spec, area, L)
	local top = L.vy0 - PAD - (L.up and BUTTON_H or 0)
	return UIBox({
		definition = {
			n = G.UIT.ROOT,
			config = {
				align = L.up and "tm" or "bm", padding = 0.1, r = 0.15, colour = { 0, 0, 0, 0.75 },
				minw = L.w + 2 * PAD, minh = L.h + 2 * PAD + BUTTON_H,
			},
			nodes = { with_spec(toggle_button(spec), spec) },
		},
		config = {
			align = "tli", offset = { x = L.x0 - PAD - area.T.x, y = top - area.T.y },
			major = area, parent = area, bond = "Strong",
		},
	})
end

local function clear_ui(spec, area)
	for _, key in ipairs({ "czoom_button", "czoom_panel" }) do
		if area and area.children[key] then
			area.children[key]:remove()
			area.children[key] = nil
		end
	end
	spec.panel_key = nil
end

function CZ.set_open(spec, open)
	spec.open = open
	spec.scroll = 0
	local area = spec.area()
	if not area then return end
	clear_ui(spec, area)
	area:align_cards()
end

G.FUNCS.czoom_toggle = function(e)
	local spec = e.config.ref_table
	if spec then CZ.set_open(spec, not spec.open) end
end

-- Scrolls the grid while a dragged card is held near its top or bottom edge.
local function drag_scroll(spec, area)
	local L = spec.layout
	local dragged = G.CONTROLLER.dragging.target
	if not (L and L.scrollable and dragged and dragged.area == area) then return end
	local cy = dragged.T.y + dragged.T.h / 2
	local edge, speed = 0.6, 8 * (G.real_dt or 0)
	if cy < L.vy0 + edge then
		spec.scroll = spec.scroll - speed
	elseif cy > L.vy0 + L.h - edge then
		spec.scroll = spec.scroll + speed
	end
	clamp_scroll(spec, L.max_scroll)
end

-- Keeps the card selected with a gamepad (or WASD) inside the window.
local function follow_focus(spec, area)
	local L = spec.layout
	local focused = G.CONTROLLER.focused.target
	if not (L and L.scrollable and focused and focused.area == area) then return end
	for k, card in ipairs(area.cards) do
		if card == focused then
			local top = math.floor((k - 1) / L.cols) * L.row_step
			if top < spec.scroll then
				spec.scroll = top
			elseif top + L.ch > spec.scroll + L.h then
				spec.scroll = top + L.ch - L.h
			end
			clamp_scroll(spec, L.max_scroll)
			return
		end
	end
end

-- Runs every frame from align_cards (CardArea:move calls it each frame).
local function update(spec, area)
	-- A new booster pack (or run) builds a new area: start closed.
	if spec.last_area ~= area then
		spec.last_area = area
		spec.open = false
		spec.scroll = 0
		spec.panel_key = nil
	end
	local enough = #area.cards >= spec.min_cards
	if spec.open and not enough then
		spec.open = false
		clear_ui(spec, area)
	end
	if spec.open then
		drag_scroll(spec, area)
		follow_focus(spec, area)
		align_grid(spec, area)
		local L = spec.layout
		local key = L and table.concat({ L.cols, L.rows, math.floor(L.h * 100),
			math.floor((L.x0 - area.T.x) * 100), math.floor((L.vy0 - area.T.y) * 100) }, "/")
		if key and spec.panel_key ~= key then
			if area.children.czoom_panel then area.children.czoom_panel:remove() end
			area.children.czoom_panel = make_panel(spec, area, L)
			spec.panel_key = key
		end
	elseif enough and not area.children.czoom_button then
		area.children.czoom_button = make_button(spec, area)
	elseif not enough and area.children.czoom_button then
		clear_ui(spec, area)
	end
end

-- Thin bar on the right edge of the panel showing which part of the grid is in view.
local function draw_scrollbar(L)
	local S = G.TILESCALE * G.TILESIZE
	local x = L.x0 + L.w + PAD * 0.45
	local thumb_h = math.max(0.4, L.h * L.h / L.full_h)
	local thumb_y = L.vy0 + (L.h - thumb_h) * (L.max_scroll > 0 and L.scroll / L.max_scroll or 0)
	love.graphics.setColor(1, 1, 1, 0.15)
	love.graphics.rectangle("fill", (x - 0.04) * S, L.vy0 * S, 0.08 * S, L.h * S, 0.04 * S)
	love.graphics.setColor(1, 1, 1, 0.6)
	love.graphics.rectangle("fill", (x - 0.04) * S, thumb_y * S, 0.08 * S, thumb_h * S, 0.04 * S)
	love.graphics.setColor(1, 1, 1, 1)
end

-- Limits drawing to the visible rows (with some room for raised cards).
-- Coordinates are taken in the area's space, i.e. after translate_container.
local function push_clip(L)
	local S = G.TILESCALE * G.TILESIZE
	local _, top = love.graphics.transformPoint(0, (L.vy0 - PAD * 0.9) * S)
	local _, bottom = love.graphics.transformPoint(0, (L.vy0 + L.h + PAD * 0.9) * S)
	local canvas = love.graphics.getCanvas()
	local w = canvas and canvas:getWidth() or love.graphics.getWidth()
	local old = { love.graphics.getScissor() }
	love.graphics.intersectScissor(0, math.floor(top), w, math.max(0, math.ceil(bottom - top)))
	return old
end

local function pop_clip(old)
	if old[1] then love.graphics.setScissor(unpack(old)) else love.graphics.setScissor() end
end

-- Drawn from Game:draw after all card areas (see lovely.toml), so an open
-- grid sits on top of the other areas. The pack grid is drawn last.
function CZ.draw_late()
	for _, spec in ipairs(CZ.specs) do
		local area = spec.area()
		if spec.open and area and area.states.visible and spec.last_area == area then
			spec.drawing_late = true
			if area.children.czoom_panel then
				love.graphics.push()
				area.children.czoom_panel:translate_container()
				area.children.czoom_panel:draw()
				love.graphics.pop()
			end
			local L = spec.layout
			love.graphics.push()
			area:translate_container()
			if L and L.scrollable then
				draw_scrollbar(L)
				local old = push_clip(L)
				area:draw()
				pop_clip(old)
			else
				area:draw()
			end
			love.graphics.pop()
			spec.drawing_late = false
		end
	end
end

-- Mouse wheel over an open grid scrolls it (and isn't passed on to other mods).
local function on_wheel(y)
	local cx, cy = cursor_in_room()
	for i = #CZ.specs, 1, -1 do
		local spec = CZ.specs[i]
		local area = spec.area()
		local L = area and open_layout_of(area)
		if L and area.states.visible
			and cx >= L.x0 - PAD and cx <= L.x0 + L.w + PAD
			and cy >= L.vy0 - PAD and cy <= L.vy0 + L.h + PAD then
			spec.scroll = spec.scroll - y * L.row_step * 0.5
			clamp_scroll(spec, L.max_scroll)
			return true
		end
	end
end

-- Installed once all mods are loaded so this handler runs before theirs.
local function hook_wheel()
	if CZ.wheel_hooked then return end
	CZ.wheel_hooked = true
	local wheelmoved_ref = love.wheelmoved or function() end
	function love.wheelmoved(x, y, ...)
		if G and G.CURSOR and G.ROOM and y ~= 0 and on_wheel(y) then return end
		return wheelmoved_ref(x, y, ...)
	end
end

local card_collides_ref = Card.collides_with_point
function Card:collides_with_point(point, ...)
	if self.area and self ~= G.CONTROLLER.dragging.target and clipped_away(self.area, point) then return false end
	return card_collides_ref(self, point, ...)
end

local element_collides_ref = UIElement.collides_with_point
function UIElement:collides_with_point(point, ...)
	local parent = self.UIBox and self.UIBox.config and self.UIBox.config.parent
	if parent and parent.area and parent.is and parent:is(Card) and clipped_away(parent.area, point) then
		return false
	end
	return element_collides_ref(self, point, ...)
end

local align_cards_ref = CardArea.align_cards
function CardArea:align_cards(...)
	local spec = spec_of(self)
	if spec then
		update(spec, self)
		if spec.open then return end
	end
	return align_cards_ref(self, ...)
end

local draw_ref = CardArea.draw
function CardArea:draw(...)
	local spec = spec_of(self)
	if not spec then return draw_ref(self, ...) end
	-- When open, the area is drawn later on top of everything (draw_late).
	if spec.open and not spec.drawing_late then return end
	local ret = draw_ref(self, ...)
	if not spec.open and self.children.czoom_button then self.children.czoom_button:draw() end
	return ret
end

local start_run_ref = Game.start_run
function Game:start_run(...)
	hook_wheel()
	for _, spec in ipairs(CZ.specs) do
		spec.open = false
		spec.scroll = 0
		spec.panel_key = nil
		spec.last_area = nil
	end
	return start_run_ref(self, ...)
end
