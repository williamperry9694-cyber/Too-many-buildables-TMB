-- Too Many Buildables (TMB): the buildables panel over the quickbar.
local U = require("scripts.util")
local ALL, BLOCK_COL, CENTER_OFFSET, FIXED_H, FIXED_W, GROUP = U.ALL, U.BLOCK_COL, U.CENTER_OFFSET, U.FIXED_H, U.FIXED_W, U.GROUP
local GROUP_GAP, QBTN, SCROLLBAR, SLOT, TAB, TAB_COLS = U.GROUP_GAP, U.QBTN, U.SCROLLBAR, U.SLOT, U.TAB, U.TAB_COLS
local TOGGLE_H, TOGGLE_W, all_buildable_names, badge, before, cur_quality = U.TOGGLE_H, U.TOGGLE_W, U.all_buildable_names, U.badge, U.before, U.cur_quality
local find_side, group_sprite, is_buildable, main_inventory, pdata, quality_enabled = U.find_side, U.group_sprite, U.is_buildable, U.main_inventory, U.pdata, U.quality_enabled
local quality_list, remote_border, group_by, building_type = U.quality_list, U.remote_border, U.group_by, U.building_type
---------------------------------------------------------------------------
-- Settings and geometry
---------------------------------------------------------------------------
local function get_rows(player) return player.mod_settings["tmb-rows"].value end
local function tab_position(player) return player.mod_settings["tmb-tab-position"].value end
local function slot_layout(player) return player.mod_settings["tmb-slot-layout"].value end
local function sort_mode(player) return player.mod_settings["tmb-sort"].value end
local TAB_STRIP_GAP = 4   -- space between the tab strip (Top) and the slots

local function get_width(player)
  local v = player.mod_settings["tmb-width"].value
  if v == "auto" then
    local w = player.quick_bar_width
    if not w or w < 1 then w = 10 end
    return w
  end
  return tonumber(v) or 10
end

