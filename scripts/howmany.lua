-- Too Many Buildables (TMB): the "How many?" crafting popup.
local U = require("scripts.util")
local main_inventory, say = U.main_inventory, U.say
local C = require("scripts.crafting")
local craft_items, find_recipe = C.craft_items, C.find_recipe
---------------------------------------------------------------------------
-- "How many?" popup (Alt + click)
---------------------------------------------------------------------------
local MAX_STACKS = 10

-- 999 / 1.2k / 25k / 1.5M, like the game's own counts
local function short_count(n)
  if n >= 1000000 then return (string.format("%.1fM", math.floor(n / 100000) / 10):gsub("%.0M", "M")) end
  if n >= 10000 then return string.format("%dk", math.floor(n / 1000)) end
  if n >= 1000 then return (string.format("%.1fk", math.floor(n / 100) / 10):gsub("%.0k", "k")) end
  return tostring(n)
end

local function howmany_close(player)
  local f = player.gui.screen.tmb_howmany
  if f then f.destroy() end
end

local function hm_right(frame) return frame.tmb_body_frame.tmb_body.tmb_right end

-- Simple sums in the amount box: + - * / and brackets ("500-39", "(500-39)/2", "2*50+7").
-- Returns a number, or nil if the text can't be read.
local function evaluate(text)
  local s = text:gsub("[%s,]", "")
  if s == "" then return 0 end
  if s:find("[^%d%.%+%-%*/%(%)]") then return nil end
  local pos = 1
  local expr
  local function peek() return s:sub(pos, pos) end
  local function number()
    local n = s:match("^%d+%.?%d*", pos) or s:match("^%.%d+", pos)
    if not n then return nil end
    pos = pos + #n
    return tonumber(n)
  end
  local function factor()
    local c = peek()
    if c == "-" then pos = pos + 1; local v = factor(); return v and -v end
    if c == "+" then pos = pos + 1; return factor() end
    if c == "(" then
      pos = pos + 1
      local v = expr()
      if not v or peek() ~= ")" then return nil end
      pos = pos + 1
      return v
    end
    return number()
  end
  local function term()
    local v = factor()
    while v do
      local c = peek()
      if c ~= "*" and c ~= "/" then break end
      pos = pos + 1
      local r = factor()
      if not r then return nil end
      if c == "*" then v = v * r else
        if r == 0 then return nil end
        v = v / r
      end
    end
    return v
  end
  expr = function()
    local v = term()
    while v do
      local c = peek()
      if c ~= "+" and c ~= "-" then break end
      pos = pos + 1
      local r = term()
      if not r then return nil end
      v = (c == "+") and v + r or v - r
    end
    return v
  end
  local v = expr()
  if not v or pos <= #s or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

-- The window's most: 10 stacks plus a stack of singles (5,500 for a stack of 500).
local function howmany_max(frame)
  return (MAX_STACKS + 1) * frame.tags.stack
end

-- The amount in the box, rounded down and kept between 0 and the window's most; nil if unreadable.
local function howmany_total(frame)
  local t = evaluate(hm_right(frame).tmb_total_row.tmb_total.text)
  if not t then return nil end
  return math.max(0, math.min(math.floor(t), howmany_max(frame)))
end

local function howmany_sync_from_sliders(frame)
  local right = hm_right(frame)
  local stack = frame.tags.stack
  local st = math.floor(right.tmb_stacks_row.tmb_stacks.slider_value + 0.5)
  local si = math.floor(right.tmb_singles_row.tmb_singles.slider_value + 0.5)
  right.tmb_stacks_row.tmb_stacks_val.caption = tostring(st)
  right.tmb_singles_row.tmb_singles_val.caption = tostring(si)
  right.tmb_total_row.tmb_total.text = tostring(st * stack + si)
end

local function howmany_sync_from_total(frame)
  local right = hm_right(frame)
  local stack = frame.tags.stack
  local t = howmany_total(frame)
  local field = right.tmb_total_row.tmb_total
  if not t then
    field.tooltip = {"", {"tmb.bad-formula"}, "\n", {"tmb.tip-total", short_count(howmany_max(frame))}}
    return  -- half-typed: leave the sliders where they were
  end
  field.tooltip = {"tmb.tip-total", short_count(howmany_max(frame))}
  local st = math.min(MAX_STACKS, math.floor(t / stack))
  local si = math.min(stack, t - st * stack)
  right.tmb_stacks_row.tmb_stacks.slider_value = st
  right.tmb_singles_row.tmb_singles.slider_value = si
  right.tmb_stacks_row.tmb_stacks_val.caption = tostring(st)
  right.tmb_singles_row.tmb_singles_val.caption = tostring(si)
end

