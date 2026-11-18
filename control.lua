-- Too Many Buildables (TMB)
-- A collapsible panel over the quickbar showing every buildable in your inventory,
-- sorted into the crafting menu's categories.
-- This file wires up the events; the parts live in scripts/ (util, crafting, howmany, buildables,
-- materials, and the built-in Casper).
local events = require("scripts.events")
local U = require("scripts.util")
local shared = require("scripts.shared")
local CHECK_TICKS, cur_quality, find_side, mark_dirty, pdata, quality_enabled = U.CHECK_TICKS, U.cur_quality, U.find_side, U.mark_dirty, U.pdata, U.quality_enabled
local quality_list = U.quality_list
local C = require("scripts.crafting")
local craft, find_recipe, grab_ghost, per_craft, pick = C.craft, C.find_recipe, C.grab_ghost, C.per_craft, C.pick
local H = require("scripts.howmany")
local howmany_close, howmany_confirm, howmany_open, howmany_sync_from_sliders, howmany_sync_from_total = H.howmany_close, H.howmany_confirm, H.howmany_open, H.howmany_sync_from_sliders, H.howmany_sync_from_total
local B = require("scripts.buildables")
local build_frame, game_hides_quickbar, get_width, refresh, reposition, toggle = B.build_frame, B.game_hides_quickbar, B.get_width, B.refresh, B.reposition, B.toggle
local update_visibility = B.update_visibility
local M = require("scripts.materials")
local CUSTOM, add_custom, all_material_names, mat_build, mat_click, mat_defaults = M.CUSTOM, M.add_custom, M.all_material_names, M.mat_build, M.mat_click, M.mat_defaults
local mat_place = M.mat_place
local mat_mode, mat_refresh, mat_set_open, mat_toggle_place, track_build, track_place = M.mat_mode, M.mat_refresh, M.mat_set_open, M.mat_toggle_place, M.track_build, M.track_place
local track_sync_grid, gp_tick, gp_keep = M.track_sync_grid, M.gp_tick, M.gp_keep

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function init_player(player)
  local d = pdata(player)
  build_frame(player)
  if d.mat_open then
    mat_build(player)
    track_build(player)
  end
  mat_toggle_place(player)
end

local function init_all()
  storage.players = storage.players or {}
  -- 0.5.1: drop the old "track what you carry" preset once; tracking is now only what you pick
  for _, d in pairs(storage.players) do
    if not d.tracked_v2 then
      d.tracked = {}
      d.tracked_v2 = true
    end
  end
  storage.unlocked = nil
  storage.dirty = storage.dirty or {}
  for _, player in pairs(game.players) do init_player(player) end
end

events.on_init(init_all)
events.on_configuration_changed(init_all)

events.on_event(defines.events.on_player_created, function(e) init_player(game.get_player(e.player_index)) end)
events.on_event(defines.events.on_player_joined_game, function(e) init_player(game.get_player(e.player_index)) end)
events.on_event(defines.events.on_player_removed, function(e)
  if storage.players then storage.players[e.player_index] = nil end
  if storage.dirty then storage.dirty[e.player_index] = nil end
end)

events.on_event({
  defines.events.on_player_display_resolution_changed,
  defines.events.on_player_display_scale_changed
}, function(e)
  local player = game.get_player(e.player_index)
  reposition(player)
  if pdata(player).mat_open then mat_build(player); track_build(player) end
  mat_toggle_place(player)
end)

-- Remote View adds a border; move the bar, its tab and the Materials panel inside it (and back).
events.on_event(defines.events.on_player_controller_changed, function(e)
  local player = game.get_player(e.player_index)
  if not (player and player.valid) then return end
  local was_remote = e.old_type == defines.controllers.remote
  local is_remote = player.controller_type == defines.controllers.remote
  if was_remote == is_remote then return end
  reposition(player)
  if pdata(player).mat_open then mat_place(player) else mat_toggle_place(player) end
end)

events.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
  if not e.player_index or not e.setting:find("^tmb%-") then return end
  local player = game.get_player(e.player_index)
  build_frame(player)
  local d = pdata(player)
  if d.open then refresh(player, true) end
  if d.mat_open then mat_set_open(player, true) else mat_toggle_place(player) end
end)

-- Inventory or hand changed: refresh at most once per tick.
events.on_event({
  defines.events.on_player_main_inventory_changed,
  defines.events.on_player_cursor_stack_changed
}, function(e) mark_dirty(e.player_index) end)