local function geometry(player)
  local rows, width = get_rows(player), get_width(player)
  local groups = math.ceil(width / GROUP)
  local inner_w = SLOT * width + GROUP_GAP * (groups - 1)
  -- vanilla quickbar size (what we line up with)
  local van_w, h = inner_w + FIXED_W, SLOT * rows + FIXED_H
  -- our frame: tabs (+ their scrollbar) | grid (+ its scrollbar); grows to the left.
  -- Tabs on top: a strip above the grid instead. The frame is exactly as wide as the
  -- vanilla quickbar (so it covers it and no more); the tab strip lines up with the grid,
  -- the quality buttons sit right next to them, and what's spare is on the far left.
  local tabs_at = tab_position(player)
  local tab_w = TAB * TAB_COLS + SCROLLBAR
  local top_gap = 0
  local tab_strip_cols
  local q_per_col, q_cols, q_w = 0, 0, 0
  if quality_enabled() then
    q_per_col = math.max(1, math.floor(SLOT * rows / QBTN))
    q_cols = math.ceil(#quality_list() / q_per_col)
    q_w = q_cols * QBTN + 8
  end
  local w = 4 + q_w + tab_w + 8 + inner_w + SCROLLBAR + 4
  local van_h = h
  if tabs_at == "top" then
    local narrow = 4 + q_w + inner_w + SCROLLBAR + 4
    -- +3: the vanilla frame's outer edge reaches a little past van_w (measured in-game)
    w = math.max(narrow, van_w + 3)
    top_gap = w - narrow
    h = h + TAB + TAB_STRIP_GAP
  end
  tab_strip_cols = math.max(1, math.floor(inner_w / TAB))
  local scale, res = player.display_scale, player.display_resolution
  local off_x = player.mod_settings["tmb-offset-x"].value
  local off_y = player.mod_settings["tmb-offset-y"].value
  local center_x = res.width / 2 + CENTER_OFFSET * scale + off_x
  local van_left = center_x - (van_w * scale) / 2
  local right = van_left + van_w * scale          -- keep the right edge where vanilla's is
  local left = math.floor(right - w * scale + 0.5)
  local top = res.height - math.floor(h * scale + 0.5) + off_y - remote_border(player)
  return {
    rows = rows, width = width, groups = groups, w = w, h = h, inner_w = inner_w, tab_w = tab_w,
    tabs_at = tabs_at, tab_strip_cols = tab_strip_cols, top_gap = top_gap,
    q_per_col = q_per_col, q_cols = q_cols,
    left = left, top = top,
    toggle_left = math.floor(center_x - (TOGGLE_W * scale) / 2 + 0.5),
    toggle_top = top - math.floor(TOGGLE_H * scale + 0.5),
    -- closed: the tab rests on the vanilla quickbar, which is lower than our bar with tabs on top
    toggle_top_closed = res.height - math.floor(van_h * scale + 0.5) + off_y - remote_border(player)
      - math.floor(TOGGLE_H * scale + 0.5),
    mat_toggle_left = math.floor(center_x + (TOGGLE_W / 2 + 4) * scale + 0.5)
  }
end

-- {name = total count} of buildables, quality ignored (summed).
-- What's in your hand counts too, so a slot doesn't vanish while you hold it.
local function collect(player, quality)
  local counts = {}
  local inv = main_inventory(player)
  if inv then
    for _, entry in pairs(inv.get_contents()) do
      if (entry.quality or "normal") == quality and is_buildable(entry.name) then
        counts[entry.name] = (counts[entry.name] or 0) + entry.count
      end
    end
  end
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read and cursor.quality.name == quality and is_buildable(cursor.name) then
    counts[cursor.name] = (counts[cursor.name] or 0) + cursor.count
  end
  return counts
end

---------------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------------
local function destroy_gui(player)
  local screen = player.gui.screen
  if screen.tmb_bar then screen.tmb_bar.destroy() end
  if screen.tmb_toggle then screen.tmb_toggle.destroy() end
end

local function update_visibility(player)
  local d = pdata(player)
  local screen = player.gui.screen
  if screen.tmb_toggle then
    screen.tmb_toggle.visible = not d.hidden
    screen.tmb_toggle.sprite = d.open and "tmb-arrow-up" or "tmb-arrow-down"
    screen.tmb_toggle.tooltip = d.open and {"tmb.close"} or {"tmb.open"}
    local g = geometry(player)
    screen.tmb_toggle.location = {g.toggle_left, d.open and g.toggle_top or g.toggle_top_closed}
  end
  if screen.tmb_bar then
    screen.tmb_bar.visible = d.open and not d.hidden
  end
  if screen.tmb_mat_toggle then screen.tmb_mat_toggle.visible = not d.hidden end
  local mat, track = find_side(player, "tmb_mat"), find_side(player, "tmb_track")
  if mat then mat.visible = not d.hidden end
  if track then track.visible = not d.hidden end
end

local function build_frame(player)
  destroy_gui(player)
  local d = pdata(player)
  local g = geometry(player)
  d.width = g.width
  d.list_sig = nil
  local screen = player.gui.screen

  local bar = screen.add{type = "frame", name = "tmb_bar", style = "tmb_bar_frame", direction = "horizontal"}
  bar.style.width = g.w
  bar.style.height = g.h
  bar.location = {g.left, g.top}

  local row = bar.add{type = "flow", name = "tmb_row", direction = "horizontal"}
  row.style.horizontal_spacing = 8
  -- tabs on top: everything sits flush against the right (quality | strip over grid);
  -- the spare width goes on the far left
  if g.tabs_at == "top" then
    row.style.horizontal_spacing = 4                -- quality buttons closer to the slots
    row.style.left_padding = g.top_gap + 4
  end

  -- Quality buttons: no box, stacked top to bottom; extra columns grow to the left
  if g.q_cols > 0 then
    local d_q = cur_quality(d)
    local qflow = row.add{type = "flow", name = "tmb_quality", direction = "horizontal"}
    qflow.style.horizontal_spacing = 0
    local list = quality_list()
    for c = g.q_cols, 1, -1 do
      local col = qflow.add{type = "flow", direction = "vertical"}
      col.style.vertical_spacing = 0
      for i = (c - 1) * g.q_per_col + 1, math.min(c * g.q_per_col, #list) do
        local q = list[i]
        col.add{type = "sprite-button", style = "tmb_quality_button", sprite = "quality/" .. q.name,
          tooltip = q.localised_name, tags = {tmb_quality = q.name}, toggled = (q.name == d_q)}
      end
    end
  end

  -- Category tabs: a column left or right of the grid, or a strip above it.
  -- Scrollbar space is reserved so nothing gets covered.
  local holder = row
  if g.tabs_at == "top" then
    holder = row.add{type = "flow", name = "tmb_col", direction = "vertical"}
    holder.style.vertical_spacing = TAB_STRIP_GAP
  end

  local function add_tabs()
    local tab_panel = holder.add{type = "frame", name = "tmb_tab_panel", style = "quick_bar_inner_panel"}
    local tab_scroll = tab_panel.add{type = "scroll-pane", name = "tmb_scroll", style = "tmb_scroll",
      horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space"}
    if g.tabs_at == "top" then
      tab_panel.style.width = g.inner_w + SCROLLBAR
      tab_panel.style.height = TAB
      tab_scroll.style.width = g.inner_w + SCROLLBAR
      tab_scroll.style.height = TAB
      tab_scroll.add{type = "table", name = "tmb_tabs", column_count = g.tab_strip_cols, style = "slot_table"}
    else
      tab_panel.style.width = g.tab_w
      tab_panel.style.height = SLOT * g.rows
      tab_scroll.style.width = g.tab_w
      tab_scroll.style.height = SLOT * g.rows
      tab_scroll.add{type = "table", name = "tmb_tabs", column_count = TAB_COLS, style = "slot_table"}
    end
  end

  local function add_grid()
    -- Item grid, with its scrollbar in its own space on the right
    local grid_panel = holder.add{type = "frame", name = "tmb_grid_panel", style = "quick_bar_inner_panel"}
    grid_panel.style.width = g.inner_w + SCROLLBAR
    grid_panel.style.height = SLOT * g.rows
    local grid_scroll = grid_panel.add{type = "scroll-pane", name = "tmb_scroll", style = "tmb_scroll",
      horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space"}
    grid_scroll.style.width = g.inner_w + SCROLLBAR
    grid_scroll.style.height = SLOT * g.rows
    -- one extra spacer column between each group of 5, like the vanilla quickbar
    grid_scroll.add{type = "table", name = "tmb_grid", column_count = g.width + g.groups - 1, style = "slot_table"}
  end

  if g.tabs_at == "right" then
    add_grid(); add_tabs()
  else
    add_tabs(); add_grid()
  end
  -- tabs on top: line the quality buttons up with the slots, not the tab strip
  if g.tabs_at == "top" and row.tmb_quality then
    row.tmb_quality.style.top_padding = TAB + TAB_STRIP_GAP
  end

  local toggle = screen.add{type = "sprite-button", name = "tmb_toggle", style = "tmb_toggle_button",
    sprite = "tmb-arrow-down"}
  toggle.location = {g.toggle_left, g.toggle_top}


  update_visibility(player)
end

-- The tab table, the slot table and the slot scroll-pane, wherever the tabs are.
local function panels(bar)
  local row = bar and bar.valid and bar.tmb_row
  if not row then return end
  local holder = row.tmb_col or row
  if not (holder.tmb_tab_panel and holder.tmb_grid_panel) then return end
  local grid_scroll = holder.tmb_grid_panel.tmb_scroll
  return holder.tmb_tab_panel.tmb_scroll.tmb_tabs, grid_scroll.tmb_grid, grid_scroll
end

local function reposition(player)
  local screen = player.gui.screen
  if not (screen.tmb_bar and screen.tmb_toggle) then return build_frame(player) end
  local g = geometry(player)
  screen.tmb_bar.location = {g.left, g.top}
  screen.tmb_toggle.location = {g.toggle_left, pdata(player).open and g.toggle_top or g.toggle_top_closed}
end


-- Category layout: subgroups in "newspaper" columns, like the crafting menu but
-- using the whole bar. Columns are 5 or 10 wide (lined up with the blocks of 5);
-- a leftover block becomes a narrow last column. Each subgroup starts its own row
-- and wraps inside its column if it's long. Columns are filled top to bottom.
-- Returns {pos -> name} keyed by (row-1)*width + col, and the number of rows.
local function layout_columns(subgroups, width, min_rows)
  local longest = 1
  for _, sg in ipairs(subgroups) do longest = math.max(longest, #sg) end
  local col_w = math.min(BLOCK_COL, math.ceil(longest / GROUP) * GROUP, width)
  local widths = {}
  for _ = 1, math.floor(width / col_w) do widths[#widths + 1] = col_w end
  local spare = width - #widths * col_w
  if spare >= GROUP then widths[#widths + 1] = spare end

  local function try(height)
    local cells, col, used, x = {}, 1, 0, 0
    for _, sg in ipairs(subgroups) do
      local need = math.ceil(#sg / widths[col])
      if used > 0 and used + need > height then
        x = x + widths[col]
        col, used = col + 1, 0
        if col > #widths then return nil end
        need = math.ceil(#sg / widths[col])
      end
      if need > height then return nil end
      for i, name in ipairs(sg) do
        local r = used + math.floor((i - 1) / widths[col])
        local c = x + (i - 1) % widths[col]
        cells[r * width + c + 1] = name
      end
      used = used + need
    end
    return cells
  end

  local height = min_rows
  while true do
    local cells = try(height)
    if cells then return cells, height end
    height = height + 1
  end
end

-- Compact: subgroups follow one another left to right, one empty slot apart (no gap
-- at the start of a row).
local function layout_compact(subgroups, width, min_rows)
  local cells, pos = {}, 0
  for _, sg in ipairs(subgroups) do
    if pos % width ~= 0 then pos = pos + 1 end
    for _, name in ipairs(sg) do
      pos = pos + 1
      cells[pos] = name
    end
  end
  return cells, math.max(min_rows, math.ceil(pos / width))
end

-- Columns: each subgroup fills top to bottom (bar height), then the next column; one
-- empty column between subgroups. A subgroup that doesn't fit what's left of the width
-- starts a new band of rows below (the grid scrolls down, never sideways).
local function layout_bands(subgroups, width, rows)
  local cells, L = {}, 0     -- L = column index counted across bands (band * width + x)
  for _, sg in ipairs(subgroups) do
    local ncols = math.ceil(#sg / rows)
    local x = L % width
    if x > 0 and x + ncols > width then L = L - x + width end
    for i, name in ipairs(sg) do
      local col = L + math.floor((i - 1) / rows)
      local band, c = math.floor(col / width), col % width
      local r = band * rows + (i - 1) % rows
      cells[r * width + c + 1] = name
    end
    L = L + ncols
    if L % width ~= 0 then L = L + 1 end
  end
  local bands = math.max(1, math.ceil(L / width))
  return cells, bands * rows
end

-- "All" tab: packed, in crafting-menu order.
local function layout_packed(names, width, min_rows)
  local cells = {}
  for i, name in ipairs(names) do cells[i] = name end
  return cells, math.max(min_rows, math.ceil(#names / width))
end

-- Fill tabs and grid from the current inventory. Skips work if nothing changed.
local function refresh(player, force)
  local screen = player.gui.screen
  local bar = screen.tmb_bar
  if not (bar and bar.valid) then return end
  local d = pdata(player)
  local g = geometry(player)

  local q = cur_quality(d)
  local counts = collect(player, q)

  -- everything that can appear in a category tab: every buildable in the game
  -- (researched or not) + whatever you carry
  local known = {}
  for _, name in ipairs(all_buildable_names()) do known[name] = true end
  for name in pairs(counts) do known[name] = true end

  local present, names = {}, {}
  for name in pairs(known) do
    names[#names + 1] = name
    local grp = prototypes.item[name].group
    present[grp.name] = grp
  end
  table.sort(names, before)

  local tab = d.tab
  if tab ~= ALL and not present[tab] then tab = ALL end
  local shown = {}
  for _, name in ipairs(names) do
    if tab == ALL then
      if counts[name] then shown[#shown + 1] = name end      -- "All" = what you carry
    elseif prototypes.item[name].group.name == tab then
      shown[#shown + 1] = name
    end
  end

  local groups = {}
  for _, grp in pairs(present) do groups[#groups + 1] = grp end
  table.sort(groups, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.name < b.name
  end)

  -- signature: rebuild when the layout or an item's have/have-none state changes;
  -- otherwise just update counts
  local layout, by_type = slot_layout(player), sort_mode(player) == "type"
  local parts = {tab, q, layout, by_type and "t" or "c"}
  for _, grp in ipairs(groups) do parts[#parts + 1] = grp.name end
  parts[#parts + 1] = "|"
  for _, name in ipairs(shown) do parts[#parts + 1] = name .. (counts[name] and "+" or "-") end
  local sig = table.concat(parts, ",")

  local tabs_tbl, grid = panels(bar)
  if not tabs_tbl then return end

  if force or sig ~= d.list_sig then
    d.list_sig = sig

    -- tabs: "All" first, then each group that has buildables
    tabs_tbl.clear()
    local t = tabs_tbl.add{type = "sprite-button", style = "tmb_tab_button", sprite = "utility/grid_view",
      tooltip = {"tmb.tab-all"}, tags = {tmb_tab = ALL}, toggled = (tab == ALL)}
    for _, grp in ipairs(groups) do
      tabs_tbl.add{type = "sprite-button", style = "tmb_tab_button", sprite = group_sprite(grp.name),
        tooltip = grp.localised_name, tags = {tmb_tab = grp.name}, toggled = (tab == grp.name)}
    end

    -- grid
    local cells, total_rows
    if tab == ALL or layout == "dense" then
      if by_type then shown = group_by(shown, building_type) end
      cells, total_rows = layout_packed(shown, g.width, g.rows)
    else
      -- split into subgroups (shown is already in crafting-menu order)
      local subgroups, last = {}, nil
      for _, name in ipairs(shown) do
        local sg = prototypes.item[name].subgroup.name
        if sg ~= last then subgroups[#subgroups + 1] = {}; last = sg end
        local list = subgroups[#subgroups]
        list[#list + 1] = name
      end
      if by_type then
        for i, sg in ipairs(subgroups) do subgroups[i] = group_by(sg, building_type) end
      end
      if layout == "compact" then
        cells, total_rows = layout_compact(subgroups, g.width, g.rows)
      elseif layout == "columns" then
        cells, total_rows = layout_bands(subgroups, g.width, g.rows)
      else
        cells, total_rows = layout_columns(subgroups, g.width, g.rows)
      end
    end
    total_rows = math.max(total_rows, g.rows)

    grid.clear()
    for r = 1, total_rows do
      for c = 1, g.width do
        if c > 1 and (c - 1) % GROUP == 0 then
          local gap = grid.add{type = "empty-widget"}
          gap.style.width = GROUP_GAP
          gap.style.height = SLOT
        end
        local name = cells[(r - 1) * g.width + c]
        if name and counts[name] then
          grid.add{type = "sprite-button", style = "slot_button", sprite = "item/" .. name,
            number = counts[name], quality = badge(q),
            elem_tooltip = {type = "item-with-quality", name = name, quality = q},
            tags = {tmb_item = name}, mouse_button_filter = {"left", "right"}}
        elseif name then
          -- none on you: item icon with a dark layer over it
          local b = grid.add{type = "sprite-button", style = "slot_button",
            elem_tooltip = {type = "item-with-quality", name = name, quality = q},
            tags = {tmb_item = name, tmb_zero = true}, mouse_button_filter = {"left", "right"}}
          local icon = b.add{type = "sprite", sprite = "item/" .. name, resize_to_sprite = false,
            ignored_by_interaction = true}
          icon.style.size = 32
          icon.style.stretch_image_to_widget_size = true
          local dim = b.add{type = "sprite", sprite = "tmb-dim", resize_to_sprite = false,
            ignored_by_interaction = true}
          dim.style.size = 32
          dim.style.left_margin = -32
          dim.style.stretch_image_to_widget_size = true
          if badge(q) then
            local qb = b.add{type = "sprite", sprite = "quality/" .. q, resize_to_sprite = false,
              ignored_by_interaction = true}
            qb.style.size = 14
            qb.style.left_margin = -32
            qb.style.top_margin = 18
            qb.style.stretch_image_to_widget_size = true
          end
        else
          grid.add{type = "sprite-button", style = "slot_button", mouse_button_filter = {"left"}}
        end
      end
    end
  else
    -- same layout: only the numbers can have changed
    for _, el in pairs(grid.children) do
      local name = el.tags and el.tags.tmb_item
      if name and not el.tags.tmb_zero and el.number ~= counts[name] then el.number = counts[name] end
    end
  end
end

---------------------------------------------------------------------------
-- Hidden by the game? (cutscenes, quickbar / controller GUI turned off)
---------------------------------------------------------------------------
local function game_hides_quickbar(player)
  if player.controller_type == defines.controllers.cutscene then return true end
  local gvs = player.game_view_settings
  return not gvs.show_quickbar or not gvs.show_controller_gui
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function toggle(player)
  local d = pdata(player)
  d.open = not d.open
  if d.open then
    if get_width(player) ~= d.width or not player.gui.screen.tmb_bar then build_frame(player) end
    refresh(player, true)
  end
  update_visibility(player)
end

return {
  get_rows = get_rows,
  get_width = get_width,
  geometry = geometry,
  collect = collect,
  destroy_gui = destroy_gui,
  update_visibility = update_visibility,
  build_frame = build_frame,
  reposition = reposition,
  layout_columns = layout_columns,
  layout_packed = layout_packed,
  layout_compact = layout_compact,
  layout_bands = layout_bands,
  panels = panels,
  refresh = refresh,
  game_hides_quickbar = game_hides_quickbar,
  toggle = toggle,
}
