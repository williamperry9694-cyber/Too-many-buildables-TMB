-- Casper: Ghost Tracking, built into TMB.
-- Same as the standalone mod (casper-ghost-tracking 0.8.0), with tmb- names so the two never clash.
-- control.lua only loads this file when the standalone Casper is not active.

local events = require("scripts.events")
local shared = require("scripts.shared")  -- TMB crafting and quality helpers
local U = require("scripts.util")


local TOOL = "tmb-casper-tool"
local EXORCIST = "tmb-exorcist"
local ROOT = "tmb_casper_root"        -- vertical flow in the top bar: Casper bar, then Exorcist strip
local PANEL = "tmb_casper_panel"
local STRIP = "tmb_exorcist_strip"
local CHANGE = "tmb_casper_change"  -- "Change N ghosts to" popup (screen)
local craft_all, craft_one, how_many, change_open, change_click  -- defined further down

local SLOT_SIZE = 40          -- width of one slot_button, in GUI pixels
local RIGHT_RESERVE = 330     -- room kept free for the minimap / FPS-UPS corner
local EDGE_PADDING = 40       -- frame padding and safety margin
local MIN_COLUMNS = 2
local ROW_LENGTH = 10         -- icons per row before the bar grows downward
local MAX_ROWS = 2            -- more rows than this scroll
local MAX_COLUMNS = 60
local CLICK_SIZE = 0.6        -- a selection smaller than this (tiles) counts as a click
local CANCEL_GRACE = 120      -- ticks after an alt-click cancel during which a click-selection is ignored

local MAP_COLOR = {r = 0.2, g = 1, b = 0.2, a = 0.75}

-- Belt/pipe outline pieces, cut from the game's own copy-paste bracket art (see data.lua).
local CORNER_SIZE = 20 / 64   -- corner L piece, in tiles
local BAND = 9 / 64           -- thickness of a bracket arm, in tiles
local DASH_WIDTH = 7 / 64     -- width of the dash sprite before stretching, in tiles
local DASH_LENGTH = 0.5       -- one dash centred on each outer tile side, in tiles
local ARROW_COLOR = {r = 0.3, g = 1, b = 0.3, a = 0.9}
local HOVER_TTL = 600         -- a hover guide never outlives 10 s without a fresh hover

-- Belts and pipes that touch are outlined together: dashes on the outer sides, L pieces on outer corners.
local MERGE_TYPES = {
  ["transport-belt"] = "belt",
  ["underground-belt"] = "belt",
  ["pipe"] = "pipe",
  ["pipe-to-ground"] = "pipe",
}

-- Ritual: the same tracker for entities marked for upgrade (and ghosts changed in Casper).
local RITUAL = "tmb-ritual-tool"
local RPANEL = "tmb_ritual_panel"

-- The two trackers. Casper keeps its storage at storage.casper, Ritual at storage.casper.ritual.
local CASPER_K = {
  id = "casper", ritual = false, tool = TOOL, panel = PANEL,
  color = {r = 0.2, g = 1, b = 0.2},
  map_color = MAP_COLOR, arrow_color = ARROW_COLOR,
  area_color = {r = 0.25, g = 1, b = 0.25, a = 0.9},
  title = "tmb-casper.panel-title", preview_title = "tmb-casper.preview-title",
  craft_all_hint = "tmb-casper.craft-all-hint",
  none = "tmb-casper.no-ghosts", none_new = "tmb-casper.no-new-ghosts",
  tracking = "tmb-casper.tracking", added = "tmb-casper.added",
}
local RITUAL_K = {
  id = "ritual", ritual = true, tool = RITUAL, panel = RPANEL,
  color = {r = 0.15, g = 0.9, b = 0.9},
  map_color = {r = 0.15, g = 0.9, b = 0.9, a = 0.75}, arrow_color = {r = 0.2, g = 0.95, b = 0.95, a = 0.9},
  area_color = {r = 0.2, g = 0.95, b = 0.95, a = 0.9},
  title = "tmb-casper.ritual-title", preview_title = "tmb-casper.ritual-preview-title",
  craft_all_hint = "tmb-casper.ritual-craft-all-hint",
  none = "tmb-casper.no-upgrades", none_new = "tmb-casper.no-new-upgrades",
  tracking = "tmb-casper.ritual-tracking", added = "tmb-casper.ritual-added",
}
local KINDS = {casper = CASPER_K, ritual = RITUAL_K}

local function S(K)
  if K and K.ritual then return storage.casper.ritual end
  return storage.casper
end

local function kind_of(job)
  return (job and job.ritual) and RITUAL_K or CASPER_K
end

-- The tracker an element or tool name belongs to.
local function kind_named(name)
  return KINDS[name] or CASPER_K
end

---------------------------------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------------------------------
--
-- jobs[player_index] = {
--   home_surface_index,                -- planet the player was physically on when the job started
--   ghosts = {[reg] = record},         -- reg = registration number from register_on_object_destroyed
--   counts = {[key] = {name, quality, sprite, is_item, amount}},
--   tiles = {[tile_key] = reg},        -- belt/pipe ghosts by tile, for neighbour lookups
--   units = {[unit] = true}, unit_reg = {[unit] = reg}, remaining,
-- }
-- record = {key, per_ghost, surface_index, unit, pos, sbox, marker?,
--           box?                      -- other ghosts: native copy brackets
--           merge?, tile_x?, tile_y?, pieces?}   -- belts/pipes: outline pieces

local function init_storage()
  storage.casper = storage.casper or {}
  local c = storage.casper
  storage.casper.ritual = storage.casper.ritual or {}
  for _, st in pairs({c, c.ritual}) do
    st.jobs = st.jobs or {}
    st.watchers = st.watchers or {}       -- [reg] = {[player_index] = true}
    st.dirty = st.dirty or {}             -- [player_index] = true: bar needs redrawing
    st.pending = st.pending or {}         -- [player_index] = latest drag state, not yet counted
    st.preview = st.preview or {}         -- [player_index] = {counts, total}
    st.collapsed = st.collapsed or {}     -- [player_index] = true when folded
    st.arrows = st.arrows or {}           -- [player_index] = guide render objects
    st.hover = st.hover or {}             -- [player_index] = {key, expires}
    st.pinned = st.pinned or {}           -- [player_index] = key of the pinned guide
  end
  c.cancel_tick = c.cancel_tick or {}     -- [player_index] = tick of last alt-click cancel
  c.picked = c.picked or {}               -- [player_index] = Exorcist picks
  c.gp = c.gp or {}                       -- [player_index] = {[item] = true}: Ghost Project items
  c.changes = c.changes or {}             -- [player_index] = recent Casper changes, for undo/redo

  for _, st in pairs({c, c.ritual}) do
    for _, job in pairs(st.jobs) do
      job.tiles = job.tiles or {}
      job.units = job.units or {}
      job.boxes = job.boxes or {}
      if not job.unit_reg then
        job.unit_reg = {}
        for reg, record in pairs(job.ghosts) do
          if record.unit then job.unit_reg[record.unit] = reg end
        end
      end
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Ghost and entity lookups
---------------------------------------------------------------------------------------------------

local function describe_ghost(ghost)
  local quality = (ghost.quality and ghost.quality.name) or "normal"
  local proto = ghost.ghost_prototype
  local items = proto and proto.items_to_place_this
  local first = items and items[1]
  if first then
    local name = first.name
    if type(name) ~= "string" then name = name.name end
    return name .. "|" .. quality, {
      name = name, quality = quality, sprite = "item/" .. name, per_ghost = first.count or 1, is_item = true,
    }
  end
  -- Entities with no placing item: count the entity itself.
  local name = ghost.ghost_name
  return "entity:" .. name .. "|" .. quality, {
    name = name, quality = quality, sprite = "entity/" .. name, per_ghost = 1, is_item = false,
  }
end

-- Quality-free type key for a ghost or built entity: the item that places it, else "entity:<name>" for ghosts.
local function pick_of_entity(entity)
  if not entity.valid then return nil end
  local is_ghost = entity.type == "entity-ghost"
  local proto = is_ghost and entity.ghost_prototype or entity.prototype
  local items = proto and proto.items_to_place_this
  local first = items and items[1]
  if first then
    local name = first.name
    if type(name) ~= "string" then name = name.name end
    return name, {name = name, sprite = "item/" .. name, is_item = true}
  end
  if is_ghost then
    local name = entity.ghost_name
    return "entity:" .. name, {name = name, sprite = "entity/" .. name, is_item = false}
  end
  return nil
end

-- Tracked records are keyed "<type>|<quality>"; dropping the quality gives the pick key.
local function pick_of_record(record)
  return record.key:match("^(.*)|[^|]*$") or record.key
end

-- Works anywhere the force has scanned at least once, radar live view or not; never in unscanned sectors.
local function charted(force, surface, position)
  return force.is_chunk_charted(surface, {x = math.floor(position.x / 32), y = math.floor(position.y / 32)})
end

local function holding(player, name)
  local cursor = player.cursor_stack
  return cursor and cursor.valid_for_read and cursor.name == name
end

---------------------------------------------------------------------------------------------------
-- Drawing primitives
---------------------------------------------------------------------------------------------------

local function destroy_obj(obj)
  if obj and obj.valid then obj.destroy() end
end

local function destroy_all(objects)
  for _, obj in pairs(objects or {}) do destroy_obj(obj) end
end

-- Green copy-style corner brackets on a single ghost, seen only by this player.
local function create_box(surface, ghost, player_index)
  local ok, box = pcall(surface.create_entity, {
    name = "highlight-box", position = ghost.position, target = ghost,
    box_type = "copy", render_player_index = player_index, blink_interval = 0,
  })
  if ok and box then return box end
  ok, box = pcall(surface.create_entity, {
    name = "highlight-box", position = ghost.position, bounding_box = ghost.selection_box,
    box_type = "copy", render_player_index = player_index, blink_interval = 0,
  })
  if ok then return box end
  return nil
end

local function draw(fn, spec, list)
  local ok, obj = pcall(fn, spec)
  if ok and obj then
    if list then list[#list + 1] = obj end
    return obj
  end
  return nil
end

-- Filled mark on the map view, in the tracker's colour.
local function create_marker(surface, bbox, player_index, color)
  if not bbox then return nil end
  return draw(rendering.draw_rectangle, {
    color = color or MAP_COLOR, filled = true, left_top = bbox.left_top, right_bottom = bbox.right_bottom,
    surface = surface, players = {player_index}, render_mode = "chart",
  })
end

---------------------------------------------------------------------------------------------------
-- Belt and pipe outlines
---------------------------------------------------------------------------------------------------
-- Each belt/pipe ghost draws its own share of the group outline, based on which neighbours exist:
-- a dash centred on every side facing out of the group, and an L corner piece on every outer corner,
-- all just outside the group. When a tile comes or goes, only it and its four neighbours redraw.

local function tile_key(surface_index, merge, x, y)
  return surface_index .. "|" .. merge .. "|" .. x .. "," .. y
end

local SIDES = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}  -- up, right, down, left

local function draw_piece(spec, list)
  spec.render_layer = "selection-box"
  if not draw(rendering.draw_sprite, spec, list) then
    spec.render_layer = nil
    draw(rendering.draw_sprite, spec, list)
  end
end

-- Ritual's corner brackets: the game's highlight boxes only come in fixed colours, so Ritual draws
-- its own from white L pieces tinted cyan, placed like the copy brackets.
local function create_corners(surface, bbox, player_index)
  if not bbox then return nil end
  local list = {}
  local half = CORNER_SIZE / 2
  local l, t, r, b = bbox.left_top.x, bbox.left_top.y, bbox.right_bottom.x, bbox.right_bottom.y
  for _, c in pairs({{l, t, -1, -1, 0}, {r, t, 1, -1, 0.25}, {r, b, 1, 1, 0.5}, {l, b, -1, 1, 0.75}}) do
    local sx, sy = c[3], c[4]
    draw_piece({sprite = "tmb-ritual-outline-corner", tint = RITUAL_K.color,
      target = {x = c[1] + sx * BAND - sx * half, y = c[2] + sy * BAND - sy * half},
      orientation = c[5], surface = surface, players = {player_index}}, list)
  end
  return list
