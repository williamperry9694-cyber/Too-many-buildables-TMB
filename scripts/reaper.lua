-- Reaper: a finder for things already marked for deconstruction.
--
-- Drag over an area: everything marked for deconstruction in it (your buildings, trees, rocks,
-- plants, items on the ground, tiles) that a radar can see is counted once, by type, on a bar
-- below Casper's and Ritual's. Shift-drag adds another box. The tool never marks or cancels
-- anything, and it never recounts: a count only drops as the things it counted are removed (or
-- their mark is cancelled). Hover a type to point to the nearest one, click to keep pointing.
-- Right-click a type to hunt it: every marked one of that type a radar can see on the surface is
-- added, once. Shift + right-click stops the hunt and drops what it added.

local events = require("scripts.events")

local TOOL = "tmb-reaper"
local ROOT = "tmb_casper_root"            -- the top-bar flow Casper and Ritual use
local PANEL = "tmb_reaper_panel"
local ABOVE = {"tmb_casper_panel", "tmb_ritual_panel"}  -- bars that sit above Reaper's

local SLOT_SIZE = 40
local RIGHT_RESERVE = 330
local EDGE_PADDING = 40
local ROW_LENGTH = 10
local MAX_ROWS = 2
local HOVER_TTL = 600
local CANCEL_GRACE = 120
local ARROW_COLOR = {r = 0.75, g = 0.45, b = 1, a = 0.9}
local TILE_PROXY = "deconstructible-tile-proxy"
local GROUND = "item-entity"

---------------------------------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------------------------------
-- storage.reaper = {
--   jobs = {[player_index] = {things = {[reg] = rec}, counts = {[key] = entry}, remaining}},
--   watchers = {[reg] = {[player_index] = true}},
--   dirty, collapsed, arrows, hover, pinned, cancel_tick: per player
-- }
-- rec   = {key, surface_index, x, y, hunt?}
-- entry = {name, quality, sprite, is_item, amount, match, hunted?}
--   match = {kind = "entity", names = {[entity name] = true}} | {kind = "ground", item} | {kind = "tile", tile}

local function init_storage()
  storage.reaper = storage.reaper or {}
  local r = storage.reaper
  for _, k in pairs({"jobs", "watchers", "dirty", "collapsed", "arrows", "hover", "pinned", "cancel_tick"}) do
    r[k] = r[k] or {}
  end
end

local function R()
  return storage.reaper
end

---------------------------------------------------------------------------------------------------
-- What a marked thing is
---------------------------------------------------------------------------------------------------

local function quality_of(entity)
  return (entity.quality and entity.quality.name) or "normal"
end

-- key, info for something marked for deconstruction; nil for things Reaper leaves alone.
local function describe(entity)
  local etype = entity.type
  if etype == "entity-ghost" or etype == "tile-ghost" then return nil end
  if etype == GROUND then
    local stack = entity.stack
    if not (stack and stack.valid_for_read) then return nil end
    return "ground:" .. stack.name, {name = stack.name, quality = "normal", sprite = "item/" .. stack.name,
      is_item = true, match = {kind = "ground", item = stack.name}}
  end
  if entity.name == TILE_PROXY then
    local tile = entity.surface.get_tile(entity.position.x, entity.position.y)
    local tname = tile and tile.valid and tile.name
    if not tname then return nil end
    return "tile:" .. tname, {name = tname, quality = "normal", sprite = "tile/" .. tname,
      is_tile = true, match = {kind = "tile", tile = tname}}
  end
  local q = quality_of(entity)
  local items = entity.prototype and entity.prototype.items_to_place_this
  local first = items and items[1]
  if first then
    local name = first.name
    if type(name) ~= "string" then name = name.name end
    return name .. "|" .. q, {name = name, quality = q, sprite = "item/" .. name, is_item = true,
      match = {kind = "entity", names = {}}}
  end
  return "entity:" .. entity.name .. "|" .. q, {name = entity.name, quality = q, sprite = "entity/" .. entity.name,
    is_item = false, match = {kind = "entity", names = {}}}