-- Pipette over a TMB slot: the item if you have it, otherwise its ghost (like left-click).
local function slot_item(player, el, sel)
  local tags = el.tags or {}
  local d = pdata(player)
  if tags.tmb_item then return tags.tmb_item, cur_quality(d) end
  if tags.tmb_mat then return tags.tmb_mat, cur_quality(d, "mat_quality") end
  if tags.tmb_track_item then return tags.tmb_track_item, "normal" end
  if tags.tmb_casper_key and shared.casper_slot_item then
    return shared.casper_slot_item(player, tags.tmb_casper_key, tags.tmb_kind)
  end
  if sel and sel.base_type == "item" then return sel.name, sel.quality end
end

local function do_pipette(player, name, quality)
  local item = prototypes.item[name]
  if not item then return false end
  local ok, done = pcall(player.pipette, item, quality or "normal", true)
  return ok and done
end

events.on_event("tmb-pipette", function(e)
  if not e.in_gui then return end
  local el = e.element
  if not (el and el.valid and el.get_mod() == "too-many-buildables") then return end
  local player = game.get_player(e.player_index)
  if not player then return end
  local name, quality = slot_item(player, el, e.selected_prototype)
  if not name then return end
  if do_pipette(player, name, quality) then
    -- the game's own pipette runs after us and may empty the hand (nothing under the
    -- cursor in the world); if so, put it back next tick
    storage.pipette_retry = storage.pipette_retry or {}
    storage.pipette_retry[player.index] = {name = name, quality = quality, tick = e.tick}
  end
end)

local function pipette_retry(tick)
  local list = storage.pipette_retry
  if not list or next(list) == nil then return end
  for index, r in pairs(list) do
    if tick > r.tick then
      list[index] = nil
      local player = game.get_player(index)
      if player and player.valid then
        local stack = player.cursor_stack
        if not (stack and stack.valid_for_read) and not player.cursor_ghost then
          do_pipette(player, r.name, r.quality)
        end
      end
    end
  end
end

events.on_event(defines.events.on_tick, function(e)
  gp_tick(e.tick)   -- Ghost Project blink and auto-close (does nothing unless one is running)
  pipette_retry(e.tick)
  local dirty = storage.dirty
  if not dirty or next(dirty) == nil then return end
  storage.dirty = {}
  for index in pairs(dirty) do
    local player = game.get_player(index)
    if player and player.connected then
      local d = pdata(player)
      if d.open then refresh(player) end
      if d.mat_open then mat_refresh(player) end
    end
  end
end)

-- Research changes what can be crafted: refresh the force's players.
local function force_changed(force)
  if force then for _, p in pairs(force.players) do mark_dirty(p.index) end end
end
events.on_event(defines.events.on_research_finished, function(e) force_changed(e.research.force) end)
events.on_event(defines.events.on_research_reversed, function(e) force_changed(e.research.force) end)
events.on_event({defines.events.on_force_reset, defines.events.on_technology_effects_reset},
  function(e) force_changed(e.force) end)
events.on_event(defines.events.on_player_changed_force, function(e)
  local p = game.get_player(e.player_index)
  if p then mark_dirty(p.index) end
end)

events.on_event("tmb-toggle", function(e) toggle(game.get_player(e.player_index)) end)
events.on_event("tmb-toggle-materials", function(e)
  local player = game.get_player(e.player_index)
  mat_set_open(player, not pdata(player).mat_open)
end)

-- Is this element part of the Materials panel?
local function in_materials(el)
  while el do
    if el.name == "tmb_mat" then return true end
    el = el.parent
  end
  return false
end