end

local function draw_tile(job, player_index, reg)
  local r = job.ghosts[reg]
  if not (r and r.merge) then return end
  destroy_all(r.pieces)
  r.pieces = {}
  local surface = game.surfaces[r.surface_index]
  if not surface then return end

  local x, y = r.tile_x, r.tile_y
  local function open(dx, dy) return job.tiles[tile_key(r.surface_index, r.merge, x + dx, y + dy)] == nil end
  local up, right, down, left = open(0, -1), open(1, 0), open(0, 1), open(-1, 0)
  local players = {player_index}
  local stretch = DASH_LENGTH / DASH_WIDTH
  local dash_sprite = job.ritual and "tmb-ritual-outline-dash" or "tmb-casper-outline-dash"
  local corner_sprite = job.ritual and "tmb-ritual-outline-corner" or "tmb-casper-outline-corner"
  local tint = job.ritual and RITUAL_K.color or nil

  -- Dashes centred on each outer side, sitting just outside the edge.
  local dashes = {
    {up, x + 0.5, y - BAND / 2, 0},
    {right, x + 1 + BAND / 2, y + 0.5, 0.25},
    {down, x + 0.5, y + 1 + BAND / 2, 0.5},
    {left, x - BAND / 2, y + 0.5, 0.75},
  }
  for _, d in pairs(dashes) do
    if d[1] then
      draw_piece({sprite = dash_sprite, tint = tint, target = {x = d[2], y = d[3]}, orientation = d[4],
        x_scale = stretch, surface = surface, players = players}, r.pieces)
    end
  end

  -- L pieces wrapped around the outside of each outer corner.
  local half = CORNER_SIZE / 2
  local corners = {
    {up and left, x, y, -1, -1, 0},
    {up and right, x + 1, y, 1, -1, 0.25},
    {down and right, x + 1, y + 1, 1, 1, 0.5},
    {down and left, x, y + 1, -1, 1, 0.75},
  }
  for _, c in pairs(corners) do
    if c[1] then
      local sx, sy = c[4], c[5]
      draw_piece({sprite = corner_sprite, tint = tint,
        target = {x = c[2] + sx * BAND - sx * half, y = c[3] + sy * BAND - sy * half},
        orientation = c[6], surface = surface, players = players}, r.pieces)
    end
  end
end

-- Redraw a tile and/or its four neighbours (their outer sides change when it comes or goes).
local function draw_around(job, player_index, record, include_self, reg)
  if include_self then draw_tile(job, player_index, reg) end
  for _, d in pairs(SIDES) do
    local n = job.tiles[tile_key(record.surface_index, record.merge, record.tile_x + d[1], record.tile_y + d[2])]
    if n then draw_tile(job, player_index, n) end
  end
end

-- Rebuild every belt/pipe outline (used when converting saves from older versions).
local function rebuild_all_tiles(job, player_index)
  job.tiles = {}
  for reg, r in pairs(job.ghosts) do
    if r.merge then job.tiles[tile_key(r.surface_index, r.merge, r.tile_x, r.tile_y)] = reg end
  end
  for reg, r in pairs(job.ghosts) do
    if r.merge then
      draw_tile(job, player_index, reg)
      if not r.marker and r.sbox then
        local surface = game.surfaces[r.surface_index]
        if surface then r.marker = create_marker(surface, r.sbox, player_index, kind_of(job).map_color) end
      end
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Job areas: the dragged boxes, drawn as one combined outline
---------------------------------------------------------------------------------------------------
-- A job's area is every box dragged for it (shift-drag adds one). New ghosts (Casper) or upgrade
-- orders (Ritual) placed inside it later are picked up. The outline traces the boxes' combined edge.

local function in_area(job, surface_index, pos)
  for _, b in pairs(job.boxes or {}) do
    if b.surface_index == surface_index and pos.x >= b.l and pos.x <= b.r and pos.y >= b.t and pos.y <= b.b then
      return true
    end
  end
  return false
end

