-- Too Many Buildables (TMB): the Materials side panel and its Track menu.
local U = require("scripts.util")
local QBTN, SCROLLBAR, SLOT, TAB, TOGGLE_H, TOGGLE_W = U.QBTN, U.SCROLLBAR, U.SLOT, U.TAB, U.TOGGLE_H, U.TOGGLE_W
local add_item_slot, before, cur_quality, destroy_side, find_side, group_sprite = U.add_item_slot, U.before, U.cur_quality, U.destroy_side, U.find_side, U.group_sprite
local is_buildable, main_inventory, pdata, quality_enabled, quality_list = U.is_buildable, U.main_inventory, U.pdata, U.quality_enabled, U.quality_list
local remote_border = U.remote_border
local C = require("scripts.crafting")
local craft, pick = C.craft, C.pick
local mod_gui = require("mod-gui")
local shared = require("scripts.shared")
---------------------------------------------------------------------------
-- Materials side panel (intermediates and crafting materials)
---------------------------------------------------------------------------
-- Everything that isn't a buildable counts as a material, except tools like
-- blueprints and planners.
local NOT_MATERIAL = {
  ["blueprint"] = true, ["blueprint-book"] = true, ["deconstruction-item"] = true,
  ["upgrade-item"] = true, ["selection-tool"] = true, ["copy-paste-tool"] = true,
  ["spidertron-remote"] = true
}
local material_cache = {}
local function is_material(name)
  local c = material_cache[name]
  if c ~= nil then return c end
  local p = prototypes.item[name]
  local ok = p ~= nil and not p.hidden and not p.parameter and not is_buildable(name) and not NOT_MATERIAL[p.type]
  material_cache[name] = ok
  return ok
end