events.on_event(defines.events.on_gui_click, function(e)
  local el = e.element
  if not (el and el.valid) then return end
  local player = game.get_player(e.player_index)
  -- clicking an auto-opened Materials panel keeps it open
  if pdata(player).gp_auto and in_materials(el) then gp_keep(player) end

  if el.name == "tmb_toggle" then return toggle(player) end
  if el.name == "tmb_howmany_close" then return howmany_close(player) end
  if el.name == "tmb_howmany_craft" then return howmany_confirm(player) end
  if e.control and not e.shift and not e.alt and el.tags and (el.tags.tmb_item or el.tags.tmb_mat)
     and e.button == defines.mouse_button_type.left then
    return howmany_open(player, el.tags.tmb_item or el.tags.tmb_mat, nil, e.cursor_display_location)
  end
  if el.name == "tmb_mat_toggle" then return mat_set_open(player, not pdata(player).mat_open) end

  local d = pdata(player)
  if el.name == "tmb_mat_track" then
    d.track_open = not d.track_open
    return track_build(player)
  elseif el.name == "tmb_track_close" then
    d.track_open = false
    return track_build(player)
  elseif el.name == "tmb_mat_lock" then
    local frame = find_side(player, "tmb_mat")
    if frame then d.mat_loc = frame.location end
    d.mat_locked = not d.mat_locked
    return mat_build(player)
  elseif el.name == "tmb_mat_collapse_all" then
    mat_defaults(d)
    local any_open = not d.collapsed[CUSTOM]
    for name in pairs(d.tracked or {}) do
      local p = prototypes.item[name]
      if p and not d.collapsed["g:" .. p.group.name] then any_open = true end
    end
    d.collapsed = {}
    if any_open then
      d.collapsed[CUSTOM] = true
      for name in pairs(d.tracked or {}) do
        local p = prototypes.item[name]
        if p then d.collapsed["g:" .. p.group.name] = true end
      end
    end
    return mat_refresh(player, true)
  end

  local tags = el.tags
  if not tags then return end
  if tags.tmb_mat_quality then
    d.mat_quality = tags.tmb_mat_quality
    return mat_build(player)
  end
  if tags.tmb_quality then
    d.quality = tags.tmb_quality
    build_frame(player)
    if d.open then refresh(player, true) end
    return
  end
  if tags.tmb_strip then
    mat_defaults(d)
    d.collapsed[tags.tmb_strip] = not d.collapsed[tags.tmb_strip] or nil
    return mat_refresh(player, true)
  elseif tags.tmb_mat then
    return mat_click(player, e, tags)
  elseif tags.tmb_track_tab then
    d.track_tab = tags.tmb_track_tab
    return track_build(player)
  elseif tags.tmb_track_item then
    local name = tags.tmb_track_item
    d.tracked = d.tracked or {}
    if e.shift then
      add_custom(player, name)                     -- shift+click: add to Custom bar
    else
      d.tracked[name] = (not d.tracked[name]) or nil
      track_sync_grid(el.parent, d)
    end
    return mat_refresh(player, true)
  end
  if tags.tmb_tab then
    local d = pdata(player)
    d.tab = tags.tmb_tab
    refresh(player, true)
    local bar = player.gui.screen.tmb_bar
    local _, _, grid_scroll = B.panels(bar)
    if grid_scroll then grid_scroll.scroll_to_top() end
  elseif tags.tmb_item then
    local name = tags.tmb_item
    local q = cur_quality(pdata(player))
    local left = e.button == defines.mouse_button_type.left
    local right = e.button == defines.mouse_button_type.right
    if left and e.shift and e.control then
      craft(player, name, nil, q)       -- as many as possible
    elseif left and e.shift then
      craft(player, name, 1, q)
    elseif right and e.shift then
      craft(player, name, 5, q)
    elseif right then
      grab_ghost(player, name, q)
    elseif left then
      pick(player, name, false, q)
    end
  end
end)

-- Ctrl + click: a recipe in the vanilla crafting menu, or an item in your own inventory,
-- opens "How many?". Clicks on TMB's own slots are handled by on_gui_click instead.
-- With a chest/machine open, Ctrl + click on items is the game's "transfer all", so
-- TMB leaves items alone then (recipes still work).
events.on_event("tmb-how-many", function(e)
  if not e.in_gui then return end
  local el = e.element
  if el and el.valid and el.tags and (el.tags.tmb_item or el.tags.tmb_mat) then return end
  if el and el.valid and el.get_mod() == "too-many-buildables" then return end
  local sel = e.selected_prototype
  if not sel then return end
  local player = game.get_player(e.player_index)
  if sel.base_type == "item" then
    if player.opened_gui_type ~= defines.gui_type.controller then return end
    howmany_open(player, sel.name, nil, e.cursor_display_location)
  elseif sel.base_type == "recipe" then
    local r = prototypes.recipe[sel.name]
    local main = r and (r.main_product or (r.products[1]))
    if main and main.type == "item" then
      howmany_open(player, main.name, sel.name, e.cursor_display_location)
    end
  end
end)

-- Hovering an auto-opened Materials panel keeps it open.
events.on_event(defines.events.on_gui_hover, function(e)
  local el = e.element
  if el and el.valid and el.tags and el.tags.tmb_mat_frame then
    local player = game.get_player(e.player_index)
    if pdata(player).gp_auto then gp_keep(player) end
  end
end)