-- Edge segments of the union of axis-aligned boxes: split the plane at every box edge, mark the cells
-- inside a box, and keep the cell sides that face an outside cell. Collinear pieces are joined.
local function area_segments(boxes)
  local xs, ys, seen_x, seen_y = {}, {}, {}, {}
  for _, b in pairs(boxes) do
    for _, x in pairs({b.l, b.r}) do if not seen_x[x] then seen_x[x] = true; xs[#xs + 1] = x end end
    for _, y in pairs({b.t, b.b}) do if not seen_y[y] then seen_y[y] = true; ys[#ys + 1] = y end end
  end
  table.sort(xs)
  table.sort(ys)
  local function covered(i, j)
    if i < 1 or j < 1 or i >= #xs or j >= #ys then return false end
    local cx, cy = (xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2
    for _, b in pairs(boxes) do
      if cx > b.l and cx < b.r and cy > b.t and cy < b.b then return true end
    end
    return false
  end
  local horiz, vert = {}, {}  -- [y] = {{x1, x2}}, [x] = {{y1, y2}}
  for i = 1, #xs - 1 do
    for j = 1, #ys - 1 do
      if covered(i, j) then
        if not covered(i, j - 1) then table.insert(horiz, {ys[j], xs[i], xs[i + 1]}) end
        if not covered(i, j + 1) then table.insert(horiz, {ys[j + 1], xs[i], xs[i + 1]}) end
        if not covered(i - 1, j) then table.insert(vert, {xs[i], ys[j], ys[j + 1]}) end
        if not covered(i + 1, j) then table.insert(vert, {xs[i + 1], ys[j], ys[j + 1]}) end
      end
    end
  end
  local function join(list)
    table.sort(list, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
    local out = {}
    for _, seg in ipairs(list) do
      local last = out[#out]
      if last and last[1] == seg[1] and math.abs(last[3] - seg[2]) < 1e-6 then
        last[3] = seg[3]
      else
        out[#out + 1] = {seg[1], seg[2], seg[3]}
      end
    end
    return out
  end
  local segments = {}
  for _, h in pairs(join(horiz)) do segments[#segments + 1] = {{x = h[2], y = h[1]}, {x = h[3], y = h[1]}} end
  for _, v in pairs(join(vert)) do segments[#segments + 1] = {{x = v[1], y = v[2]}, {x = v[1], y = v[3]}} end
  return segments
end

local function draw_area(job, player_index)
  destroy_all(job.area_objs)
  job.area_objs = {}
  local K = kind_of(job)
  local by_surface = {}
  for _, b in pairs(job.boxes or {}) do
    by_surface[b.surface_index] = by_surface[b.surface_index] or {}
    table.insert(by_surface[b.surface_index], b)
  end
  for surface_index, boxes in pairs(by_surface) do
    local surface = game.surfaces[surface_index]
    if surface then
      for _, seg in pairs(area_segments(boxes)) do
        for _, mode in pairs({"game", "chart"}) do
          draw(rendering.draw_line, {color = K.area_color, width = 2, from = seg[1], to = seg[2],
            dash_length = 0.5, gap_length = 0.35, surface = surface, players = {player_index},
            render_mode = mode}, job.area_objs)
        end
      end
    end
  end
end

-- Add a dragged box to the job's area and redraw the outline.
local function add_box(job, player_index, surface, area)
  job.boxes = job.boxes or {}
  table.insert(job.boxes, {surface_index = surface.index,
    l = area.left_top.x, t = area.left_top.y, r = area.right_bottom.x, b = area.right_bottom.y})
  draw_area(job, player_index)
end

---------------------------------------------------------------------------------------------------
-- GUI: Casper bar and Exorcist strip
---------------------------------------------------------------------------------------------------

local function get_root(player, create)
  local top = player.gui.top
  local root = top[ROOT]
  if not root and create then
    root = top.add{type = "flow", name = ROOT, direction = "vertical"}
  end
  return root
end

local function tidy_root(player)
  local root = player.gui.top[ROOT]
  if root and #root.children == 0 then root.destroy() end
end

local function destroy_panel(player, K)
  K = K or CASPER_K
  if not K.ritual then
    local legacy = player.gui.top[PANEL]  -- 0.3.0 and older put the bar directly in the top bar
    if legacy then legacy.destroy() end
  end
  local root = get_root(player, false)
  if root and root[K.panel] then root[K.panel].destroy() end
  tidy_root(player)
end

local function column_count(player)
  local width = player.display_resolution.width / player.display_scale

  -- Space already taken on the left by the shared mod button bar (GUI Unifier and friends).
  local left_used = 0
  for _, child in pairs(player.gui.top.children) do
    if child.name ~= PANEL and child.name ~= RPANEL and child.name ~= ROOT then
      local inner = child.name == "mod_gui_top_frame" and child.mod_gui_inner_frame
      local buttons = inner and #inner.children or 1
      left_used = left_used + buttons * SLOT_SIZE + 16
    end
  end

  local columns = math.floor((width - left_used - RIGHT_RESERVE - EDGE_PADDING) / SLOT_SIZE)
  if columns < MIN_COLUMNS then columns = MIN_COLUMNS end
  if columns > MAX_COLUMNS then columns = MAX_COLUMNS end
  return columns
end

local function sort_key(entry)
  local proto = entry.is_item and prototypes.item[entry.name] or prototypes.entity[entry.name]
  if not proto then return entry.name end
  local group = proto.group and proto.group.order or ""
  local subgroup = proto.subgroup and proto.subgroup.order or ""
  return group .. "|" .. subgroup .. "|" .. (proto.order or "") .. "|" .. entry.name
end

local function tooltip_for(entry)
  local proto = entry.is_item and prototypes.item[entry.name] or prototypes.entity[entry.name]
  local name = proto and proto.localised_name or entry.name
  if entry.quality ~= "normal" and prototypes.quality[entry.quality] then
    return {"tmb-casper.item-tooltip-quality", name, prototypes.quality[entry.quality].localised_name, entry.amount}
  end
  return {"tmb-casper.item-tooltip", name, entry.amount}
end

local function sorted_entries(map)
  local entries, keys, ids = {}, {}, {}
  for id, entry in pairs(map) do
    entries[#entries + 1] = entry
    keys[entry] = sort_key(entry)
    ids[entry] = id
  end
  table.sort(entries, function(a, b) return keys[a] < keys[b] end)
  return entries, ids
end

-- The icon grid of a bar or strip. Past MAX_ROWS rows it sits in a scroll area MAX_ROWS rows tall.
local function add_grid(frame, count, columns)
  local inner = frame.add{type = "frame", name = "tmb_inner", style = "mod_gui_inside_deep_frame"}
  local parent = inner
  if math.ceil(count / columns) > MAX_ROWS then
    local scroll = inner.add{type = "scroll-pane", name = "tmb_scroll", style = "tmb_scroll",
      horizontal_scroll_policy = "never", vertical_scroll_policy = "always"}
    scroll.style.maximal_height = MAX_ROWS * SLOT_SIZE
    parent = scroll
  end
  return parent.add{type = "table", name = "tmb_grid", column_count = columns, style = "filter_slot_table"}
end

local function find_grid(frame)
  local inner = frame and frame.valid and frame.tmb_inner
  if not inner then return nil end
  return inner.tmb_grid or (inner.tmb_scroll and inner.tmb_scroll.tmb_grid)
end

-- Draw a tracker's bar from a counts table: header slot on the left, then up to ROW_LENGTH icons per row.
-- Live (job) bars get clickable, hoverable icons for the guide arrow. Casper's bar sits first in the
-- top flow, Ritual's right below it, the Exorcist strip last.
local function draw_counts(player, counts, header_tooltip, live, K)
  K = K or CASPER_K
  local entries, ids = sorted_entries(counts)
  local collapsed = S(K).collapsed[player.index] and true or false
  local columns = math.max(1, math.min(#entries, ROW_LENGTH, column_count(player)))
  local header_tip = live and {"", header_tooltip, "\n", {K.craft_all_hint}, "\n", {"tmb-casper.fold-hint"}}
    or {"", header_tooltip, "\n", {"tmb-casper.toggle-hint"}}
  local function item_tip(entry)
    return live and {"", tooltip_for(entry), "\n", {"tmb-casper.guide-hint"}, "\n", {"tmb-casper.craft-hint"},
      "\n", {"tmb-casper.how-many-hint"}, "\n", {"tmb-casper.change-hint"}} or tooltip_for(entry)
  end

  -- Same types in the same layout: update counts in place, so a scrolled bar keeps its position.
  local parts = {live and "L" or "P", collapsed and "C" or "c", columns}
  for _, entry in ipairs(entries) do parts[#parts + 1] = ids[entry] end
  local sig = table.concat(parts, "|")
  local root_now = get_root(player, false)
  local existing = root_now and root_now[K.panel]
  if existing and existing.valid and existing.tags.sig == sig and #entries > 0 then
    local header = existing.children[1] and existing.children[1].children[1]
    if header then header.tooltip = header_tip end
    local grid = find_grid(existing)
    if grid then
      local pinned = S(K).pinned[player.index]
      for i, button in ipairs(grid.children) do
        local entry = entries[i]
        if entry then
          if button.number ~= entry.amount then button.number = entry.amount end
          button.tooltip = item_tip(entry)
          if live then pcall(function() button.toggled = (pinned == ids[entry]) end) end
        end
      end
    end
    return
  end

  destroy_panel(player, K)
  if #entries == 0 and live then return end

  local root = get_root(player, true)
  local index = 1
  if K.ritual and root[PANEL] then index = 2 end
  local frame = root.add{
    type = "frame", name = K.panel, direction = "horizontal", style = "slot_window_frame", index = index,
    tags = {sig = sig},
  }
  frame.add{type = "frame", style = "mod_gui_inside_deep_frame"}.add{
    type = "sprite-button", sprite = "item/" .. K.tool, style = "slot_button",
    tooltip = header_tip,
    tags = {tmb_casper_toggle = true, tmb_casper_craft = live or nil, tmb_kind = K.id},
    mouse_button_filter = live and {"left", "right"} or {"left"},
  }
  if #entries == 0 or collapsed then return end

  local grid = add_grid(frame, #entries, columns)
  local pinned = S(K).pinned[player.index]

  for _, entry in pairs(entries) do
    local sprite = entry.sprite
    if not helpers.is_valid_sprite_path(sprite) then sprite = "utility/questionmark" end
    local button = grid.add{
      type = "sprite-button",
      sprite = sprite,
      number = entry.amount,
      style = "slot_button",
      tooltip = item_tip(entry),
      tags = live and {tmb_casper_key = ids[entry], tmb_kind = K.id} or nil,
      mouse_button_filter = live and {"left", "right"} or {"left"},
      raise_hover_events = live or false,
    }
    if live and pinned == ids[entry] then
      pcall(function() button.toggled = true end)
    end
  end
end

local function draw_panel(player, K)
  K = K or CASPER_K
  -- While dragging, the bar previews what the drag would track.
  local preview = S(K).preview[player.index]
  if preview then
    draw_counts(player, preview.counts, {"", {K.preview_title}, ": ", preview.total}, false, K)
    return
  end
  local job = S(K).jobs[player.index]
  if not job or job.remaining <= 0 then
    destroy_panel(player, K)
    return
  end
  draw_counts(player, job.counts, {"", {K.title}, ": ", job.remaining}, true, K)
  -- Casper's bar is inserted first; make sure Ritual's stays below it.
  if not K.ritual then
    local root = get_root(player, false)
    if root and root[RPANEL] and root[PANEL] and root[RPANEL].get_index_in_parent() < root[PANEL].get_index_in_parent() then
      root[RPANEL].destroy()  -- rebuilt below Casper's (an in-place update would leave it above)
      draw_panel(player, RITUAL_K)
    end
  end
end

local function draw_strip(player)
  local root = get_root(player, false)
  if root and root[STRIP] then root[STRIP].destroy() end
  if not holding(player, EXORCIST) then
    tidy_root(player)
    return
  end

  local frame = get_root(player, true).add{type = "frame", name = STRIP, direction = "horizontal", style = "slot_window_frame"}
  frame.add{type = "frame", style = "mod_gui_inside_deep_frame"}.add{
    type = "sprite-button", sprite = "item/" .. EXORCIST, style = "red_slot_button",
    tooltip = {"", {"tmb-casper.exorcist-help"}, "\n", {"tmb-casper.toggle-hint"}},
    tags = {tmb_casper_toggle = true},
  }
  if storage.casper.collapsed[player.index] then return end

  local entries = sorted_entries(storage.casper.picked[player.index] or {})
  if #entries == 0 then return end
  local columns = math.min(#entries, ROW_LENGTH, column_count(player))
  local grid = add_grid(frame, #entries, columns)
  for _, entry in pairs(entries) do
    local sprite = entry.sprite
    if not helpers.is_valid_sprite_path(sprite) then sprite = "utility/questionmark" end
    local proto = entry.is_item and prototypes.item[entry.name] or prototypes.entity[entry.name]
    grid.add{type = "sprite-button", sprite = sprite, style = "red_slot_button",
      tooltip = proto and proto.localised_name or entry.name}
  end
end

local function mark_dirty(player_index, K)
  S(K).dirty[player_index] = true
  local gp = storage.casper.gp and storage.casper.gp[player_index]
  if gp and next(gp) then U.mark_dirty(player_index) end  -- Ghost Project amounts follow the job
end

---------------------------------------------------------------------------------------------------
-- Guide: arrow + dashed path from you to the nearest tracked ghost of a type
---------------------------------------------------------------------------------------------------

local function clear_guide(player_index, K)
  destroy_all(S(K).arrows[player_index])
  S(K).arrows[player_index] = nil
end

local function record_position(record)
  if record.pos then return record.pos end
  if record.sbox then
    return {x = (record.sbox.left_top.x + record.sbox.right_bottom.x) / 2, y = (record.sbox.left_top.y + record.sbox.right_bottom.y) / 2}
  end
  if record.box and record.box.valid then return record.box.position end
  return nil
end

local function nearest_of(job, key, surface_index, from)
  local best, best_d
  for _, record in pairs(job.ghosts) do
    if record.key == key and record.surface_index == surface_index then
      local p = record_position(record)
      if p then
        local dx, dy = p.x - from.x, p.y - from.y
        local d = dx * dx + dy * dy
        if not best_d or d < best_d then best, best_d = p, d end
      end
    end
  end
  return best
end

local function draw_guide(player, key, ttl, K)
  K = K or CASPER_K
  clear_guide(player.index, K)
  local job = S(K).jobs[player.index]
  if not job then return end

  local surface = player.surface
  local character = player.character
  local on_character = character and character.valid and character.surface == surface
  local origin = on_character and character or player.position
  local from = on_character and character.position or player.position
  local target = nearest_of(job, key, surface.index, from)
  if not target then return end

  local objects = {}
  local function add(fn, spec)
    spec.surface = surface
    spec.players = {player.index}
    spec.time_to_live = ttl
    draw(fn, spec, objects)
  end
  for _, mode in pairs({"game", "chart"}) do
    add(rendering.draw_line, {color = K.arrow_color, width = 3, from = origin, to = target,
      dash_length = 0.6, gap_length = 0.4, render_mode = mode})
  end
  add(rendering.draw_sprite, {sprite = "utility/indication_arrow", target = origin, orientation_target = target,
    oriented_offset = {0, -2}, x_scale = 1.5, y_scale = 1.5, tint = K.arrow_color})
  add(rendering.draw_circle, {color = K.arrow_color, radius = 1, width = 4, filled = false, target = target})
  S(K).arrows[player.index] = objects
end

-- Show the hover guide if one is active, else the pinned guide, else nothing.
local function refresh_guide(player, K)
  K = K or CASPER_K
  local index = player.index
  local job = S(K).jobs[index]

  local hover = S(K).hover[index]
  if hover and (hover.expires <= game.tick or not (job and job.counts[hover.key])) then
    S(K).hover[index] = nil
    hover = nil
  end
  local pinned = S(K).pinned[index]
  if pinned and not (job and job.counts[pinned]) then
    S(K).pinned[index] = nil  -- that type is finished
    pinned = nil
  end

  if hover then
    draw_guide(player, hover.key, hover.expires - game.tick, K)
  elseif pinned then
    draw_guide(player, pinned, nil, K)
  else
    clear_guide(index, K)
  end
end

---------------------------------------------------------------------------------------------------
-- Jobs
---------------------------------------------------------------------------------------------------

-- A built entity with an upgrade order, described by what it will become.
local function describe_upgrade(entity)
  local target, quality = entity.get_upgrade_target()
  if not target then return nil end
  local q = quality and quality.name or "normal"
  local items = target.items_to_place_this
  local first = items and items[1]
  if first then
    local name = first.name
    if type(name) ~= "string" then name = name.name end
    return name .. "|" .. q, {name = name, quality = q, sprite = "item/" .. name, per_ghost = first.count or 1, is_item = true}
  end
  return "entity:" .. target.name .. "|" .. q,
    {name = target.name, quality = q, sprite = "entity/" .. target.name, per_ghost = 1, is_item = false}
end

-- Ritual tracks upgrade orders and ghosts handed over from Casper; Casper tracks ghosts.
local function describe_tracked(entity)
  if entity.type == "entity-ghost" then return describe_ghost(entity) end
  return describe_upgrade(entity)
end

local function cancel_job(player_index, K)
  K = K or CASPER_K
  local job = S(K).jobs[player_index]
  if not job then return false end

  for reg, record in pairs(job.ghosts) do
    destroy_obj(record.box)
    destroy_all(record.corners)
    destroy_obj(record.marker)
    destroy_all(record.pieces)
    local watchers = S(K).watchers[reg]
    if watchers then
      watchers[player_index] = nil
      if next(watchers) == nil then S(K).watchers[reg] = nil end
    end
  end
  destroy_all(job.area_objs)
  for _, group in pairs(job.groups or {}) do destroy_all(group.objects) end  -- leftovers from 0.7.0
  for _, run in pairs(job.runs or {}) do  -- leftovers from 0.6.0 and older
    destroy_obj(run.box)
    destroy_obj(run.marker)
  end

  S(K).jobs[player_index] = nil
  S(K).dirty[player_index] = nil
  -- The Ghost Project covers both trackers; it goes when neither has a job left.
  local other = K.ritual and CASPER_K or RITUAL_K
  if storage.casper.gp[player_index] and not S(other).jobs[player_index] then
    storage.casper.gp[player_index] = nil
    U.mark_dirty(player_index)
  elseif storage.casper.gp[player_index] then
    U.mark_dirty(player_index)
  end
  S(K).hover[player_index] = nil
  S(K).pinned[player_index] = nil
  clear_guide(player_index, K)
  local player = game.get_player(player_index)
  if player then
    destroy_panel(player, K)
    local popup = player.gui.screen[CHANGE]
    if popup and popup.tags.kind == K.id then popup.destroy() end
  end
  return true
end

-- Add every not-yet-tracked, scanned entity in the area to the job: entity ghosts for Casper,
-- entities with an upgrade order for Ritual. `list` gives the entities instead of scanning.
-- Returns how many were added.
local function add_ghosts(player, job, surface, area, list)
  local K = kind_of(job)
  local found = list
  if not found then
    if K.ritual then
      found = surface.find_entities_filtered{area = area, to_be_upgraded = true, force = player.force}
    else
      found = surface.find_entities_filtered{area = area, type = "entity-ghost", force = player.force}
    end
  end
  local added, new_tiles = 0, {}

  for _, ghost in pairs(found) do
    if ghost.valid and charted(player.force, surface, ghost.position) then
      local key, info = describe_tracked(ghost)
      local reg = key and script.register_on_object_destroyed(ghost)
      if key and not job.ghosts[reg] then
        local entry = job.counts[key]
        if not entry then
          entry = {name = info.name, quality = info.quality, sprite = info.sprite, is_item = info.is_item, amount = 0}
          job.counts[key] = entry
        end
        entry.amount = entry.amount + info.per_ghost

        local record = {
          key = key,
          per_ghost = info.per_ghost,
          surface_index = surface.index,
          unit = ghost.unit_number,
          pos = {x = ghost.position.x, y = ghost.position.y},
          sbox = ghost.selection_box,
          ghost = ghost.type == "entity-ghost" or nil,
        }
        if record.unit then
          job.units[record.unit] = true
          job.unit_reg[record.unit] = reg
        end
        local merge = MERGE_TYPES[ghost.type == "entity-ghost" and ghost.ghost_type or ghost.type]
        if merge then
          record.merge = merge
          record.tile_x = math.floor(ghost.position.x)
          record.tile_y = math.floor(ghost.position.y)
          job.tiles[tile_key(surface.index, merge, record.tile_x, record.tile_y)] = reg
          new_tiles[#new_tiles + 1] = reg
        elseif K.ritual then
          record.corners = create_corners(surface, ghost.selection_box, player.index)
        else
          record.box = create_box(surface, ghost, player.index)
        end
        record.marker = create_marker(surface, ghost.selection_box, player.index, K.map_color)
        job.ghosts[reg] = record
        job.remaining = job.remaining + 1
        added = added + 1

        local watchers = S(K).watchers[reg] or {}
        watchers[player.index] = true
        S(K).watchers[reg] = watchers
      end
    end
  end

  -- Outline the new belts/pipes, and refresh existing neighbours they now touch.
  local done = {}
  for _, reg in pairs(new_tiles) do
    local r = job.ghosts[reg]
    for _, d in pairs({{0, 0}, {0, -1}, {1, 0}, {0, 1}, {-1, 0}}) do
      local n = job.tiles[tile_key(r.surface_index, r.merge, r.tile_x + d[1], r.tile_y + d[2])]
      if n and not done[n] then
        done[n] = true
        draw_tile(job, player.index, n)
      end
    end
  end
  return added
end

local function new_job(player, K)
  return {
    ritual = (K and K.ritual) or nil,
    home_surface_index = player.physical_surface_index,
    ghosts = {}, counts = {}, tiles = {},
    units = {}, unit_reg = {}, remaining = 0,
    boxes = {}, area_objs = {},
  }
end

-- Plain drag: replace the current job with a fresh snapshot of the box, which becomes its area.
local function start_job(player, surface, area, K)
  K = K or CASPER_K
  cancel_job(player.index, K)
  local job = new_job(player, K)
  local added = add_ghosts(player, job, surface, area)
  if added == 0 then
    player.create_local_flying_text{text = {K.none}, create_at_cursor = true}
    return
  end
  S(K).jobs[player.index] = job
  add_box(job, player.index, surface, area)
  player.create_local_flying_text{text = {K.tracking, job.remaining}, create_at_cursor = true}
  draw_panel(player, K)
end

-- Shift-drag: add the box to the current job's area and track what's in it (or start a job).
local function extend_job(player, surface, area, K)
  K = K or CASPER_K
  local job = S(K).jobs[player.index]
  if not job then return start_job(player, surface, area, K) end
  local added = add_ghosts(player, job, surface, area)
  add_box(job, player.index, surface, area)
  if added == 0 then
    player.create_local_flying_text{text = {K.none_new}, create_at_cursor = true}
    return
  end
  player.create_local_flying_text{text = {K.added, added, job.remaining}, create_at_cursor = true}
  mark_dirty(player.index, K)
end

local function drop_ghost(player_index, reg, K)
  K = K or CASPER_K
  local job = S(K).jobs[player_index]
  if not job then return end
  local record = job.ghosts[reg]
  if not record then return end

  destroy_obj(record.box)
  destroy_all(record.corners)
  destroy_obj(record.marker)
  job.ghosts[reg] = nil
  if record.unit then
    job.units[record.unit] = nil
    job.unit_reg[record.unit] = nil
  end
  job.remaining = job.remaining - 1

  if record.merge then
    destroy_all(record.pieces)
    job.tiles[tile_key(record.surface_index, record.merge, record.tile_x, record.tile_y)] = nil
    if job.remaining > 0 then draw_around(job, player_index, record, false) end
  end

  local entry = job.counts[record.key]
  if entry then
    entry.amount = entry.amount - record.per_ghost
    if entry.amount <= 0 then job.counts[record.key] = nil end
  end

  if job.remaining <= 0 and not job.holding then
    cancel_job(player_index, K)  -- job finished: bar simply vanishes
  else
    mark_dirty(player_index, K)
  end
end

-- Stop tracking an entity for one player (Exorcist, cancelled upgrades, hand-overs), leaving
-- other players' tracking alone.
local function untrack(player_index, reg, K)
  local watchers = S(K).watchers[reg]
  if watchers then
    watchers[player_index] = nil
    if next(watchers) == nil then S(K).watchers[reg] = nil end
  end
  drop_ghost(player_index, reg, K)
end

---------------------------------------------------------------------------------------------------
-- Exorcist: pick types, then drag to untrack ghosts of those types
---------------------------------------------------------------------------------------------------

-- A click is a drag whose start and end are (almost) the same spot.
local function is_click(event)
  local p, c = event.position, event.cursor_position
  if p and c then
    return math.abs(p.x - c.x) < CLICK_SIZE and math.abs(p.y - c.y) < CLICK_SIZE
  end
  local a = event.area
  return (a.right_bottom.x - a.left_top.x) < CLICK_SIZE and (a.right_bottom.y - a.left_top.y) < CLICK_SIZE
end

-- The entity a click landed on: ghosts win over built entities.
local function clicked_entity(event, force)
  local candidates = event.entities or {}
  if #candidates == 0 then
    local a = event.area
    local point = event.cursor_position or {x = (a.left_top.x + a.right_bottom.x) / 2, y = (a.left_top.y + a.right_bottom.y) / 2}
    candidates = event.surface.find_entities_filtered{position = point}
  end
  local fallback
  for _, entity in pairs(candidates) do
    if entity.valid and charted(force, entity.surface, entity.position) and pick_of_entity(entity) then
      if entity.type == "entity-ghost" then return entity end
      fallback = fallback or entity
    end
  end
  return fallback
end

local function exorcist_click(player, event, on)
  local entity = clicked_entity(event, player.force)
  local key, info = nil, nil
  if entity then key, info = pick_of_entity(entity) end
  if not key then
    player.create_local_flying_text{text = {"tmb-casper.cant-pick"}, create_at_cursor = true}
    return
  end
  local picked = storage.casper.picked[player.index] or {}
  picked[key] = on and info or nil
  storage.casper.picked[player.index] = picked
  draw_strip(player)
end

-- Shift-drag: pick every type in the box, ghosts and built entities alike.
local function exorcist_pick_area(player, event)
  local added = 0
  local picked = storage.casper.picked[player.index] or {}
  for _, entity in pairs(event.surface.find_entities_filtered{area = event.area}) do
    if entity.valid and charted(player.force, event.surface, entity.position) then
      local key, info = pick_of_entity(entity)
      if key and not picked[key] then
        picked[key] = info
        added = added + 1
      end
    end
  end
  storage.casper.picked[player.index] = picked
  if added == 0 then
    player.create_local_flying_text{text = {"tmb-casper.cant-pick"}, create_at_cursor = true}
  end
  draw_strip(player)
end

-- Drag: untrack every tracked ghost of a picked type inside the box.
local function exorcist_remove_area(player, event)
  local K = CASPER_K  -- the Exorcist only works on Casper's ghosts
  local picked = storage.casper.picked[player.index]
  if not picked or next(picked) == nil then
    player.create_local_flying_text{text = {"tmb-casper.nothing-picked"}, create_at_cursor = true}
    return
  end
  local job = S(K).jobs[player.index]
  if not job then
    player.create_local_flying_text{text = {"tmb-casper.nothing-tracked"}, create_at_cursor = true}
    return
  end

  local doomed = {}
  for _, ghost in pairs(event.surface.find_entities_filtered{area = event.area, type = "entity-ghost", force = player.force}) do
    local unit = ghost.valid and ghost.unit_number
    local reg = unit and job.units[unit] and job.unit_reg[unit]
    local record = reg and job.ghosts[reg]
    if record and picked[pick_of_record(record)] then doomed[#doomed + 1] = reg end
  end
  for _, reg in pairs(doomed) do untrack(player.index, reg, K) end
  player.create_local_flying_text{text = {"tmb-casper.removed", #doomed}, create_at_cursor = true}
end

---------------------------------------------------------------------------------------------------
-- Drag preview
---------------------------------------------------------------------------------------------------

local function clear_preview(player_index, K)
  K = K or CASPER_K
  S(K).pending[player_index] = nil
  if S(K).preview[player_index] then
    S(K).preview[player_index] = nil
    mark_dirty(player_index, K)
  end
end

-- Count what the pending drag would end up tracking.
local function build_preview(player, pending, K)
  K = K or CASPER_K
  local counts, total = {}, 0
  local job = pending.alt and S(K).jobs[player.index] or nil

  -- Shift-drag adds to the job, so the preview starts from what's already tracked.
  if job then
    for key, entry in pairs(job.counts) do
      counts[key] = {name = entry.name, quality = entry.quality, sprite = entry.sprite, is_item = entry.is_item, amount = entry.amount}
    end
    total = job.remaining
  end

  -- Scan the dragged box ourselves, exactly like the final drag does.
  local found = {}
  local surface = pending.surface_index and game.surfaces[pending.surface_index]
  if surface and pending.area then
    if K.ritual then
      found = surface.find_entities_filtered{area = pending.area, to_be_upgraded = true, force = player.force}
    else
      found = surface.find_entities_filtered{area = pending.area, type = "entity-ghost", force = player.force}
    end
  end

  for _, entity in pairs(found) do
    if entity.valid and charted(player.force, entity.surface, entity.position)
      and not (job and entity.unit_number and job.units[entity.unit_number]) then
      local key, info = describe_tracked(entity)
      if key then
        local entry = counts[key]
        if not entry then
          entry = {name = info.name, quality = info.quality, sprite = info.sprite, is_item = info.is_item, amount = 0}
          counts[key] = entry
        end
        entry.amount = entry.amount + info.per_ghost
        total = total + 1
      end
    end
  end
  return {counts = counts, total = total}
end

local function tool_kind(item)
  if item == TOOL then return CASPER_K end
  if item == RITUAL then return RITUAL_K end
  return nil
end

local function on_drag(event)
  local K = tool_kind(event.item)
  if not K then return end
  local alt = defines.selection_mode and event.selection_mode == defines.selection_mode.alt_select or false
  -- Remember the box, not event.entities: the entity list can be empty until the drag is released.
  S(K).pending[event.player_index] = {
    surface_index = event.surface and event.surface.index,
    area = event.area,
    alt = alt,
  }
end


---------------------------------------------------------------------------------------------------
-- Craft all: hand-craft the job's shortfall (normal quality only)
---------------------------------------------------------------------------------------------------

-- Items already in the hand-crafting queue (top-level entries only), by item name.
local function queued_items(player)
  local queued = {}
  local queue = player.crafting_queue
  if not queue then return queued end
  for _, q in pairs(queue) do
    if not q.prerequisite then
      local recipe = prototypes.recipe[q.recipe]
      if recipe then
        for _, prod in pairs(recipe.products) do
          if prod.type == "item" then
            queued[prod.name] = (queued[prod.name] or 0) + q.count * shared.per_craft(q.recipe, prod.name)
          end
        end
      end
    end
  end
  return queued
end

-- How many of a bar entry you're still missing (normal quality counts only for normal ghosts).
local function shortfall(player, entry, queued)
  if entry.quality ~= "normal" then return entry.amount end
  local have = player.get_item_count{name = entry.name, quality = "normal", comparator = "="}
  return entry.amount - have - (queued[entry.name] or 0)
end

---------------------------------------------------------------------------------------------------
-- Ghost Project: what the job's buildings still need, listed in TMB's Materials panel
---------------------------------------------------------------------------------------------------

-- For every building the player's jobs still need (Casper and Ritual together; normal quality,
-- hand-craftable), the ingredients for all of its remaining crafts. Ingredients that are
-- buildings themselves (a prior tier, a part that is placeable) go deeper: what you're short of
-- those is broken into their own ingredients too, down the chain. Plates, gears and the like
-- stay one level. Shared items add up to one total.
-- need[item] = total; uses[item] = {{name, count, amount, via}} per building that needs it
-- (`via` = the job's building a deeper item is ultimately for).
local GP_MAX_DEPTH = 8

local function have_normal(player, name)
  return player.get_item_count{name = name, quality = "normal", comparator = "="}
end


local function is_building(name)
  local p = prototypes.item[name]
  return p ~= nil and p.place_result ~= nil
end

local function project_needs(player, queued)
  local wanted = {}  -- [building item] = amount still needed across both trackers
  for _, K in pairs({CASPER_K, RITUAL_K}) do
    local job = S(K).jobs[player.index]
    for _, entry in pairs(job and job.counts or {}) do
      if entry.is_item and entry.quality == "normal" then
        wanted[entry.name] = (wanted[entry.name] or 0) + entry.amount
      end
    end
  end
  local need, uses = {}, {}
  local demand, expanded, root = {}, {}, {}
  for name, amount in pairs(wanted) do
    demand[name] = amount
    root[name] = name
  end
  for _ = 1, GP_MAX_DEPTH do
    local names = {}
    for name in pairs(demand) do
      if wanted[name] or is_building(name) then names[#names + 1] = name end
    end
    local changed = false
    for _, name in ipairs(names) do
      local extra = demand[name] - have_normal(player, name) - (queued[name] or 0) - (expanded[name] or 0)
      if extra > 0 then
        local recipe = shared.find_recipe(player, name)
        if recipe then
          local per = shared.per_craft(recipe, name)
          local crafts = math.ceil(extra / per)
          expanded[name] = (expanded[name] or 0) + crafts * per
          changed = true
          for _, ing in pairs(prototypes.recipe[recipe].ingredients) do
            if ing.type == "item" then
              local n = ing.amount * crafts
              need[ing.name] = (need[ing.name] or 0) + n
              demand[ing.name] = (demand[ing.name] or 0) + n
              root[ing.name] = root[ing.name] or root[name]
              uses[ing.name] = uses[ing.name] or {}
              table.insert(uses[ing.name], {name = name, count = extra, amount = n,
                via = (not wanted[name]) and root[name] or nil})
            end
          end
        end
      end
    end
    if not changed then break end
  end
  return need, uses
end

local function has_any_job(player_index)
  return (storage.casper.jobs[player_index] or storage.casper.ritual.jobs[player_index]) ~= nil
end

-- For an item you can't hand-craft: a machine that makes it (entity name), or nil.
-- nil too when you can hand-craft it, or when there's no character to ask.
local machine_cache = {}
local function machine_for(player, name)
  if not (player.character and player.character.valid) then return nil end
  if shared.find_recipe(player, name) then return nil end
  if machine_cache[name] ~= nil then return machine_cache[name] or nil end
  local found = false
  for _, rname in ipairs(U.recipe_index()[name] or {}) do
    local r = prototypes.recipe[rname]
    for _, cat in pairs(r and r.categories or {}) do
      local machines = prototypes.get_entity_filtered{{filter = "crafting-category", crafting_category = cat}}
      for mname, m in pairs(machines) do
        if m.items_to_place_this and m.items_to_place_this[1] then found = mname; break end
      end
      if found then break end
    end
    if found then break end
  end
  machine_cache[name] = found
  return found or nil
end

-- The Ghost Project list for TMB's Materials panel: flagged items you're still short of, in crafting order.
-- Items you now have enough of drop off the list.
local function ghost_project(player)
  -- TMB can ask before Casper's saved data exists (TMB's panels rebuild first when a save is updated)
  if not (storage.casper and storage.casper.gp and storage.casper.ritual) then return {} end
  local flags = storage.casper.gp[player.index]
  if not (flags and next(flags)) then return {} end
  if not has_any_job(player.index) then
    storage.casper.gp[player.index] = nil
    return {}
  end
  local need, uses = project_needs(player, queued_items(player))
  local list = {}
  for name in pairs(flags) do
    local have = have_normal(player, name)
    local missing = (need[name] or 0) - have
    if missing > 0 and prototypes.item[name] then
      local u = uses[name] or {}
      local deeper = #u > 0
      for _, use in ipairs(u) do if not use.via then deeper = false end end
      list[#list + 1] = {name = name, need = need[name], have = have, missing = missing, uses = u,
        deeper = deeper, machine = machine_for(player, name)}
    else
      flags[name] = nil
    end
  end
  if not next(flags) then storage.casper.gp[player.index] = nil end
  table.sort(list, function(a, b) return U.before(a.name, b.name) end)
  return list
end

-- A craft of `item` failed or came up short: flag its ingredients the job is short of, and
-- return the ones to blink. Doesn't alert; callers batch that.
local function flag_failure(player, item, need)
  local recipe = shared.find_recipe(player, item)
  if not recipe then return {} end
  local blink = {}
  local flags = storage.casper.gp[player.index] or {}
  local seen = {}
  local function flag(rname, depth)
    for _, ing in pairs(prototypes.recipe[rname].ingredients) do
      if ing.type == "item" and not seen[ing.name] and (need[ing.name] or 0) > have_normal(player, ing.name) then
        seen[ing.name] = true
        flags[ing.name] = true
        blink[#blink + 1] = ing.name
        -- a building you're short of: what it's short of too
        if depth < GP_MAX_DEPTH and is_building(ing.name) then
          local sub = shared.find_recipe(player, ing.name)
          if sub then flag(sub, depth + 1) end
        end
      end
    end
  end
  flag(recipe, 1)
  if next(flags) then storage.casper.gp[player.index] = flags end
  return blink
end

local function alert(player, blink)
  if #blink == 0 then return end
  U.mark_dirty(player.index)
  if shared.gp_alert then shared.gp_alert(player, blink) end
end

-- Hook for TMB's own crafting (buildables panel, Materials panel, "How many?"): a failed craft
-- of a building the job needs feeds the Ghost Project too.
local function note_craft_failure(player, item)
  if not (storage.casper and storage.casper.gp and storage.casper.ritual) then return end
  if not has_any_job(player.index) then return end
  local need = project_needs(player, queued_items(player))
  alert(player, flag_failure(player, item, need))
end
shared.ghost_project = ghost_project
shared.note_craft_failure = note_craft_failure
-- Item name and quality behind a Casper / Ritual bar slot (nil if it isn't an item).
shared.casper_slot_item = function(player, key, kind)
  local job = S(kind_named(kind)).jobs[player.index]
  local entry = job and job.counts[key]
  if entry and entry.is_item then return entry.name, entry.quality end
end

-- Shift + click on a bar item: craft that item's shortfall.
craft_one = function(player, key, K)
  local job = S(K).jobs[player.index]
  local entry = job and job.counts[key]
  if not (entry and entry.is_item) then return end
  local say = function(msg) player.create_local_flying_text{text = msg, create_at_cursor = true} end
  if entry.quality ~= "normal" then return say({"tmb.craft-normal-only"}) end
  local need = shortfall(player, entry, queued_items(player))
  if need <= 0 then return say({"tmb-casper.craft-have-enough"}) end
  local recipe, err = shared.find_recipe(player, entry.name)
  if not recipe then return say(err) end
  local can = player.get_craftable_count(recipe)
  local each = shared.per_craft(recipe, entry.name)
  local want = math.ceil(need / each)
  local started = 0
  if can > 0 then
    started = player.begin_crafting{count = math.min(want, can), recipe = recipe, silent = true}
  end
  if started < want then
    -- some or all of it couldn't be crafted: list what's missing in the Ghost Project
    local needs = project_needs(player, queued_items(player))
    alert(player, flag_failure(player, entry.name, needs))
  end
  if started == 0 then return say({"tmb.craft-no-ingredients"}) end
  local proto = prototypes.item[entry.name]
  say({"tmb-casper.craft-one", started * each, proto and proto.localised_name or entry.name})
end

-- Ctrl + click on a bar item: TMB's "How many?" popup, pre-filled with the shortfall.
how_many = function(player, key, location, K)
  local job = S(K).jobs[player.index]
  local entry = job and job.counts[key]
  if not (entry and entry.is_item) then return end
  if entry.quality ~= "normal" then
    return player.create_local_flying_text{text = {"tmb.craft-normal-only"}, create_at_cursor = true}
  end
  local need = shortfall(player, entry, queued_items(player))
  shared.howmany_open(player, entry.name, nil, location, need > 0 and need or nil)
end

craft_all = function(player, K)
  local job = S(K).jobs[player.index]
  if not job then return end
  local queued = queued_items(player)
  local made, failed, short = 0, 0, 0
  local starved = {}  -- items that had a recipe but not enough ingredients

  for _, entry in pairs(job.counts) do
    if entry.is_item then
      local need = shortfall(player, entry, queued)  -- hand-crafting only makes normal quality
      if need > 0 then
        short = short + 1
        local recipe = entry.quality == "normal" and shared.find_recipe(player, entry.name) or nil
        local can = recipe and player.get_craftable_count(recipe) or 0
        if recipe and can > 0 then
          local each = shared.per_craft(recipe, entry.name)
          local want = math.ceil(need / each)
          local started = player.begin_crafting{count = math.min(want, can), recipe = recipe, silent = true}
          made = made + started * each
          if started < want then
            failed = failed + 1
            starved[#starved + 1] = entry.name
          end
          -- crafting may use up ingredients other entries wanted; later entries just get less
        else
          failed = failed + 1
          if recipe then starved[#starved + 1] = entry.name end
        end
      end
    end
  end

  if #starved > 0 then
    local needs = project_needs(player, queued_items(player))
    local blink, seen = {}, {}
    for _, item in pairs(starved) do
      for _, name in pairs(flag_failure(player, item, needs)) do
        if not seen[name] then seen[name] = true; blink[#blink + 1] = name end
      end
    end
    alert(player, blink)
  end

  local text
  if short == 0 then
    text = {"tmb-casper.craft-none-short"}
  elseif made == 0 then
    text = {"tmb-casper.craft-none-possible", failed}
  elseif failed > 0 then
    text = {"tmb-casper.craft-queued-some", made, failed}
  else
    text = {"tmb-casper.craft-queued", made}
  end
  player.create_local_flying_text{text = text, create_at_cursor = true}
end

---------------------------------------------------------------------------------------------------
-- Change N ghosts to: swap every tracked ghost of one type to another type and/or quality
---------------------------------------------------------------------------------------------------

local replace_index  -- [fast_replaceable_group] = {entity prototypes}, built once per session

local function box_size(proto)
  local b = proto.collision_box
  return (b.right_bottom.x - b.left_top.x), (b.right_bottom.y - b.left_top.y)
end

local function same_size(a, b)
  local aw, ah = box_size(a)
  local bw, bh = box_size(b)
  return math.abs(aw - bw) < 0.01 and math.abs(ah - bh) < 0.01
end

local function placeable(proto)
  local items = proto.items_to_place_this
  return proto and not proto.hidden and items and items[1] ~= nil
    and not (proto.flags and proto.flags["not-upgradable"])
end

local function item_order(proto)
  local first = proto.items_to_place_this[1]
  local name = type(first.name) == "string" and first.name or first.name.name
  local item = prototypes.item[name]
  if not item then return proto.order or proto.name end
  return (item.group and item.group.order or "") .. "|" .. (item.subgroup and item.subgroup.order or "") .. "|" ..
    (item.order or "") .. "|" .. name
end

-- Everything a ghost of `proto` can be swapped to, like the upgrade planner: same replace group, same footprint.
local function change_options(proto)
  if not replace_index then
    replace_index = {}
    for _, p in pairs(prototypes.entity) do
      local group = p.fast_replaceable_group
      if group and placeable(p) then
        replace_index[group] = replace_index[group] or {}
        table.insert(replace_index[group], p)
      end
    end
  end
  local list = {}
  local group = proto.fast_replaceable_group
  for _, p in pairs(group and replace_index[group] or {}) do
    if same_size(p, proto) then list[#list + 1] = p end
  end
  if #list == 0 then list[1] = proto end
  local keys = {}
  for _, p in pairs(list) do keys[p] = item_order(p) end
  table.sort(list, function(a, b) return keys[a] < keys[b] end)
  return list
end

-- The tracked ghosts of one bar entry (key "<type>|<quality>"), still valid.
-- Ghosts can't be looked up by unit number (their prototype lacks the get-by-unit-number flag),
-- so each one is found again at its stored position and matched by unit number.
local function ghosts_of(job, key)
  local list = {}
  for reg, record in pairs(job.ghosts) do
    if record.key == key and record.unit then
      local surface = game.get_surface(record.surface_index)
      if surface then
        for _, ghost in pairs(surface.find_entities_filtered{position = record.pos}) do
          if ghost.valid and ghost.unit_number == record.unit then
            list[#list + 1] = {reg = reg, record = record, ghost = ghost}
            break
          end
        end
      end
    end
  end
  return list
end

local function change_close(player)
  local frame = player.gui.screen[CHANGE]
  if frame then frame.destroy() end
end

-- Rebuild the choices and the confirm button from the popup's tags.
local function change_draw(frame)
  local t = frame.tags
  local body = frame.tmb_body
  body.clear()
  local slots = body.add{type = "frame", style = "slot_button_deep_frame"}
  local grid = slots.add{type = "table", column_count = math.min(#t.options, 10), style = "slot_table"}
  for _, name in ipairs(t.options) do
    local proto = prototypes.entity[name]
    local tip = {"", proto.localised_name}
    if t.sel_quality ~= "normal" then
      tip = {"", proto.localised_name, " (", prototypes.quality[t.sel_quality].localised_name, ")"}
    end
    if name == t.cur_name then tip = {"", tip, "\n", {"tmb-casper.change-current"}} end
    local button = grid.add{
      type = "sprite-button", style = "slot_button", sprite = "entity/" .. name,
      tooltip = tip, tags = {tmb_casper_change = "choice", name = name},
      toggled = (name == t.sel_name),
    }
    if t.sel_quality ~= "normal" then pcall(function() button.quality = t.sel_quality end) end
  end
  local row = body.add{type = "flow", direction = "horizontal"}
  row.style.vertical_align = "center"
  row.style.top_margin = 4
  local hint = row.add{type = "label", caption = {"tmb-casper.change-undo"}}
  hint.style.font_color = {0.7, 0.7, 0.7}
  local push = row.add{type = "empty-widget"}
  push.style.horizontally_stretchable = true
  row.add{
    type = "button", style = "green_button", caption = {"tmb-casper.change-confirm"},
    tags = {tmb_casper_change = "confirm"},
    enabled = (t.sel_name ~= t.cur_name or t.sel_quality ~= t.cur_quality),
  }
  -- quality buttons in the title bar
  local qt = frame.tmb_titlebar.tmb_qualities
  if qt then
    for _, b in pairs(qt.children) do b.toggled = (b.tags.quality == t.sel_quality) end
  end
end

-- What a tracked entity is (ghost) or will become (upgrade order): prototype and quality name.
local function current_target(entity)
  if entity.type == "entity-ghost" then
    return entity.ghost_prototype, entity.quality and entity.quality.name or "normal"
  end
  local target, quality = entity.get_upgrade_target()
  return target, quality and quality.name or "normal"
end

change_open = function(player, key, location, K)
  K = K or CASPER_K
  change_close(player)
  local job = S(K).jobs[player.index]
  if not job then return end
  local list = ghosts_of(job, key)
  if #list == 0 then
    player.create_local_flying_text{text = {"tmb-casper.change-gone"}, create_at_cursor = true}
    return
  end
  local proto, cur_quality = current_target(list[1].ghost)
  if not proto then
    player.create_local_flying_text{text = {"tmb-casper.change-gone"}, create_at_cursor = true}
    return
  end
  local options = change_options(proto)
  local quality_on = shared.quality_enabled()
  if #options < 2 and not quality_on then
    player.create_local_flying_text{text = {"tmb-casper.change-nothing"}, create_at_cursor = true}
    return
  end
  local names = {}
  for i, p in ipairs(options) do names[i] = p.name end

  local frame = player.gui.screen.add{type = "frame", name = CHANGE, direction = "vertical",
    tags = {key = key, kind = K.id, options = names, cur_name = proto.name, cur_quality = cur_quality,
            sel_name = proto.name, sel_quality = cur_quality}}
  local bar = frame.add{type = "flow", name = "tmb_titlebar", direction = "horizontal"}
  bar.style.horizontal_spacing = 8
  bar.style.vertical_align = "center"
  bar.drag_target = frame
  bar.add{type = "label", caption = {K.ritual and "tmb-casper.change-title-ritual" or "tmb-casper.change-title", #list},
    style = "frame_title", ignored_by_interaction = true}
  if quality_on then
    local qs = shared.quality_list()
    local qt = bar.add{type = "table", name = "tmb_qualities", column_count = math.min(#qs, 8), style = "slot_table"}
    for _, q in ipairs(qs) do
      qt.add{type = "sprite-button", style = "tmb_quality_button", sprite = "quality/" .. q.name,
        tooltip = q.localised_name, tags = {tmb_casper_change = "quality", quality = q.name}}
    end
  end
  local drag = bar.add{type = "empty-widget", style = "draggable_space_header"}
  drag.style.height = 24
  drag.style.minimal_width = 8
  drag.style.horizontally_stretchable = true
  drag.drag_target = frame
  bar.add{type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
    tooltip = {"tmb.close-window"}, tags = {tmb_casper_change = "close"}}
  local body = frame.add{type = "flow", name = "tmb_body", direction = "vertical"}
  body.style.vertical_spacing = 4
  change_draw(frame)

  -- open under the cursor, kept on screen
  local scale = player.display_scale
  local res = player.display_resolution
  local w = (#names * 40 + 60) * scale
  local h = 130 * scale
  local x, y = res.width / 2, res.height / 3
  if location then x, y = location.x - 40 * scale, location.y + 24 * scale end
  x = math.max(0, math.min(x, res.width - w))
  y = math.max(0, math.min(y, res.height - h))
  frame.location = {x = x, y = y}
  player.opened = frame
end

local function spot_key(surface_index, pos)
  return surface_index .. ":" .. pos.x .. "," .. pos.y
end

-- Swap a ghost in place, like the upgrade planner does on ghosts. Falls back to a new ghost in the
-- same spot if the game won't upgrade it (settings and undo are not kept then).
local function swap_ghost(player, ghost, target, quality, undo)
  local ok = pcall(function()
    ghost.order_upgrade{target = {name = target, quality = quality}, force = player.force,
      player = player, undo_index = undo.index}
    undo.index = 1
    if ghost.valid and ghost.to_be_upgraded() then ghost.apply_upgrade() end
  end)
  if ghost.valid and (not ok or ghost.ghost_name ~= target) then
    local spec = {
      name = "entity-ghost", inner_name = target, quality = quality,
      position = ghost.position, direction = ghost.direction, force = ghost.force, player = player,
    }
    if ghost.ghost_type == "underground-belt" then spec.type = ghost.belt_to_ground_type end
    local surface = ghost.surface
    ghost.destroy()
    surface.create_entity(spec)
  end
end

-- Keep both of a player's jobs open while entries move between them; close empty ones afterwards.
local function hold_jobs(player, on)
  for _, k in pairs({CASPER_K, RITUAL_K}) do
    local j = S(k).jobs[player.index]
    if j then j.holding = on or nil end
  end
  if not on then
    for _, k in pairs({CASPER_K, RITUAL_K}) do
      local j = S(k).jobs[player.index]
      if j then
        if j.remaining <= 0 then cancel_job(player.index, k) else mark_dirty(player.index, k) end
      end
    end
  end
end

local function job_for(player, K)
  local job = S(K).jobs[player.index]
  if not job then
    job = new_job(player, K)
    job.holding = true  -- only called while entries are moving; hold_jobs(false) settles it
    S(K).jobs[player.index] = job
  end
  return job
end

-- Remember a Casper change, so undo/redo can move its ghosts between Casper and Ritual.
local MAX_CHANGES = 20
local function remember_change(player, spots, from_name, from_quality, to_name, to_quality)
  local list = storage.casper.changes[player.index] or {}
  table.insert(list, {spots = spots, from = {name = from_name, quality = from_quality},
    to = {name = to_name, quality = to_quality}})
  while #list > MAX_CHANGES do table.remove(list, 1) end
  storage.casper.changes[player.index] = list
end

-- Change the tracked entities of `key` to `target` at `quality`.
-- Casper: the ghosts are swapped and the changed ones move over to Ritual.
-- Ritual: upgrade orders are re-targeted, and ghosts (taken over from Casper) are swapped again.
-- Returns changed, failed.
local function change_apply(player, key, target, quality, K, from_name, from_quality)
  K = K or CASPER_K
  local job = S(K).jobs[player.index]
  if not job then return 0, 0 end
  local target_proto = prototypes.entity[target]
  local list = ghosts_of(job, key)
  local spots, spot_list, surfaces = {}, {}, {}
  local undo = {index = 0}  -- first swap starts a new undo item; the rest join it
  hold_jobs(player, true)

  -- forget the old entries first; whatever sits in those spots afterwards is tracked again below
  for _, g in pairs(list) do
    local r = g.record
    spots[spot_key(r.surface_index, r.pos)] = true
    spot_list[#spot_list + 1] = {surface_index = r.surface_index, x = r.pos.x, y = r.pos.y}
    local box = surfaces[r.surface_index]
    if not box then
      surfaces[r.surface_index] = {r.pos.x, r.pos.y, r.pos.x, r.pos.y}
    else
      box[1], box[2] = math.min(box[1], r.pos.x), math.min(box[2], r.pos.y)
      box[3], box[4] = math.max(box[3], r.pos.x), math.max(box[4], r.pos.y)
    end
  end
  for _, g in pairs(list) do
    if job.ghosts[g.reg] then drop_ghost(player.index, g.reg, K) end
  end

  for _, g in pairs(list) do
    local entity = g.ghost
    if entity.valid then
      local proto, q = current_target(entity)
      if not proto or (proto.name == target and q == quality) then
        -- nothing to do (e.g. the other end of an underground swapped earlier)
      elseif (proto.fast_replaceable_group ~= target_proto.fast_replaceable_group and proto.name ~= target)
          or not same_size(proto, target_proto) then
        -- can't become that type; stays as it is
      elseif entity.type == "entity-ghost" then
        swap_ghost(player, entity, target, quality, undo)
      else
        pcall(function()
          entity.order_upgrade{target = {name = target, quality = quality}, force = player.force,
            player = player, undo_index = undo.index}
          undo.index = 1
        end)
      end
    end
  end

  -- track what sits where the old entries were, and count the changed ones
  local changed = 0
  for surface_index, box in pairs(surfaces) do
    local surface = game.get_surface(surface_index)
    local to_casper, to_ritual = {}, {}
    if surface then
      local area = {{box[1] - 1, box[2] - 1}, {box[3] + 1, box[4] + 1}}
      for _, entity in pairs(surface.find_entities_filtered{area = area, force = player.force}) do
        if spots[spot_key(surface_index, entity.position)] then
          local is_ghost = entity.type == "entity-ghost"
          if is_ghost or entity.to_be_upgraded() then
            local proto, q = current_target(entity)
            local done = proto and proto.name == target and q == quality
            if done then changed = changed + 1 end
            -- Casper hands changed ghosts to Ritual; everything else stays with its tracker
            if not K.ritual and is_ghost and not done then
              to_casper[#to_casper + 1] = entity
            elseif K.ritual or is_ghost then
              to_ritual[#to_ritual + 1] = entity
            end
          end
        end
      end
    end
    if #to_casper > 0 then add_ghosts(player, job_for(player, CASPER_K), surface, nil, to_casper) end
    if #to_ritual > 0 then add_ghosts(player, job_for(player, RITUAL_K), surface, nil, to_ritual) end
  end
  if not K.ritual and changed > 0 then
    remember_change(player, spot_list, from_name, from_quality, target, quality)
  end
  hold_jobs(player, false)
  return changed, math.max(0, #list - changed)
end

-- After undo/redo: ghosts from remembered Casper changes go to Ritual if they're the new type,
-- back to Casper if they're the old type again.
local function resort_changes(player)
  local list = storage.casper.changes[player.index]
  if not list then return end
  local index = {}  -- [kind id] = {[spot] = reg}
  for _, K in pairs({CASPER_K, RITUAL_K}) do
    index[K.id] = {}
    local job = S(K).jobs[player.index]
    for reg, r in pairs(job and job.ghosts or {}) do index[K.id][spot_key(r.surface_index, r.pos)] = reg end
  end
  local keep = {}
  hold_jobs(player, true)
  for _, change in ipairs(list) do
    local alive = false
    for _, spot in pairs(change.spots) do
      local surface = game.get_surface(spot.surface_index)
      local ghosts = surface and surface.find_entities_filtered{position = {spot.x, spot.y}, type = "entity-ghost",
        force = player.force} or {}
      for _, ghost in pairs(ghosts) do
        local q = ghost.quality and ghost.quality.name or "normal"
        local dest
        if ghost.ghost_name == change.to.name and q == change.to.quality then dest = RITUAL_K
        elseif ghost.ghost_name == change.from.name and q == change.from.quality then dest = CASPER_K end
        if dest then
          alive = true
          local k = spot_key(spot.surface_index, ghost.position)
          local other = dest.ritual and CASPER_K or RITUAL_K
          local reg = index[other.id][k]
          if reg then
            untrack(player.index, reg, other)
            index[other.id][k] = nil
          end
          local dest_job = S(dest).jobs[player.index]
          local tracked = dest_job and ghost.unit_number and dest_job.units[ghost.unit_number]
          if not tracked then
            local old = index[dest.id][k]
            if old and dest_job and dest_job.ghosts[old] then untrack(player.index, old, dest) end
            add_ghosts(player, job_for(player, dest), surface, nil, {ghost})
            mark_dirty(player.index, dest)
          end
        end
      end
    end
    if alive then keep[#keep + 1] = change end
  end
  storage.casper.changes[player.index] = #keep > 0 and keep or nil
  hold_jobs(player, false)
end

change_click = function(player, element, what)
  local frame = player.gui.screen[CHANGE]
  if not frame then return end
  local t = frame.tags
  if what == "close" then return change_close(player) end
  if what == "choice" then
    t.sel_name = element.tags.name
    frame.tags = t
    return change_draw(frame)
  end
  if what == "quality" then
    t.sel_quality = element.tags.quality
    frame.tags = t
    return change_draw(frame)
  end
  if what == "confirm" then
    if t.sel_name == t.cur_name and t.sel_quality == t.cur_quality then return end
    change_close(player)
    local changed, failed = change_apply(player, t.key, t.sel_name, t.sel_quality, kind_named(t.kind),
      t.cur_name, t.cur_quality)
    local text = {"tmb-casper.change-done", changed}
    if failed > 0 then text = {"", text, "\n", {"tmb-casper.change-failed", failed}} end
    player.create_local_flying_text{text = text, create_at_cursor = true}
  end
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

events.on_init(init_storage)

---------------------------------------------------------------------------------------------------
-- Leftover clean-up
---------------------------------------------------------------------------------------------------
-- Highlight boxes (the green corner brackets) are real entities saved with the map. When a mod is
-- removed the game deletes its drawings but not the boxes it placed, so switching from the standalone
-- Casper with a job running left its brackets behind. This removes Casper-style boxes (copy type, no
-- blink, shown to one player) that no tracked ghost uses, and TMB drawings nothing refers to.
local function sweep_leftovers()
  local function key(entity, player_index)
    local p = entity.position
    return entity.surface.index .. "|" .. p.x .. "," .. p.y .. "|" .. tostring(player_index)
  end
  local keep_boxes, keep_drawings = {}, {}
  local function keep(obj) if obj and obj.valid then keep_drawings[obj.id] = true end end
  for _, K in pairs({CASPER_K, RITUAL_K}) do
    for player_index, job in pairs(S(K).jobs) do
      for _, r in pairs(job.ghosts) do
        if r.box and r.box.valid then keep_boxes[key(r.box, player_index)] = true end
        keep(r.marker)
        for _, o in pairs(r.pieces or {}) do keep(o) end
        for _, o in pairs(r.corners or {}) do keep(o) end
      end
      for _, o in pairs(job.area_objs or {}) do keep(o) end
    end
    for _, objects in pairs(S(K).arrows) do
      for _, o in pairs(objects) do keep(o) end
    end
  end

  local boxes, drawings = 0, 0
  for _, surface in pairs(game.surfaces) do
    for _, box in pairs(surface.find_entities_filtered{name = "highlight-box"}) do
      local who = box.render_player
      if box.valid and who and box.highlight_box_type == "copy" and box.highlight_box_blink_interval == 0
          and not keep_boxes[key(box, who.index)] then
        box.destroy()
        boxes = boxes + 1
      end
    end
  end
  for _, obj in pairs(rendering.get_all_objects("too-many-buildables")) do
    if not keep_drawings[obj.id] then
      obj.destroy()
      drawings = drawings + 1
    end
  end
  return boxes, drawings
end

-- Rolled back from 0.11.5/0.11.6: drop the Exorcist's deconstruction tracking (and Hunter) data
-- those builds left in the save, with every drawing and bar it made.
local function drop_decon_leftovers()
  local d = storage.casper and storage.casper.decon
  if d then
    for _, job in pairs(d.jobs or {}) do
      for _, r in pairs(job.ghosts or {}) do
        destroy_all(r.corners)
        destroy_obj(r.marker)
        destroy_all(r.pieces)
      end
      destroy_all(job.area_objs)
    end
    for _, objs in pairs(d.arrows or {}) do destroy_all(objs) end
    storage.casper.decon = nil
  end
  if storage.casper then storage.casper.auto_decon = nil end
  for _, player in pairs(game.players) do
    local root = player.gui.top[ROOT]
    if root and root.tmb_decon_panel then root.tmb_decon_panel.destroy() end
    if root and #root.children == 0 then root.destroy() end
  end
end

events.on_configuration_changed(function(data)
  init_storage()
  drop_decon_leftovers()
  -- Once per save from 0.9.6 on, and again whenever the standalone Casper is removed.
  local changes = data and data.mod_changes or {}
  local standalone = changes["casper-ghost-tracking"]
  if not storage.casper.swept_v1 or (standalone and not standalone.new_version) then
    storage.casper.swept_v1 = true
    sweep_leftovers()
  end
  -- Older versions drew belts/pipes as run boxes (<= 0.6.0) or group lines (0.7.0); switch to bracket outlines.
  for player_index, job in pairs(storage.casper.jobs) do
    if job.runs or job.groups then
      for _, run in pairs(job.runs or {}) do
        destroy_obj(run.box)
        destroy_obj(run.marker)
      end
      for _, group in pairs(job.groups or {}) do destroy_all(group.objects) end
      job.runs, job.next_run = nil, nil
      job.groups, job.group_dirty, job.next_group = nil, nil, nil
      for _, r in pairs(job.ghosts) do r.run, r.group = nil, nil end
      rebuild_all_tiles(job, player_index)
    end
  end
  storage.casper.group_work = nil
  for _, player in pairs(game.players) do
    mark_dirty(player.index, CASPER_K)
    mark_dirty(player.index, RITUAL_K)
    draw_strip(player)
  end
end)

if defines.events.on_player_start_selected_area then
  events.on_event(defines.events.on_player_start_selected_area, on_drag)
end
if defines.events.on_player_change_selected_area then
  events.on_event(defines.events.on_player_change_selected_area, on_drag)
end
if defines.events.on_player_cancel_selected_area then
  events.on_event(defines.events.on_player_cancel_selected_area, function(event)
    local K = tool_kind(event.item)
    if K then clear_preview(event.player_index, K) end
  end)
end

-- The release of an alt-click also arrives as a tiny selection; ignore it.
local function is_cancel_release(event)
  local area = event.area
  local w = area.right_bottom.x - area.left_top.x
  local h = area.right_bottom.y - area.left_top.y
  local cancelled_at = storage.casper.cancel_tick[event.player_index]
  return w < CLICK_SIZE and h < CLICK_SIZE and cancelled_at ~= nil and event.tick - cancelled_at <= CANCEL_GRACE
end

events.on_event(defines.events.on_player_selected_area, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if event.item == EXORCIST then
    if is_click(event) then exorcist_click(player, event, true) else exorcist_remove_area(player, event) end
    return
  end
  local K = tool_kind(event.item)
  if not K then return end
  clear_preview(player.index, K)
  if is_cancel_release(event) then return end
  start_job(player, event.surface, event.area, K)
end)

events.on_event(defines.events.on_player_alt_selected_area, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if event.item == EXORCIST then
    if is_click(event) then exorcist_click(player, event, false) else exorcist_pick_area(player, event) end
    return
  end
  local K = tool_kind(event.item)
  if not K then return end
  clear_preview(player.index, K)
  if is_cancel_release(event) then return end
  extend_job(player, event.surface, event.area, K)
end)

-- Alt-click with Casper or Ritual in hand cancels that tracker's job.
events.on_event("tmb-casper-cancel-job", function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local K = holding(player, TOOL) and CASPER_K or holding(player, RITUAL) and RITUAL_K or nil
  if not K then return end
  storage.casper.cancel_tick[player.index] = event.tick
  if cancel_job(player.index, K) then
    player.create_local_flying_text{text = {K.ritual and "tmb-casper.ritual-cancelled" or "tmb-casper.cancelled"},
      create_at_cursor = true}
  end
end)

-- A tracked entity is gone: a ghost was built or removed, or an upgrade finished (the old entity is replaced).
events.on_event(defines.events.on_object_destroyed, function(event)
  local reg = event.registration_number
  for _, K in pairs({CASPER_K, RITUAL_K}) do
    local watchers = S(K).watchers[reg]
    if watchers then
      S(K).watchers[reg] = nil
      for player_index in pairs(watchers) do
        drop_ghost(player_index, reg, K)
      end
    end
  end
end)

---------------------------------------------------------------------------------------------------
-- Picking up new entries inside a job's area (from anyone on the same team)
---------------------------------------------------------------------------------------------------

local function pick_up(entity, K)
  if not (entity and entity.valid) then return end
  local surface_index = entity.surface.index
  for player_index, job in pairs(S(K).jobs) do
    if job.boxes and next(job.boxes) and not job.holding and in_area(job, surface_index, entity.position)
        and not (entity.unit_number and job.units[entity.unit_number]) then
      local player = game.get_player(player_index)
      if player and player.valid and player.force.index == entity.force.index then
        if add_ghosts(player, job, entity.surface, nil, {entity}) > 0 then mark_dirty(player_index, K) end
      end
    end
  end
end

-- Auto-track (shortcut toggle): while it's on, every paste of a blueprint, a book's blueprint,
-- a library record or a copy-paste adds the ghosts it creates to Casper and the upgrades it
-- orders to Ritual. No area: only what the paste made. A finished job ends as usual and the
-- next paste starts a new one. The game keeps the toggle state per player.
local AUTO = "tmb-casper-auto-track"

local function auto_on(player)
  local ok, on = pcall(player.is_shortcut_toggled, AUTO)
  return ok and on
end

local function auto_toggle(player)
  local on = not auto_on(player)
  player.set_shortcut_toggled(AUTO, on)
  player.create_local_flying_text{text = {on and "tmb-casper.auto-on" or "tmb-casper.auto-off"}, create_at_cursor = true}
end

-- on_pre_build with a blueprint in hand marks this tick as a paste; what it builds this tick
-- is collected and handed over on the next tick, in one go per player.
local function auto_pasting(player_index, tick)
  local p = storage.casper.auto_paste
  return p and p[player_index] == tick
end

local function auto_collect(player_index, entity, K)
  local batch = storage.casper.auto_batch or {}
  storage.casper.auto_batch = batch
  local b = batch[player_index] or {[CASPER_K.id] = {}, [RITUAL_K.id] = {}}
  batch[player_index] = b
  local list = b[K.id]
  list[#list + 1] = entity
end

local function auto_flush()
  local batch = storage.casper and storage.casper.auto_batch
  if not batch or next(batch) == nil then return end
  storage.casper.auto_batch = {}
  for player_index, b in pairs(batch) do
    local player = game.get_player(player_index)
    if player and player.valid then
      for _, K in ipairs({CASPER_K, RITUAL_K}) do
        local by_surface = {}
        for _, e in ipairs(b[K.id]) do
          if e.valid then
            local list = by_surface[e.surface.index] or {}
            by_surface[e.surface.index] = list
            list[#list + 1] = e
          end
        end
        local job, fresh = S(K).jobs[player_index], false
        local added = 0
        for surface_index, list in pairs(by_surface) do
          if not job then job = new_job(player, K); fresh = true end
          added = added + add_ghosts(player, job, game.get_surface(surface_index), nil, list)
        end
        if added > 0 then
          if fresh then
            S(K).jobs[player_index] = job
            player.create_local_flying_text{text = {K.tracking, job.remaining}, create_at_cursor = true}
            draw_panel(player, K)
          else
            player.create_local_flying_text{text = {K.added, added, job.remaining}, create_at_cursor = true}
            mark_dirty(player_index, K)
          end
        elseif fresh and job then
          destroy_all(job.area_objs)
        end
      end
    end
  end
end

events.on_event(defines.events.on_pre_build, function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid and auto_on(player)) then return end
  if not player.is_cursor_blueprint() then return end
  storage.casper.auto_paste = storage.casper.auto_paste or {}
  storage.casper.auto_paste[event.player_index] = event.tick
end)

events.on_event(defines.events.on_tick, auto_flush)

events.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= AUTO then return end
  local player = game.get_player(event.player_index)
  if player then auto_toggle(player) end
end)

events.on_event(AUTO, function(event)
  local player = game.get_player(event.player_index)
  if player then auto_toggle(player) end
end)

local function on_new_ghost(event)
  local entity = event.entity or event.ghost
  if entity and entity.valid and entity.type == "entity-ghost" then
    pick_up(entity, CASPER_K)
    if event.player_index and auto_pasting(event.player_index, event.tick) then
      auto_collect(event.player_index, entity, CASPER_K)
    end
  end
end
events.on_event(defines.events.on_built_entity, on_new_ghost)
events.on_event(defines.events.script_raised_built, on_new_ghost)
events.on_event(defines.events.on_post_entity_died, on_new_ghost)

-- New or changed upgrade orders inside a Ritual area are tracked (a changed target re-sorts the entry).
events.on_event(defines.events.on_marked_for_upgrade, function(event)
  local entity = event.entity
  if not (entity and entity.valid) or entity.type == "entity-ghost" then return end
  for player_index, job in pairs(S(RITUAL_K).jobs) do
    local reg = entity.unit_number and job.units[entity.unit_number] and job.unit_reg[entity.unit_number]
    if reg and not job.holding then
      local key = describe_upgrade(entity)
      local record = job.ghosts[reg]
      if record and key and record.key ~= key then
        local player = game.get_player(player_index)
        job.holding = true
        untrack(player_index, reg, RITUAL_K)
        job.holding = nil
        if player then add_ghosts(player, job, entity.surface, nil, {entity}) end
        if job.remaining <= 0 then cancel_job(player_index, RITUAL_K) else mark_dirty(player_index, RITUAL_K) end
      end
    end
  end
  pick_up(entity, RITUAL_K)
  if event.player_index and auto_pasting(event.player_index, event.tick) then
    auto_collect(event.player_index, entity, RITUAL_K)
  end
end)

-- A cancelled upgrade drops off every Ritual bar tracking it.
events.on_event(defines.events.on_cancelled_upgrade, function(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.unit_number) then return end
  for player_index, job in pairs(S(RITUAL_K).jobs) do
    local reg = job.units[entity.unit_number] and job.unit_reg[entity.unit_number]
    local record = reg and job.ghosts[reg]
    if record and not record.ghost then untrack(player_index, reg, RITUAL_K) end
  end
end)

-- Undo/redo of a Casper change moves its ghosts between Casper and Ritual.
local function on_undo_redo(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then resort_changes(player) end
end
events.on_event(defines.events.on_undo_applied, on_undo_redo)
events.on_event(defines.events.on_redo_applied, on_undo_redo)

-- Leaving the planet cancels the jobs. Remote view does not change the physical surface.
local function check_home(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  for _, K in pairs({CASPER_K, RITUAL_K}) do
    local job = S(K).jobs[player.index]
    if job and player.physical_surface_index ~= job.home_surface_index then
      cancel_job(player.index, K)
    else
      S(K).hover[player.index] = nil
      refresh_guide(player, K)
    end
  end
end

events.on_event(defines.events.on_player_changed_surface, check_home)
events.on_event(defines.events.on_player_controller_changed, check_home)
events.on_event(defines.events.on_player_respawned, check_home)

local function redraw(event)
  for _, K in pairs({CASPER_K, RITUAL_K}) do
    if S(K).jobs[event.player_index] then mark_dirty(event.player_index, K) end
  end
end

events.on_event(defines.events.on_player_display_resolution_changed, redraw)
events.on_event(defines.events.on_player_display_scale_changed, redraw)

-- Putting a tool away mid-drag drops its preview; putting the Exorcist away clears its picks.
events.on_event(defines.events.on_player_cursor_stack_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  for _, K in pairs({CASPER_K, RITUAL_K}) do
    if (S(K).preview[player.index] or S(K).pending[player.index]) and not holding(player, K.tool) then
      clear_preview(player.index, K)
    end
  end

  if holding(player, EXORCIST) then
    draw_strip(player)
  else
    local root = get_root(player, false)
    if storage.casper.picked[player.index] or (root and root[STRIP]) then
      storage.casper.picked[player.index] = nil
      draw_strip(player)
    end
  end
end)

events.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  local tags = element and element.valid and element.tags
  if not tags then return end
  local player = game.get_player(event.player_index)
  if not player then return end

  -- Change popup buttons.
  if tags.tmb_casper_change then return change_click(player, element, tags.tmb_casper_change) end

  -- Bar icon: left-click crafts all, right-click folds. The Exorcist icon folds Casper's bar and the strip.
  if tags.tmb_casper_toggle then
    local K = kind_named(tags.tmb_kind)
    if tags.tmb_casper_craft and event.button == defines.mouse_button_type.left then
      return craft_all(player, K)
    end
    S(K).collapsed[player.index] = not S(K).collapsed[player.index] or nil
    S(K).hover[player.index] = nil
    draw_panel(player, K)
    if not K.ritual then draw_strip(player) end
    refresh_guide(player, K)
    return
  end

  -- Item icons: left-click pins/unpins the guide, Shift craft, Ctrl how many?, right-click change.
  local key = tags.tmb_casper_key
  if not key then return end
  local K = kind_named(tags.tmb_kind)
  if event.button == defines.mouse_button_type.right then
    return change_open(player, key, event.cursor_display_location, K)
  end
  if event.shift and not event.control then return craft_one(player, key, K) end
  if event.control and not event.shift and not event.alt then
    return how_many(player, key, event.cursor_display_location, K)
  end
  if S(K).pinned[player.index] == key then
    S(K).pinned[player.index] = nil
  else
    S(K).pinned[player.index] = key
  end
  S(K).hover[player.index] = nil
  draw_panel(player, K)
  refresh_guide(player, K)
end)

events.on_event(defines.events.on_gui_closed, function(event)
  local element = event.element
  if element and element.valid and element.name == CHANGE then element.destroy() end
end)

-- Hovering an item icon previews the guide; leaving falls back to the pinned guide.
events.on_event(defines.events.on_gui_hover, function(event)
  local element = event.element
  local key = element and element.valid and element.tags and element.tags.tmb_casper_key
  if not key then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local K = kind_named(element.tags.tmb_kind)
  S(K).hover[player.index] = {key = key, expires = event.tick + HOVER_TTL}
  refresh_guide(player, K)
end)

events.on_event(defines.events.on_gui_leave, function(event)
  local element = event.element
  if not (element and element.valid and element.tags and element.tags.tmb_casper_key) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local K = kind_named(element.tags.tmb_kind)
  S(K).hover[player.index] = nil
  refresh_guide(player, K)
end)

events.on_event(defines.events.on_player_removed, function(event)
  local index = event.player_index
  for _, K in pairs({CASPER_K, RITUAL_K}) do
    cancel_job(index, K)
    local st = S(K)
    st.pending[index] = nil
    st.preview[index] = nil
    st.collapsed[index] = nil
    st.hover[index] = nil
    st.pinned[index] = nil
    clear_guide(index, K)
  end
  storage.casper.cancel_tick[index] = nil
  storage.casper.gp[index] = nil
  storage.casper.picked[index] = nil
  storage.casper.changes[index] = nil
end)

-- Batched work: drag previews and bar redraws, so big drags and robot swarms stay cheap.
events.on_nth_tick(6, function()
  for _, K in pairs({CASPER_K, RITUAL_K}) do
    local st = S(K)
    if next(st.pending) ~= nil then
      local pending = st.pending
      st.pending = {}
      for player_index, drag in pairs(pending) do
        local player = game.get_player(player_index)
        if player and player.valid then
          st.preview[player_index] = build_preview(player, drag, K)
          st.dirty[player_index] = true
        end
      end
    end

    if next(st.dirty) ~= nil then
      local dirty = st.dirty
      st.dirty = {}
      for player_index in pairs(dirty) do
        local player = game.get_player(player_index)
        if player and player.valid then
          draw_panel(player, K)
          if st.hover[player_index] or st.pinned[player_index] then refresh_guide(player, K) end
        end
      end
    end
  end
end)

-- A pinned guide re-aims once a second as you move around.
events.on_nth_tick(60, function()
  for _, K in pairs({CASPER_K, RITUAL_K}) do
    for player_index in pairs(S(K).pinned) do
      local player = game.get_player(player_index)
      if player and player.valid and not S(K).hover[player_index] then refresh_guide(player, K) end
    end
  end
end)