local all_materials = nil
local function all_material_names()
  if all_materials then return all_materials end
  all_materials = {}
  for name in pairs(prototypes.item) do
    if is_material(name) then all_materials[#all_materials + 1] = name end
  end
  table.sort(all_materials, before)
  return all_materials
end

-- Counts every item you carry (any type), so whatever you put in the Custom bar
-- -- pipes, buildings, ammo -- shows its real count.
local function collect_materials(player, quality)
  local counts = {}
  local inv = main_inventory(player)
  if inv then
    for _, entry in pairs(inv.get_contents()) do
      if (entry.quality or "normal") == quality then
        counts[entry.name] = (counts[entry.name] or 0) + entry.count
      end
    end
  end
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read and cursor.quality.name == quality then
    counts[cursor.name] = (counts[cursor.name] or 0) + cursor.count
  end
  return counts
end

local CUSTOM = "__custom__"

-- Sorting by item type inside each Materials section. The type is read from the item's
-- internal name: the first word that names a kind of item (iron-PLATE, angels-PLATE-iron,
-- angels-WIRE-coil-gold, processing-UNIT ...). Works the same for any mod.
local TYPE_WORDS = {}
for _, w in ipairs({
  "ore", "chunk", "crushed", "crystal", "dust", "powder", "pellet", "slag", "sand", "slurry",
  "plate", "sheet", "ingot", "bar", "brick", "block", "billet",
  "rod", "stick", "beam", "pipe", "tube",
  "wire", "cable", "coil", "roll", "foil",
  "gear", "bearing", "ball", "spring", "bolt",
  "circuit", "board", "chip", "processor", "transistor", "resistor", "capacitor",
  "unit", "frame", "motor", "battery", "cell",
  "pack", "fuel", "glass", "catalyst", "filter", "canister", "barrel", "seed", "sapling"
}) do TYPE_WORDS[w] = true end

local item_type_cache = {}
local function item_type(name)
  local t = item_type_cache[name]
  if t then return t end
  t = false
  for token in name:gmatch("[^%-]+") do
    if TYPE_WORDS[token] then t = token; break end
  end
  item_type_cache[name] = t
  return t
end

-- Reorder a list that is already in crafting order: same-type items are pulled together,
-- types appear in the order they first show up, and inside a type crafting order is kept.
-- Items with no type word stay where they are, on their own.
local function sort_by_type(list)
  return U.group_by(list, item_type)
end
local EQUIP_H = 96        -- vanilla armour/weapons panel height (GUI px), measured
local SIDE_CHROME_H = 40  -- frame padding top 4 + title bar 24 + gap 4 + padding bottom 8 (GUI px)
local SIDE_CHROME_W = 16  -- frame padding left + right (GUI px)
local STRIP_H = 24

local function mat_mode(player) return player.mod_settings["tmb-mat-position"].value end

local function mat_defaults(d)
  d.custom = d.custom or {}
  d.collapsed = d.collapsed or {}
  if d.mat_locked == nil then d.mat_locked = true end
end

local function mat_width(player) return player.mod_settings["tmb-mat-width"].value end

-- "raw-resource" -> "Raw resource" (subgroups have no translated names in most mods)
local function pretty(sg_name)
  local t = sg_name:gsub("-", " ")
  return t:sub(1, 1):upper() .. t:sub(2)
end

-- Offsets from the settings, plus the Remote View border: x already moved in from the
-- left; the third value is for modes anchored to the bottom edge.
local function mat_offsets(player)
  local b = remote_border(player)
  return player.mod_settings["tmb-mat-offset-x"].value + b, player.mod_settings["tmb-mat-offset-y"].value, b
end

-- How much body height (GUI px) a side window may use in the current mode.
local MAX_ROWS = 10      -- side windows stop growing at 10 rows, then scroll
local function side_body_cap(player)
  local screen_h = player.display_resolution.height / player.display_scale
  local room = screen_h - SIDE_CHROME_H - 16
  if mat_mode(player) == "equipment" then room = room - EQUIP_H end
  return math.max(SLOT * 2, math.min(MAX_ROWS * SLOT, room))
end

-- Put the Track menu next to the Materials panel (screen modes).
-- Side windows get an exact size set on them (not estimated), so anchoring and the
-- attached tab line up precisely. Returns width/height in GUI px.
local function side_size(frame, player, content_h, extra_h)
  -- quality buttons that wrap onto extra title-bar rows make the title bar taller
  local tb = frame.tmb_titlebar
  if tb then
    for _, child in pairs(tb.children) do
      if child.type == "table" then
        local rows = math.ceil(#child.children / child.column_count)
        if rows > 1 then extra_h = (extra_h or 0) + (rows * QBTN - 24) end
      end
    end
  end
  local cap = side_body_cap(player) - (extra_h or 0)
  local body = math.max(0, math.min(content_h or 0, cap))
  local scrolls = (content_h or 0) > cap
  local w = mat_width(player) * SLOT + SIDE_CHROME_W + SCROLLBAR
  local h = body + SIDE_CHROME_H + (extra_h or 0)
  frame.style.width = w
  frame.style.height = h
  local scroll = frame.tmb_scroll
  scroll.style.width = w - SIDE_CHROME_W
  scroll.style.height = body
  scroll.vertical_scroll_policy = scrolls and "always" or "auto-and-reserve-space"
  return w, h
end

local function track_place(player)
  local track = find_side(player, "tmb_track")
  if not track then return end
  local d = pdata(player)
  local w, h = side_size(track, player, d.track_content_h, d.track_tabs_h)
  if not (track.parent == player.gui.screen and d.mat_x) then return end
  local scale, res = player.display_scale, player.display_resolution
  local h_px = h * scale
  local x = d.mat_x + d.mat_w_px + math.floor(8 * scale)
  local y
  if mat_mode(player) == "equipment" then
    y = d.mat_y + d.mat_h_px - h_px          -- bottoms line up, grows upward
  else
    y = d.mat_y                              -- tops line up
  end
  y = math.max(0, math.min(y, res.height - h_px))
  track.location = {math.floor(x + 0.5), math.floor(y + 0.5)}
end

local mat_toggle_place   -- defined below; mat_place moves the tab along with the panel

-- Anchor the Materials panel for the selected mode, using its computed height.
local function mat_place(player)
  local frame = find_side(player, "tmb_mat")
  if not frame then return end
  local d = pdata(player)
  local w, h = side_size(frame, player, d.mat_content_h)
  if frame.parent ~= player.gui.screen then       -- "below GUI Unifier": the game places it
    track_place(player)
    return
  end
  local scale, res = player.display_scale, player.display_resolution
  local mode = mat_mode(player)
  local h_px, w_px = h * scale, w * scale
  local off_x, off_y, border = mat_offsets(player)
  local x, y
  if mode == "equipment" then
    x = off_x
    y = res.height - EQUIP_H * scale - h_px + off_y - border
  elseif mode == "center" then
    -- centred on the screen's middle, where the arrow tab sits: grows up and down evenly
    x = off_x
    y = (res.height - h_px) / 2 + off_y
  else -- free
    local loc = d.mat_loc or {x = 0, y = math.floor(res.height * 0.25)}
    x, y = loc.x or loc[1], loc.y or loc[2]
  end
  x = math.max(0, math.min(x, res.width - w_px))
  y = math.max(0, math.min(y, res.height - h_px))
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  frame.location = {x, y}
  d.mat_x, d.mat_y, d.mat_w_px, d.mat_h_px = x, y, w_px, h_px
  track_place(player)
  mat_toggle_place(player)
end

-- The Materials panel collapses like the toolbelt: a small arrow tab stays attached
-- to it. In "below GUI Unifier" mode the toggle is a button in the mod button bar.
function mat_toggle_place(player)
  local d = pdata(player)
  local screen = player.gui.screen
  local mode = mat_mode(player)
  if mode == "gui-unifier" then
    if screen.tmb_mat_toggle then screen.tmb_mat_toggle.destroy() end
    local bflow = mod_gui.get_button_flow(player)
    if not bflow.tmb_mat_toggle then
      bflow.add{type = "sprite-button", name = "tmb_mat_toggle", style = mod_gui.button_style,
        sprite = "tmb-list", tooltip = {"tmb.mat-toggle"}}
    end
    return
  end
  -- other modes: remove our button from the mod button bar if it's there,
  -- without creating the bar (mod-gui would add an empty frame otherwise)
  local top = player.gui.top
  local bflow = top.mod_gui_button_flow
    or (top.mod_gui_top_frame and top.mod_gui_top_frame.mod_gui_inner_frame)
  if bflow and bflow.tmb_mat_toggle then bflow.tmb_mat_toggle.destroy() end

  local upright = (mode == "center")
  local style = upright and "tmb_toggle_button_v" or "tmb_toggle_button"
  local tab = screen.tmb_mat_toggle
  if tab and tab.style.name ~= style then tab.destroy(); tab = nil end
  if not tab then
    tab = screen.add{type = "sprite-button", name = "tmb_mat_toggle", style = style, tooltip = {"tmb.mat-toggle"}}
  end
  local scale, res = player.display_scale, player.display_resolution
  local off_x, off_y, border = mat_offsets(player)
  local tw = (upright and TOGGLE_H or TOGGLE_W) * scale
  local th = (upright and TOGGLE_W or TOGGLE_H) * scale
  local open = d.mat_open and d.mat_x ~= nil
  local x, y, sprite
  if mode == "equipment" then
    -- rests on the equipment panel; on top of the Materials panel when open
    x = open and d.mat_x or off_x
    y = open and (d.mat_y - th) or (res.height - EQUIP_H * scale - th + off_y - border)
    sprite = open and "tmb-arrow-down" or "tmb-arrow-up"
  elseif mode == "center" then
    -- on the left edge mid-screen; against the panel's right side when open
    x = open and (d.mat_x + d.mat_w_px) or off_x
    y = (res.height - th) / 2 + off_y
    sprite = open and "tmb-arrow-left" or "tmb-arrow-right"
  else -- free: on top of the panel
    local loc = d.mat_loc or {x = 0, y = math.floor(res.height * 0.25)}
    x = open and d.mat_x or (loc.x or loc[1])
    y = (open and d.mat_y or (loc.y or loc[2])) - th
    sprite = open and "tmb-arrow-up" or "tmb-arrow-down"
  end
  x = math.max(0, math.min(x, res.width - tw))
  y = math.max(0, math.min(y, res.height - th))
  tab.location = {math.floor(x + 0.5), math.floor(y + 0.5)}
  tab.sprite = sprite
  tab.tooltip = open and {"tmb.mat-close"} or {"tmb.mat-toggle"}
  tab.visible = not d.hidden
end


-- Vanilla-style title bar: title, drag area, small icon buttons.
local function add_titlebar(frame, caption, draggable, buttons, quality)
  local bar = frame.add{type = "flow", name = "tmb_titlebar", direction = "horizontal"}
  bar.style.horizontal_spacing = 8
  bar.style.vertical_align = "center"
  if caption then
    bar.add{type = "label", caption = caption, style = "frame_title", ignored_by_interaction = true}
  end
  local drag = bar.add{type = "empty-widget", style = "draggable_space_header"}
  drag.style.height = 24
  drag.style.horizontally_stretchable = true
  drag.style.right_margin = 4
  if draggable then
    bar.drag_target = frame
    drag.drag_target = frame
  end
  if quality then
    local qt = bar.add{type = "table", column_count = quality.per_row, style = "slot_table"}
    for _, q in ipairs(quality_list()) do
      qt.add{type = "sprite-button", style = "tmb_quality_button", sprite = "quality/" .. q.name,
        tooltip = q.localised_name, tags = {tmb_mat_quality = q.name}, toggled = (q.name == quality.selected)}
    end
  end
  for _, b in ipairs(buttons) do
    bar.add{type = "sprite-button", name = b.name, style = "frame_action_button", sprite = b.sprite,
      tooltip = b.tooltip, mouse_button_filter = {"left"}}
  end
end

-- A collapsible section: a clickable strip, then a grid (unless collapsed).
local function add_section(parent, key, caption, collapsed, width)
  local strip = parent.add{type = "frame", style = "tmb_strip_frame", direction = "horizontal"}
  local arrow = collapsed and "tmb-arrow-right" or "tmb-arrow-down"
  strip.add{type = "button", style = "tmb_strip_button", caption = {"", "[img=" .. arrow .. "] ", caption},
    tags = {tmb_strip = key}, mouse_button_filter = {"left"}}
  if collapsed then return nil end
  return parent.add{type = "table", column_count = width, style = "slot_table"}
end

---------------------------------------------------------------------------
-- Ghost Project section (filled by the built-in Casper when a craft for its ghosts comes up short)
---------------------------------------------------------------------------
local GP = "__ghost_project__"
-- Plain game ticks. Mods can't read real time (multiplayer must stay in sync), and the game speed
-- setting can be far from the speed the game actually reaches, so timing doesn't try to follow it.
local GP_HOLD_TICKS = 240       -- an auto-opened panel stays this long (4 s at normal speed)
local GP_BLINK_TICKS = 15       -- one red or plain phase of a blink
local GP_BLINK_PHASES = 6       -- red, plain, red, plain, red, plain
local GP_USES_SHOWN = 8         -- per-building lines in the tooltip before "and N more"

local function item_name(name)
  local p = prototypes.item[name]
  return p and p.localised_name or name
end

local function gp_tooltip(entry)
  local lines = {""}
  local uses = entry.uses or {}
  for i, u in ipairs(uses) do
    if i > GP_USES_SHOWN then
      lines[#lines + 1] = {"", "\n", {"tmb.gp-more", #uses - GP_USES_SHOWN}}
      break
    end
    lines[#lines + 1] = {"", "\n", {"tmb.gp-use", u.count, item_name(u.name), u.amount}}
  end
  return {"", "[font=default-bold]", item_name(entry.name), "[/font]\n",
    {"tmb.gp-need", entry.need, entry.have, entry.missing}, lines, "\n", {"tmb.gp-clears"},
    "\n", {"tmb.divider"}, "\n", {"tmb.gp-shortcuts"}}
end

-- Is this Ghost Project slot red right now (mid-blink)?
local function gp_red(d, name)
  local b = d.gp_blink
  if not (b and b.names[name]) then return false end
  local phase = math.floor((game.tick - b.start) / b.step)
  return phase < GP_BLINK_PHASES and phase % 2 == 0
end

local function mat_refresh(player, force)
  local frame = find_side(player, "tmb_mat")
  if not (frame and frame.valid) then return end
  local d = pdata(player)
  mat_defaults(d)
  local q = cur_quality(d, "mat_quality")
  local counts = collect_materials(player, q)
  -- nothing is tracked until you pick it in the Track menu
  d.tracked = d.tracked or {}
  local width = mat_width(player)

  -- tracked items, in crafting-menu order: one section per crafting-menu tab (item group),
  -- packed into full rows (subgroups don't start new rows here; the Track menu keeps them)
  local names = {}
  for name in pairs(d.tracked) do
    if prototypes.item[name] and is_material(name) then names[#names + 1] = name end
  end
  table.sort(names, before)
  local sections, last_g, last_sg = {}, nil, nil
  for _, name in ipairs(names) do
    local p = prototypes.item[name]
    local g, sg = p.group, p.subgroup.name
    if g.name ~= last_g then
      sections[#sections + 1] = {key = "g:" .. g.name, group = g, rows = {}}
      last_g, last_sg = g.name, nil
    end
    local sec = sections[#sections]
    if not sec.rows[1] then sec.rows[1] = {} end
    local row = sec.rows[1]
    row[#row + 1] = name
  end
  local by_type = player.mod_settings["tmb-mat-sort"].value == "type"
  for _, sec in ipairs(sections) do
    if sec.rows[1] and by_type then sec.rows[1] = sort_by_type(sec.rows[1]) end
  end
  local custom = {}
  for _, name in ipairs(d.custom) do
    if prototypes.item[name] then custom[#custom + 1] = name end
  end
  local gp = shared.ghost_project and shared.ghost_project(player) or {}

  -- rebuild only when something other than a count changed
  local parts = {width, q}
  for _, name in ipairs(custom) do parts[#parts + 1] = name .. (counts[name] and "+" or "-") end
  parts[#parts + 1] = d.collapsed[CUSTOM] and "C" or "c"
  parts[#parts + 1] = "|gp" .. (d.collapsed[GP] and "C" or "c")
  for _, e in ipairs(gp) do parts[#parts + 1] = e.name end
  for _, sec in ipairs(sections) do
    parts[#parts + 1] = "|" .. sec.key .. (d.collapsed[sec.key] and "C" or "c")
    for _, row in ipairs(sec.rows) do
      parts[#parts + 1] = "/"
      for _, name in ipairs(row) do parts[#parts + 1] = name .. (counts[name] and "+" or "-") end
    end
  end
  local sig = table.concat(parts, ",")
  local inner = frame.tmb_scroll.tmb_inner

  if not force and sig == d.mat_sig then
    for _, child in pairs(inner.children) do
      if child.type == "table" then
        for _, el in pairs(child.children) do
          local name = el.tags and el.tags.tmb_mat
          if name and el.tags.tmb_gp then
            for _, e in ipairs(gp) do
              if e.name == name then
                if el.number ~= e.missing then el.number = e.missing end
                el.tooltip = gp_tooltip(e)
              end
            end
          elseif name and not el.tags.tmb_zero and el.number ~= counts[name] then
            el.number = counts[name]
          end
        end
      end
    end
    return
  end
  d.mat_sig = sig
  inner.clear()
  local content_h = 0

  -- Custom bar (your own picks) with a [+] slot that opens the game's item picker
  local tbl = add_section(inner, CUSTOM, {"", "[color=255,200,120]", {"tmb.custom"}, "[/color]"},
    d.collapsed[CUSTOM], width)
  content_h = content_h + STRIP_H
  if tbl then
    content_h = content_h + math.ceil((#custom + 1) / width) * SLOT
    for i, name in ipairs(custom) do
      add_item_slot(tbl, name, counts[name], {tmb_mat = name, tmb_custom = i}, q)
    end
    tbl.add{type = "choose-elem-button", elem_type = "item", style = "slot_button",
      tooltip = {"tmb.custom-add"}, tags = {tmb_custom_add = true}}
  end

  -- Ghost Project: what the Casper job is short of (badge = how many you're missing)
  if #gp > 0 then
    local caption = {"", "[img=item/tmb-casper-tool] [color=140,255,140]", {"tmb.gp-title"}, "[/color]"}
    local grid = add_section(inner, GP, caption, d.collapsed[GP], width)
    content_h = content_h + STRIP_H
    if grid then
      content_h = content_h + math.ceil(#gp / width) * SLOT
      for _, e in ipairs(gp) do
        grid.add{type = "sprite-button", style = gp_red(d, e.name) and "red_slot_button" or "slot_button",
          sprite = "item/" .. e.name, number = e.missing, tooltip = gp_tooltip(e),
          tags = {tmb_mat = e.name, tmb_gp = true}, mouse_button_filter = {"left", "right"}}
      end
    end
  end

  -- tracked items, one section per crafting-menu tab
  for _, sec in ipairs(sections) do
    local g = sec.group
    local icon = helpers.is_valid_sprite_path("item-group/" .. g.name) and ("  [img=item-group/" .. g.name .. "]") or ""
    local grid = add_section(inner, sec.key, {"", g.localised_name, icon}, d.collapsed[sec.key], width)
    content_h = content_h + STRIP_H
    if grid then
      for _, row in ipairs(sec.rows) do
        for _, name in ipairs(row) do add_item_slot(grid, name, counts[name], {tmb_mat = name}, q) end
        -- pad the rest of the line so the next subgroup starts a new row
        local used = #row % width
        if used > 0 then
          for _ = used + 1, width do
            local gap = grid.add{type = "empty-widget"}
            gap.style.size = SLOT
          end
        end
        content_h = content_h + math.ceil(#row / width) * SLOT
      end
    end
  end
  if #sections == 0 and #gp == 0 then
    local hint = inner.add{type = "label", caption = {"tmb.mat-empty"}}
    hint.style.single_line = false
    hint.style.width = width * SLOT - 16
    hint.style.height = 72
    hint.style.margin = 8
    hint.style.vertical_align = "top"
    content_h = content_h + 72 + 16
  end
  d.mat_content_h = content_h
  mat_place(player)
end

local function mat_build(player)
  destroy_side(player, "tmb_mat")
  local d = pdata(player)
  mat_defaults(d)
  local mode = mat_mode(player)
  local parent = (mode == "gui-unifier") and mod_gui.get_frame_flow(player) or player.gui.screen
  local frame = parent.add{type = "frame", name = "tmb_mat", direction = "vertical", style = "tmb_side_frame",
    raise_hover_events = true, tags = {tmb_mat_frame = true}}
  local free = (mode == "free")
  local buttons = {{name = "tmb_mat_track", sprite = "tmb-list", tooltip = {"tmb.track-open"}}}
  if free then
    buttons[#buttons + 1] = {name = "tmb_mat_lock", sprite = d.mat_locked and "tmb-lock" or "tmb-unlock",
      tooltip = d.mat_locked and {"tmb.unlock"} or {"tmb.lock"}}
  end
  buttons[#buttons + 1] = {name = "tmb_mat_collapse_all", sprite = "tmb-arrow-up", tooltip = {"tmb.collapse-all"}}
  -- quality buttons in the title bar; the "Materials" title is dropped if they wouldn't fit
  local caption, quality = {"tmb.materials"}, nil
  if quality_enabled() then
    local avail = mat_width(player) * SLOT + SCROLLBAR          -- title bar width (GUI px)
    local btns = #buttons * (24 + 8)
    local nq = #quality_list()
    local per_row = math.max(1, math.min(nq, math.floor((avail - btns - 8) / QBTN)))
    quality = {per_row = per_row, selected = cur_quality(d, "mat_quality")}
    if avail - btns - 8 - math.min(nq, per_row) * QBTN < 90 then caption = nil end
  end
  add_titlebar(frame, caption, free and not d.mat_locked and parent == player.gui.screen, buttons, quality)
  local scroll = frame.add{type = "scroll-pane", name = "tmb_scroll", style = "tmb_scroll",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"}
  scroll.style.maximal_height = side_body_cap(player)
  scroll.add{type = "frame", name = "tmb_inner", style = "inside_deep_frame", direction = "vertical"}
  d.mat_sig = nil
  frame.visible = not d.hidden
  mat_refresh(player, true)
end

-- Track menu: every material, by group tab and subgroup; click to track/untrack.
local function track_build(player)
  destroy_side(player, "tmb_track")
  local screen = player.gui.screen
  local d = pdata(player)
  if not (d.mat_open and d.track_open) then return end
  mat_defaults(d)
  local width = mat_width(player)
  d.tracked = d.tracked or {}

  -- groups and subgroups of all materials
  local groups, by_group = {}, {}
  for _, name in ipairs(all_material_names()) do
    local p = prototypes.item[name]
    local g = p.group
    if not by_group[g.name] then
      by_group[g.name] = {}
      groups[#groups + 1] = g
    end
    local list = by_group[g.name]
    local sg = p.subgroup.name
    if not (list[#list] and list[#list].key == sg) then list[#list + 1] = {key = sg, names = {}} end
    local sec = list[#list]
    sec.names[#sec.names + 1] = name
  end
  if #groups == 0 then return end
  local tab = d.track_tab
  if not by_group[tab] then tab = groups[1].name end
  d.track_tab = tab

  local in_flow = (mat_mode(player) == "gui-unifier")
  local parent = in_flow and mod_gui.get_frame_flow(player) or screen
  local frame = parent.add{type = "frame", name = "tmb_track", direction = "vertical", style = "tmb_side_frame"}
  add_titlebar(frame, {"tmb.track"}, not in_flow, {
    {name = "tmb_track_close", sprite = "utility/close", tooltip = {"tmb.track-close"}}
  })

  local per_row = math.max(1, math.floor((width * SLOT) / TAB))
  local tabs = frame.add{type = "table", column_count = per_row, style = "slot_table"}
  d.track_tabs_h = math.ceil(#groups / per_row) * TAB + 4 + 4
  for _, g in ipairs(groups) do
    tabs.add{type = "sprite-button", style = "tmb_tab_button", sprite = group_sprite(g.name),
      tooltip = g.localised_name, tags = {tmb_track_tab = g.name}, toggled = (g.name == tab)}
  end

  local scroll = frame.add{type = "scroll-pane", name = "tmb_scroll", style = "tmb_scroll",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"}
  scroll.style.maximal_height = side_body_cap(player)
  local inner = scroll.add{type = "frame", style = "inside_deep_frame", direction = "vertical"}
  local content_h = 0

  for _, sec in ipairs(by_group[tab]) do
    local all_on = true
    for _, name in ipairs(sec.names) do if not d.tracked[name] then all_on = false; break end end
    local strip = inner.add{type = "frame", style = "tmb_strip_frame", direction = "horizontal"}
    local label = strip.add{type = "label", caption = pretty(sec.key), style = "subheader_caption_label"}
    label.style.left_padding = 4
    local push = strip.add{type = "empty-widget"}
    push.style.horizontally_stretchable = true
    strip.add{type = "checkbox", state = all_on, tooltip = {"tmb.track-subgroup"},
      tags = {tmb_track_sg = sec.key, tmb_track_group = tab}}
    local grid = inner.add{type = "table", column_count = width, style = "slot_table"}
    content_h = content_h + STRIP_H + math.ceil(#sec.names / width) * SLOT
    for _, name in ipairs(sec.names) do
      local b = add_item_slot(grid, name, nil, {tmb_track_item = name})
      b.children[2].visible = not d.tracked[name]     -- dim layer = not tracked
    end
  end
  d.track_content_h = content_h
  frame.visible = not d.hidden
  track_place(player)
end

-- Update the Track menu in place (no rebuild), so its scroll position is kept.
local function track_sync_grid(grid, d)
  local all_on = true
  for _, b in pairs(grid.children) do
    local name = b.tags and b.tags.tmb_track_item
    if name then
      local on = d.tracked[name] == true
      b.children[2].visible = not on
      if not on then all_on = false end
    end
  end
  -- the subgroup's strip sits right before its grid; its checkbox is the last child
  local inner, prev = grid.parent, nil
  for _, child in pairs(inner.children) do
    if child == grid then break end
    prev = child
  end
  if prev then
    local kids = prev.children
    local box = kids[#kids]
    if box and box.type == "checkbox" then box.state = all_on end
  end
end

local function mat_set_open(player, open)
  local d = pdata(player)
  d.mat_open = open
  d.gp_auto = nil
  local screen = player.gui.screen
  if open then
    mat_build(player)
    track_build(player)
  else
    destroy_side(player, "tmb_mat")
    destroy_side(player, "tmb_track")
    d.mat_x = nil
  end
  mat_toggle_place(player)
end

local function mat_click(player, e, tags)
  local d = pdata(player)
  local name = tags.tmb_mat
  local q = cur_quality(d, "mat_quality")
  local left = e.button == defines.mouse_button_type.left
  local right = e.button == defines.mouse_button_type.right
  if left and e.shift and e.control then
    craft(player, name, nil, q)
  elseif left and e.shift then
    craft(player, name, 1, q)
  elseif right and e.shift then
    craft(player, name, 5, q)
  elseif right and tags.tmb_custom then
    table.remove(d.custom, tags.tmb_custom)       -- right-click removes from the Custom bar
    mat_refresh(player, true)
  elseif left then
    pick(player, name, true, q)
  end
end

local function add_custom(player, name)
  local d = pdata(player)
  mat_defaults(d)
  for _, n in ipairs(d.custom) do if n == name then return end end
  d.custom[#d.custom + 1] = name
end

-- A craft for the Casper job came up short: blink the missing Ghost Project slots red and, if the
-- Materials panel was closed, open it for a few seconds. Repeated fails restart the blink and the timer.
local function gp_alert(player, names)
  local d = pdata(player)
  local set = {}
  for _, n in pairs(names) do set[n] = true end
  d.gp_blink = {names = set, start = game.tick, step = GP_BLINK_TICKS, phase = -1}
  if not d.mat_open then
    mat_set_open(player, true)
    d.gp_auto = true
  end
  if d.gp_auto then d.gp_close_at = game.tick + GP_HOLD_TICKS end
  mat_refresh(player, true)
  storage.gp_active = storage.gp_active or {}
  storage.gp_active[player.index] = true
end
shared.gp_alert = gp_alert

-- Hovering or clicking an auto-opened panel keeps it open (it's yours to close from then on).
local function gp_keep(player)
  local d = pdata(player)
  d.gp_auto = nil
end

local function gp_set_styles(player, d, red)
  local frame = find_side(player, "tmb_mat")
  if not (frame and frame.valid) then return end
  for _, child in pairs(frame.tmb_scroll.tmb_inner.children) do
    if child.type == "table" then
      for _, el in pairs(child.children) do
        local t = el.tags
        if t and t.tmb_gp and d.gp_blink.names[t.tmb_mat] then
          el.style = red and "red_slot_button" or "slot_button"
        end
      end
    end
  end
end

-- Every tick, only for players with a blink or an auto-open running.
local function gp_tick(tick)
  local active = storage.gp_active
  if not (active and next(active)) then return end
  for index in pairs(active) do
    local player = game.get_player(index)
    local d = player and storage.players and storage.players[index]
    if not (d and player.valid) then
      active[index] = nil
    else
      local b = d.gp_blink
      -- timers saved by 0.9.4/0.9.5 followed the game speed setting and could be minutes long
      if b and b.step > GP_BLINK_TICKS then b.step = GP_BLINK_TICKS end
      if d.gp_close_at and d.gp_close_at > tick + GP_HOLD_TICKS then d.gp_close_at = tick + GP_HOLD_TICKS end
      if b then
        local phase = math.floor((tick - b.start) / b.step)
        if phase ~= b.phase then
          b.phase = phase
          if phase >= GP_BLINK_PHASES then
            gp_set_styles(player, d, false)
            d.gp_blink = nil
          else
            gp_set_styles(player, d, phase % 2 == 0)
          end
        end
      end
      if d.gp_auto and tick >= (d.gp_close_at or 0) then
        mat_set_open(player, false)
      end
      if not d.gp_blink and not d.gp_auto then active[index] = nil end
    end
  end
end

return {
  gp_alert = gp_alert,
  gp_keep = gp_keep,
  gp_tick = gp_tick,
  mod_gui = mod_gui,
  NOT_MATERIAL = NOT_MATERIAL,
  material_cache = material_cache,
  is_material = is_material,
  all_materials = all_materials,
  all_material_names = all_material_names,
  collect_materials = collect_materials,
  CUSTOM = CUSTOM,
  TYPE_WORDS = TYPE_WORDS,
  item_type_cache = item_type_cache,
  item_type = item_type,
  sort_by_type = sort_by_type,
  EQUIP_H = EQUIP_H,
  SIDE_CHROME_H = SIDE_CHROME_H,
  SIDE_CHROME_W = SIDE_CHROME_W,
  STRIP_H = STRIP_H,
  mat_mode = mat_mode,
  mat_defaults = mat_defaults,
  mat_width = mat_width,
  pretty = pretty,
  mat_offsets = mat_offsets,
  MAX_ROWS = MAX_ROWS,
  side_body_cap = side_body_cap,
  side_size = side_size,
  track_place = track_place,
  mat_toggle_place = mat_toggle_place,
  mat_place = mat_place,
  add_titlebar = add_titlebar,
  add_section = add_section,
  mat_refresh = mat_refresh,
  mat_build = mat_build,
  track_build = track_build,
  track_sync_grid = track_sync_grid,
  mat_set_open = mat_set_open,
  mat_click = mat_click,
  add_custom = add_custom,
}