end

local function ours(player, entity)
  local f = entity.force
  return f and (f.index == player.force.index or f.name == "neutral")
end

-- Radar range: a chunk the team can see right now. Cached per scan.
local function visible_fn(player, surface)
  local force, seen = player.force, {}
  return function(pos)
    local cx, cy = math.floor(pos.x / 32), math.floor(pos.y / 32)
    local k = cx .. "," .. cy
    local v = seen[k]
    if v == nil then
      v = force.is_chunk_visible(surface, {x = cx, y = cy}) and true or false
      seen[k] = v
    end
    return v
  end
end

---------------------------------------------------------------------------------------------------
-- Jobs
---------------------------------------------------------------------------------------------------

-- Add marked entities to a job. Returns added, skipped (outside radar range).
local function add_all(player, job, surface, found, hunt_key)
  local visible = visible_fn(player, surface)
  local added, skipped = 0, 0
  for _, e in pairs(found) do
    if e.valid and (e.name == TILE_PROXY or e.to_be_deconstructed()) and ours(player, e) then
      local key, info = describe(e)
      if key and (not hunt_key or key == hunt_key) then
        if not visible(e.position) then
          skipped = skipped + 1
        else
          local reg = script.register_on_object_destroyed(e)
          if not job.things[reg] then
            local entry = job.counts[key]
            if not entry then
              info.amount = 0
              job.counts[key] = info
              entry = info
            end
            if entry.match.kind == "entity" then entry.match.names[e.name] = true end
            entry.amount = entry.amount + 1
            job.things[reg] = {key = key, surface_index = surface.index, x = e.position.x, y = e.position.y,
              hunt = hunt_key and true or nil}
            job.remaining = job.remaining + 1
            local w = R().watchers[reg]
            if not w then w = {}; R().watchers[reg] = w end
            w[player.index] = true
            added = added + 1
          end
        end
      end
    end
  end
  return added, skipped
end

local clear_guide, refresh_guide, draw_panel  -- below

local function mark_dirty(player_index)
  R().dirty[player_index] = true
end

local function end_job(player_index)
  local job = R().jobs[player_index]
  if not job then return false end
  for reg in pairs(job.things) do
    local w = R().watchers[reg]
    if w then
      w[player_index] = nil
      if next(w) == nil then R().watchers[reg] = nil end
    end
  end
  R().jobs[player_index] = nil
  R().pinned[player_index] = nil
  R().hover[player_index] = nil
  clear_guide(player_index)
  mark_dirty(player_index)
  return true
end

-- Something counted is gone (removed, or its mark cancelled).
local function drop(player_index, reg)
  local job = R().jobs[player_index]
  local rec = job and job.things[reg]
  if not rec then return end
  job.things[reg] = nil
  job.remaining = job.remaining - 1
  local entry = job.counts[rec.key]
  if entry then
    entry.amount = entry.amount - 1
    if entry.amount <= 0 then job.counts[rec.key] = nil end
  end
  if job.remaining <= 0 then end_job(player_index) else mark_dirty(player_index) end
end

local function untrack(player_index, reg)
  local w = R().watchers[reg]
  if w then
    w[player_index] = nil
    if next(w) == nil then R().watchers[reg] = nil end
  end
  drop(player_index, reg)
end