events.on_event(defines.events.on_gui_value_changed, function(e)
  local el = e.element
  if not (el and el.valid) then return end
  if el.name == "tmb_stacks" or el.name == "tmb_singles" then
    local frame = game.get_player(e.player_index).gui.screen.tmb_howmany
    if frame then howmany_sync_from_sliders(frame) end
  end
end)

events.on_event(defines.events.on_gui_text_changed, function(e)
  local el = e.element
  if el and el.valid and el.name == "tmb_total" then
    local frame = game.get_player(e.player_index).gui.screen.tmb_howmany
    if frame then howmany_sync_from_total(frame) end
  end
end)

events.on_event(defines.events.on_gui_confirmed, function(e)
  local el = e.element
  if el and el.valid and el.name == "tmb_total" then howmany_confirm(game.get_player(e.player_index)) end
end)

events.on_event(defines.events.on_gui_closed, function(e)
  local el = e.element
  if el and el.valid and el.name == "tmb_howmany" then el.destroy(); return end
  -- the popup closes together with the inventory / crafting menu
  if e.gui_type == defines.gui_type.controller then
    howmany_close(game.get_player(e.player_index))
  end
end)

events.on_event(defines.events.on_gui_checked_state_changed, function(e)
  local el = e.element
  if not (el and el.valid and el.tags and el.tags.tmb_track_sg) then return end
  local player = game.get_player(e.player_index)
  local d = pdata(player)
  d.tracked = d.tracked or {}
  for _, name in ipairs(all_material_names()) do
    local p = prototypes.item[name]
    if p.subgroup.name == el.tags.tmb_track_sg and p.group.name == el.tags.tmb_track_group then
      d.tracked[name] = el.state or nil
    end
  end
  -- the grid is the element right after this checkbox's strip
  local strip, inner = el.parent, el.parent.parent
  local found = false
  for _, child in pairs(inner.children) do
    if found then track_sync_grid(child, d); break end
    if child == strip then found = true end
  end
  mat_refresh(player, true)
end)

events.on_event(defines.events.on_gui_elem_changed, function(e)
  local el = e.element
  if not (el and el.valid and el.tags and el.tags.tmb_custom_add) then return end
  local player = game.get_player(e.player_index)
  local value = el.elem_value
  if value then
    local name = type(value) == "table" and value.name or value
    add_custom(player, name)
  end
  mat_refresh(player, true)
end)

events.on_event(defines.events.on_gui_location_changed, function(e)
  local el = e.element
  if not (el and el.valid) then return end
  local player = game.get_player(e.player_index)
  if el.name == "tmb_mat" and mat_mode(player) == "free" then
    local d = pdata(player)
    d.mat_loc = el.location
    d.mat_x, d.mat_y = el.location.x, el.location.y
    track_place(player)
    mat_toggle_place(player)
  end
end)

-- Periodic: hidden-by-game check and quickbar width changes.
events.on_nth_tick(CHECK_TICKS, function()
  if not storage.players then return end
  for _, player in pairs(game.connected_players) do
    local d = storage.players[player.index]
    if d then
      local hidden = game_hides_quickbar(player)
      if hidden ~= d.hidden then
        d.hidden = hidden
        update_visibility(player)
      end
      if get_width(player) ~= d.width then
        build_frame(player)
        if d.open then refresh(player, true) end
      end
    end
  end
end)

---------------------------------------------------------------------------------------------------
-- Casper: Ghost Tracking (built in)
---------------------------------------------------------------------------------------------------
-- If the standalone Casper mod is installed, it stays in charge and TMB's copy is left out entirely.
-- If it was just added to a save that used TMB's copy, clear TMB's copy once.
if script.active_mods["casper-ghost-tracking"] then
  events.on_configuration_changed(function()
    if not storage.casper then return end
    rendering.clear("too-many-buildables")
    for _, player in pairs(game.players) do
      local root = player.gui.top.tmb_casper_root
      if root then root.destroy() end
    end
    storage.casper = nil
  end)
else
  local shared = require("scripts.shared")
  shared.find_recipe = find_recipe
  shared.per_craft = per_craft
  shared.quality_list = quality_list
  shared.quality_enabled = quality_enabled
  shared.howmany_open = howmany_open
  require("scripts.casper")
end

-- Reaper (finder for things marked for deconstruction): always on.
require("scripts.reaper")