-- `amount` (optional) pre-fills the total; otherwise it starts at one stack.
local function howmany_open(player, name, recipe, location, amount)
  howmany_close(player)
  local _, err = find_recipe(player, name, recipe)
  if err then return say(player, err) end
  local proto = prototypes.item[name]
  local stack = math.max(1, proto.stack_size)

  local frame = player.gui.screen.add{type = "frame", name = "tmb_howmany", direction = "vertical",
    tags = {item = name, recipe = recipe or "", stack = stack}}
  local bar = frame.add{type = "flow", direction = "horizontal"}
  bar.style.horizontal_spacing = 8
  bar.add{type = "label", caption = {"tmb.how-many"}, style = "frame_title", ignored_by_interaction = true}
  local drag = bar.add{type = "empty-widget", style = "draggable_space_header"}
  drag.style.height = 24
  drag.style.horizontally_stretchable = true
  drag.drag_target = frame
  bar.add{type = "sprite-button", name = "tmb_howmany_close", style = "frame_action_button",
    sprite = "utility/close", tooltip = {"tmb.close-window"}}

  -- frames can't space their children, so the spacing lives on a flow inside the frame
  local body_frame = frame.add{type = "frame", name = "tmb_body_frame", style = "inside_shallow_frame_with_padding",
    direction = "horizontal"}
  local body = body_frame.add{type = "flow", name = "tmb_body", direction = "horizontal"}
  body.style.horizontal_spacing = 8

  -- left: the item, and how many you have ("On hand" over the count, same text size)
  local left = body.add{type = "flow", direction = "vertical"}
  left.style.horizontal_align = "center"
  left.style.vertical_spacing = 0
  left.style.width = 56
  left.add{type = "sprite-button", style = "slot_button", sprite = "item/" .. name,
    elem_tooltip = {type = "item", name = name}, ignored_by_interaction = true}
  local inv = main_inventory(player)
  local have = inv and inv.get_item_count({name = name, quality = "normal"}) or 0
  left.add{type = "label", caption = {"tmb.on-hand"}}
  left.add{type = "label", caption = short_count(have)}

  -- right: stacks slider, singles slider, total + Craft (no labels; tooltips explain)
  local right = body.add{type = "flow", name = "tmb_right", direction = "vertical"}
  right.style.vertical_spacing = 4

  local r1 = right.add{type = "flow", name = "tmb_stacks_row", direction = "horizontal"}
  r1.style.vertical_align = "center"
  local s1 = r1.add{type = "slider", name = "tmb_stacks", minimum_value = 0, maximum_value = MAX_STACKS,
    value = 1, value_step = 1, discrete_values = true, tooltip = {"tmb.tip-stacks", stack}}
  local start = (amount and amount > 0) and math.floor(amount) or stack
  local start_stacks = math.min(MAX_STACKS, math.floor(start / stack))
  local start_singles = math.min(stack, start - start_stacks * stack)
  s1.slider_value = start_stacks
  s1.style.width = 110
  r1.add{type = "label", name = "tmb_stacks_val", caption = tostring(start_stacks)}.style.minimal_width = 28

  local r2 = right.add{type = "flow", name = "tmb_singles_row", direction = "horizontal"}
  r2.style.vertical_align = "center"
  local s2 = r2.add{type = "slider", name = "tmb_singles", minimum_value = 0, maximum_value = stack,
    value = start_singles, value_step = 1, discrete_values = true, tooltip = {"tmb.tip-singles", stack}}
  s2.style.width = 110
  r2.add{type = "label", name = "tmb_singles_val", caption = tostring(start_singles)}.style.minimal_width = 28

  local r3 = right.add{type = "flow", name = "tmb_total_row", direction = "horizontal"}
  r3.style.vertical_align = "center"
  r3.style.horizontal_spacing = 6
  local tf = r3.add{type = "textfield", name = "tmb_total", text = tostring(start), numeric = false,
    lose_focus_on_confirm = true, tooltip = {"tmb.tip-total", short_count((MAX_STACKS + 1) * stack)}}
  tf.style.width = 56
  local craft_btn = r3.add{type = "button", name = "tmb_howmany_craft", style = "green_button", caption = {"tmb.craft"}}
  craft_btn.style.width = 64

  -- open at the cursor, kept on screen. Not set as the "opened" window, so the
  -- inventory or crafting menu stays open next to it.
  -- Like a tooltip: below and right of the cursor, flipped above / left when it would run off the screen.
  local res, scale = player.display_resolution, player.display_scale
  local w, h, gap = 250 * scale, 170 * scale, 12 * scale
  local cx = location and location.x or res.width / 2
  local cy = location and location.y or res.height / 2
  local x = cx + gap
  if x + w > res.width then x = cx - gap - w end
  local y = cy + gap
  if y + h > res.height then y = cy - gap - h end
  x = math.max(0, math.min(x, res.width - w))
  y = math.max(0, math.min(y, res.height - h))
  frame.location = {math.floor(x), math.floor(y)}
  tf.focus()
  tf.select_all()
end

local function howmany_confirm(player)
  local frame = player.gui.screen.tmb_howmany
  if not frame then return end
  local n = howmany_total(frame)
  if not n then return say(player, {"tmb.bad-formula"}) end
  local name, recipe = frame.tags.item, frame.tags.recipe
  howmany_close(player)
  if n < 1 then return end
  craft_items(player, name, n, recipe ~= "" and recipe or nil)
end

return {
  MAX_STACKS = MAX_STACKS,
  short_count = short_count,
  howmany_close = howmany_close,
  hm_right = hm_right,
  howmany_total = howmany_total,
  evaluate = evaluate,
  howmany_sync_from_sliders = howmany_sync_from_sliders,
  howmany_sync_from_total = howmany_sync_from_total,
  howmany_open = howmany_open,
  howmany_confirm = howmany_confirm,
}