local function reap(player, surface, area, grow)
  local job = R().jobs[player.index]
  if not grow and job then end_job(player.index); job = nil end
  local fresh = not job
  job = job or {things = {}, counts = {}, remaining = 0}
  local found = surface.find_entities_filtered{area = area, to_be_deconstructed = true}
  for _, p in pairs(surface.find_entities_filtered{area = area, name = TILE_PROXY}) do found[#found + 1] = p end
  local added, skipped = add_all(player, job, surface, found)
  if job.remaining > 0 then
    R().jobs[player.index] = job
    mark_dirty(player.index)
  end
  local text
  if added > 0 then
    text = fresh and {"tmb-reaper.tracking", added} or {"tmb-reaper.added", added, job.remaining}
  elseif skipped > 0 then
    text = {"tmb-reaper.out-of-range"}
  else
    text = fresh and {"tmb-reaper.none"} or {"tmb-reaper.none-new"}
  end
  if added > 0 and skipped > 0 then text = {"", text, "\n", {"tmb-reaper.skipped", skipped}} end
  player.create_local_flying_text{text = text, create_at_cursor = true}
end

---------------------------------------------------------------------------------------------------
-- Hunt: one type, everywhere a radar can see on the surface you're looking at
---------------------------------------------------------------------------------------------------

local function hunt(player, key)
  local job = R().jobs[player.index]
  local entry = job and job.counts[key]
  if not entry then return end
  local surface = player.surface
  local m = entry.match
  local found = {}
  local function take(list) for _, e in pairs(list) do found[#found + 1] = e end end
  if m.kind == "entity" then
    for ename in pairs(m.names) do
      take(surface.find_entities_filtered{name = ename, to_be_deconstructed = true, quality = entry.quality})
    end
  elseif m.kind == "ground" then
    take(surface.find_entities_filtered{type = GROUND, to_be_deconstructed = true})
  else
    take(surface.find_entities_filtered{name = TILE_PROXY})
  end
  local added = add_all(player, job, surface, found, key)
  entry.hunted = true
  mark_dirty(player.index)
  player.create_local_flying_text{text = added > 0 and {"tmb-reaper.hunt-found", added} or {"tmb-reaper.hunt-none"},
    create_at_cursor = true}
end

local function stop_hunt(player, key)
  local job = R().jobs[player.index]
  local entry = job and job.counts[key]
  if not (entry and entry.hunted) then return end
  entry.hunted = nil
  local regs = {}
  for reg, rec in pairs(job.things) do
    if rec.key == key and rec.hunt then regs[#regs + 1] = reg end
  end
  for _, reg in ipairs(regs) do untrack(player.index, reg) end
  mark_dirty(player.index)
  player.create_local_flying_text{text = {"tmb-reaper.hunt-stopped"}, create_at_cursor = true}
end

---------------------------------------------------------------------------------------------------
-- Guide: arrow + dashed line to the nearest one of a type
---------------------------------------------------------------------------------------------------

clear_guide = function(player_index)
  local objs = R().arrows[player_index]
  if objs then
    for _, o in pairs(objs) do if o and o.valid then o.destroy() end end
  end
  R().arrows[player_index] = nil
end

local function nearest(job, key, surface_index, from)
  local best, best_d
  for _, rec in pairs(job.things) do
    if rec.key == key and rec.surface_index == surface_index then
      local dx, dy = rec.x - from.x, rec.y - from.y
      local d = dx * dx + dy * dy
      if not best_d or d < best_d then best, best_d = rec, d end
    end
  end
  return best and {x = best.x, y = best.y}
end

local function draw_guide(player, key, ttl)
  clear_guide(player.index)
  local job = R().jobs[player.index]
  if not job then return end
  local surface = player.surface
  local character = player.character
  local on_character = character and character.valid and character.surface == surface
  local origin = on_character and character or player.position
  local from = on_character and character.position or player.position
  local target = nearest(job, key, surface.index, from)
  if not target then return end
  local objects = {}
  local function add(fn, spec)
    spec.surface = surface
    spec.players = {player.index}
    spec.time_to_live = ttl
    local ok, obj = pcall(fn, spec)
    if ok and obj then objects[#objects + 1] = obj end
  end
  for _, mode in pairs({"game", "chart"}) do
    add(rendering.draw_line, {color = ARROW_COLOR, width = 3, from = origin, to = target,
      dash_length = 0.6, gap_length = 0.4, render_mode = mode})
  end
  add(rendering.draw_sprite, {sprite = "utility/indication_arrow", target = origin, orientation_target = target,
    oriented_offset = {0, -2}, x_scale = 1.5, y_scale = 1.5, tint = ARROW_COLOR})
  add(rendering.draw_circle, {color = ARROW_COLOR, radius = 1, width = 4, filled = false, target = target})
  R().arrows[player.index] = objects
end

refresh_guide = function(player)
  local index = player.index
  local job = R().jobs[index]
  local hover = R().hover[index]
  if hover and (hover.expires <= game.tick or not (job and job.counts[hover.key])) then
    R().hover[index] = nil
    hover = nil
  end
  local pinned = R().pinned[index]
  if pinned and not (job and job.counts[pinned]) then
    R().pinned[index] = nil
    pinned = nil
  end
  if hover then draw_guide(player, hover.key, hover.expires - game.tick)
  elseif pinned then draw_guide(player, pinned, nil)
  else clear_guide(index) end
end

---------------------------------------------------------------------------------------------------
-- Bar
---------------------------------------------------------------------------------------------------

local function column_count(player)
  local width = player.display_resolution.width / player.display_scale
  local left_used = 0
  for _, child in pairs(player.gui.top.children) do
    if child.name ~= ROOT then
      local inner = child.name == "mod_gui_top_frame" and child.mod_gui_inner_frame
      local buttons = inner and #inner.children or 1
      left_used = left_used + buttons * SLOT_SIZE + 16
    end
  end
  local columns = math.floor((width - left_used - RIGHT_RESERVE - EDGE_PADDING) / SLOT_SIZE)
  return math.max(2, math.min(columns, 60))
end

local function proto_of(entry)
  if entry.is_tile then return prototypes.tile[entry.name] end
  return entry.is_item and prototypes.item[entry.name] or prototypes.entity[entry.name]
end

local function sort_key(entry, id)
  local lead = entry.hunted and "0|" or "1|"  -- hunted types first
  local proto = proto_of(entry)
  if not proto then return lead .. id end
  local group = proto.group and proto.group.order or ""
  local subgroup = proto.subgroup and proto.subgroup.order or ""
  return lead .. group .. "|" .. subgroup .. "|" .. (proto.order or "") .. "|" .. id
end

local function item_tip(entry)
  local proto = proto_of(entry)
  local name = proto and proto.localised_name or entry.name
  local head
  if entry.quality ~= "normal" and prototypes.quality[entry.quality] then
    head = {"tmb-reaper.item-tooltip-quality", name, prototypes.quality[entry.quality].localised_name, entry.amount}
  else
    head = {"tmb-reaper.item-tooltip", name, entry.amount}
  end
  local tip = {"", head, "\n", {"tmb-reaper.guide-hint"}, "\n", {"tmb-reaper.hunt-hint"}}
  if entry.hunted then tip = {"", {"tmb-reaper.hunted"}, "\n", tip, "\n", {"tmb-reaper.stop-hint"}} end
  return tip
end

local function destroy_panel(player)
  local root = player.gui.top[ROOT]
  if root and root[PANEL] then root[PANEL].destroy() end
  if root and #root.children == 0 then root.destroy() end
end

draw_panel = function(player)
  local job = R().jobs[player.index]
  if not job or job.remaining <= 0 then return destroy_panel(player) end

  local entries, keys = {}, {}
  for id, entry in pairs(job.counts) do
    entries[#entries + 1] = {id = id, entry = entry}
    keys[id] = sort_key(entry, id)
  end
  table.sort(entries, function(a, b) return keys[a.id] < keys[b.id] end)

  local collapsed = R().collapsed[player.index] and true or false
  local columns = math.max(1, math.min(#entries, ROW_LENGTH, column_count(player)))
  local header_tip = {"", {"tmb-reaper.title"}, ": ", job.remaining, "\n", {"tmb-reaper.fold-hint"},
    "\n", {"tmb-reaper.clear-hint"}}
  local pinned = R().pinned[player.index]

  -- same types in the same layout: update in place, so a scrolled bar keeps its position
  local parts = {collapsed and "C" or "c", columns}
  for _, e in ipairs(entries) do parts[#parts + 1] = e.id .. (e.entry.hunted and "*" or "") end
  local sig = table.concat(parts, "|")
  local root = player.gui.top[ROOT]
  local existing = root and root[PANEL]
  if existing and existing.valid and existing.tags.sig == sig then
    local header = existing.children[1] and existing.children[1].children[1]
    if header then header.tooltip = header_tip end
    local inner = existing.tmb_inner
    local grid = inner and (inner.tmb_grid or (inner.tmb_scroll and inner.tmb_scroll.tmb_grid))
    if grid then
      for i, button in ipairs(grid.children) do
        local e = entries[i]
        if e then
          if button.number ~= e.entry.amount then button.number = e.entry.amount end
          button.tooltip = item_tip(e.entry)
          pcall(function() button.toggled = (pinned == e.id) end)
        end
      end
    end
    return
  end

  if existing then existing.destroy() end
  if not root then root = player.gui.top.add{type = "flow", name = ROOT, direction = "vertical"} end
  local index = 1
  for _, name in pairs(ABOVE) do if root[name] then index = math.max(index, root[name].get_index_in_parent() + 1) end end
  local frame = root.add{type = "frame", name = PANEL, direction = "horizontal", style = "slot_window_frame",
    index = math.min(index, #root.children + 1), tags = {sig = sig}}
  frame.add{type = "frame", style = "mod_gui_inside_deep_frame"}.add{
    type = "sprite-button", sprite = "item/" .. TOOL, style = "slot_button", tooltip = header_tip,
    tags = {tmb_reaper_toggle = true}, mouse_button_filter = {"left", "right"},
  }
  if collapsed then return end

  local inner = frame.add{type = "frame", name = "tmb_inner", style = "mod_gui_inside_deep_frame"}
  local parent = inner
  if math.ceil(#entries / columns) > MAX_ROWS then
    local scroll = inner.add{type = "scroll-pane", name = "tmb_scroll", style = "tmb_scroll",
      horizontal_scroll_policy = "never", vertical_scroll_policy = "always"}
    scroll.style.maximal_height = MAX_ROWS * SLOT_SIZE
    parent = scroll
  end
  local grid = parent.add{type = "table", name = "tmb_grid", column_count = columns, style = "filter_slot_table"}
  for _, e in ipairs(entries) do
    local sprite = e.entry.sprite
    if not helpers.is_valid_sprite_path(sprite) then sprite = "utility/questionmark" end
    local button = grid.add{type = "sprite-button", sprite = sprite, number = e.entry.amount, style = "slot_button",
      tooltip = item_tip(e.entry), tags = {tmb_reaper_key = e.id}, mouse_button_filter = {"left", "right"},
      raise_hover_events = true}
    if pinned == e.id then pcall(function() button.toggled = true end) end
    if e.entry.hunted then
      pcall(function()
        local sp = button.add{type = "sprite", sprite = "tmb-hunt", ignored_by_interaction = true}
        sp.style.size = 14
        sp.style.stretch_image_to_widget_size = true
      end)
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

events.on_init(init_storage)
events.on_configuration_changed(function()
  init_storage()
  for player_index in pairs(R().jobs) do R().dirty[player_index] = true end
end)

local function selected(event, grow)
  if event.item ~= TOOL then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  init_storage()
  local cancelled = R().cancel_tick[player.index]
  if cancelled and event.tick - cancelled <= CANCEL_GRACE then return end  -- the alt-click that cleared
  reap(player, event.surface, event.area, grow)
end
events.on_event(defines.events.on_player_selected_area, function(event) selected(event, false) end)
events.on_event(defines.events.on_player_alt_selected_area, function(event) selected(event, true) end)

-- Alt-click with Reaper in hand clears the bar.
events.on_event("tmb-reaper-clear", function(event)
  local player = game.get_player(event.player_index)
  local cursor = player and player.cursor_stack
  if not (cursor and cursor.valid_for_read and cursor.name == TOOL) then return end
  init_storage()
  R().cancel_tick[player.index] = event.tick
  if end_job(player.index) then
    player.create_local_flying_text{text = {"tmb-reaper.cleared"}, create_at_cursor = true}
  end
end)

events.on_event(defines.events.on_object_destroyed, function(event)
  local r = storage.reaper
  local w = r and r.watchers[event.registration_number]
  if not w then return end
  r.watchers[event.registration_number] = nil
  for player_index in pairs(w) do drop(player_index, event.registration_number) end
end)

-- A cancelled mark drops off the bar (the thing stays, it just isn't being removed any more).
events.on_event(defines.events.on_cancelled_deconstruction, function(event)
  local r = storage.reaper
  if not (r and next(r.watchers)) then return end
  local e = event.entity
  if not (e and e.valid) then return end
  local reg = script.register_on_object_destroyed(e)
  local w = r.watchers[reg]
  if not w then return end
  r.watchers[reg] = nil
  for player_index in pairs(w) do drop(player_index, reg) end
end)

events.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  local tags = element and element.valid and element.tags
  if not (tags and (tags.tmb_reaper_toggle or tags.tmb_reaper_key)) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  init_storage()
  if tags.tmb_reaper_toggle then
    R().collapsed[player.index] = not R().collapsed[player.index] or nil
    R().hover[player.index] = nil
    draw_panel(player)
    refresh_guide(player)
    return
  end
  local key = tags.tmb_reaper_key
  if event.button == defines.mouse_button_type.right then
    if event.shift then stop_hunt(player, key) else hunt(player, key) end
    return
  end
  R().pinned[player.index] = (R().pinned[player.index] ~= key) and key or nil
  R().hover[player.index] = nil
  draw_panel(player)
  refresh_guide(player)
end)

events.on_event(defines.events.on_gui_hover, function(event)
  local element = event.element
  local key = element and element.valid and element.tags and element.tags.tmb_reaper_key
  if not key then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  R().hover[player.index] = {key = key, expires = event.tick + HOVER_TTL}
  refresh_guide(player)
end)

events.on_event(defines.events.on_gui_leave, function(event)
  local element = event.element
  if not (element and element.valid and element.tags and element.tags.tmb_reaper_key) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  R().hover[player.index] = nil
  refresh_guide(player)
end)

local function redraw(event)
  local r = storage.reaper
  if r and r.jobs[event.player_index] then mark_dirty(event.player_index) end
end
events.on_event(defines.events.on_player_display_resolution_changed, redraw)
events.on_event(defines.events.on_player_display_scale_changed, redraw)

local function reaim(event)
  local r = storage.reaper
  local player = r and game.get_player(event.player_index)
  if player and r.jobs[player.index] then
    r.hover[player.index] = nil
    refresh_guide(player)
  end
end
events.on_event(defines.events.on_player_changed_surface, reaim)
events.on_event(defines.events.on_player_controller_changed, reaim)

events.on_event(defines.events.on_player_removed, function(event)
  local r = storage.reaper
  if not r then return end
  local i = event.player_index
  end_job(i)
  for _, k in pairs({"dirty", "collapsed", "hover", "pinned", "cancel_tick"}) do r[k][i] = nil end
end)

-- Batched bar redraws.
events.on_nth_tick(6, function()
  local r = storage.reaper
  if not (r and next(r.dirty)) then return end
  local dirty = r.dirty
  r.dirty = {}
  for player_index in pairs(dirty) do
    local player = game.get_player(player_index)
    if player and player.valid then
      draw_panel(player)
      if r.hover[player_index] or r.pinned[player_index] then refresh_guide(player) end
    end
  end
end)

-- A pinned guide re-aims once a second as you move around.
events.on_nth_tick(60, function()
  local r = storage.reaper
  if not r then return end
  for player_index in pairs(r.pinned) do
    local player = game.get_player(player_index)
    if player and player.valid and not r.hover[player_index] then refresh_guide(player) end
  end
end)

return {describe = describe, init_storage = init_storage}
