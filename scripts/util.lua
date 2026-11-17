-- Too Many Buildables (TMB): shared constants and helpers used by every part of the mod.
---------------------------------------------------------------------------
-- Layout (GUI px at 100% UI scale), measured from the vanilla quickbar
---------------------------------------------------------------------------
local SLOT = 40
local GROUP = 5
local GROUP_GAP = 4
local FIXED_W = 62
local FIXED_H = 16
local CENTER_OFFSET = -23.5
local TOGGLE_W = 48
local TOGGLE_H = 20
local TAB = 28          -- category tab size
local TAB_COLS = 2
local SCROLLBAR = 12    -- vanilla vertical scrollbar width
local BLOCK_COL = 10    -- widest column for category layouts (2 blocks of 5)
local CHECK_TICKS = 30
local ALL = "__all__"
local QBTN = 20         -- quality button size

-- Qualities in the game (not hidden), lowest first. Only "normal" without the quality mod.
local quality_list_cache = nil
local function quality_list()
  if quality_list_cache then return quality_list_cache end
  local list = {}
  for _, q in pairs(prototypes.quality) do
    if not q.hidden then list[#list + 1] = q end
  end
  table.sort(list, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.name < b.name
  end)
  quality_list_cache = list
  return list
end
local function quality_enabled() return #quality_list() > 1 end
local function cur_quality(d, key)
  local q = d and d[key or "quality"]
  local p = q and prototypes.quality[q]
  if not p or p.hidden then return "normal" end
  return q
end
-- badge only for non-normal (vanilla shows none for normal)
local function badge(q) if q ~= "normal" then return q end return nil end

---------------------------------------------------------------------------
-- What counts as buildable (decided per item prototype, cached per session;
-- pure function of the prototypes, so identical on every client)
---------------------------------------------------------------------------
local ROBOTS = {["construction-robot"] = true, ["logistic-robot"] = true}
local buildable_cache = {}

local function is_buildable(name)
  local cached = buildable_cache[name]
  if cached ~= nil then return cached end
  local p = prototypes.item[name]
  local ok = false
  if p and not p.parameter then
    if p.type == "rail-planner" then
      ok = true
    elseif p.place_result then
      ok = not ROBOTS[p.place_result.type]
    elseif p.place_as_tile_result then
      ok = true
    elseif p.plant_result then
      ok = true
    elseif p.type == "module" then
      ok = true
    end
  end
  buildable_cache[name] = ok
  return ok
end

-- Item -> recipes that make it, from every normal (non-hidden) recipe.
-- Hidden recipes are skipped, so things like Space Age recycling don't count.
local recipes_for = nil   -- item name -> {recipe names}
local function recipe_index()
  if recipes_for then return recipes_for end
  recipes_for = {}
  for rname, r in pairs(prototypes.recipe) do
    if not r.hidden then
      for _, prod in pairs(r.products) do
        if prod.type == "item" then
          local list = recipes_for[prod.name] or {}
          list[#list + 1] = rname
          recipes_for[prod.name] = list
        end
      end
    end
  end
  return recipes_for
end

-- Every buildable in the game (not hidden), researched or not. Pure prototype data.
local all_buildables = nil
local function all_buildable_names()
  if all_buildables then return all_buildables end
  all_buildables = {}
  for name, p in pairs(prototypes.item) do
    if not p.hidden and is_buildable(name) then all_buildables[#all_buildables + 1] = name end
  end
  return all_buildables
end

-- Container subgroups (chests, logistic chests, warehouses, fluid storage tanks)
-- go to the bottom of their tab. A subgroup counts as containers when most of its
-- buildables place one of these. Wagons are vehicles, so they don't count.
local CONTAINER_TYPES = {
  ["container"] = true, ["logistic-container"] = true, ["linked-container"] = true,
  ["infinity-container"] = true, ["storage-tank"] = true
}
local container_subgroups = nil
local function is_container_subgroup(sg_name)
  if not container_subgroups then
    local total, hits = {}, {}
    for name, p in pairs(prototypes.item) do
      if is_buildable(name) then
        local sg = p.subgroup.name
        total[sg] = (total[sg] or 0) + 1
        if p.place_result and CONTAINER_TYPES[p.place_result.type] then hits[sg] = (hits[sg] or 0) + 1 end
      end
    end
    container_subgroups = {}
    for sg, n in pairs(total) do
      if (hits[sg] or 0) * 2 > n then container_subgroups[sg] = true end
    end
  end
  return container_subgroups[sg_name] == true
end

-- Sort like the crafting menu: group, subgroup, item order -- with container
-- subgroups moved to the end of their group.
local sort_key_cache = {}
local function sort_key(name)
  local k = sort_key_cache[name]
  if k then return k end
  local p = prototypes.item[name]
  local g, sg = p.group, p.subgroup
  k = {g.order, g.name, is_container_subgroup(sg.name) and 1 or 0, sg.order, sg.name, p.order, name}
  sort_key_cache[name] = k
  return k
end

-- Reorder a list that is already in crafting order: items with the same key are pulled
-- together, keys appear in the order they first show up, and inside a key the order is
-- kept. key_of returns false/nil for items that have no key; those stay on their own.
local function group_by(list, key_of)
  local groups, order = {}, {}
  for _, name in ipairs(list) do
    local key = key_of(name) or ("#" .. name)
    if not groups[key] then groups[key] = {}; order[#order + 1] = key end
    local g = groups[key]
    g[#g + 1] = name
  end
  local out = {}
  for _, key in ipairs(order) do
    for _, name in ipairs(groups[key]) do out[#out + 1] = name end
  end
  return out
end

-- Kind of building, read from the internal name. A word from STRONG wins wherever it is
-- (UNDERGROUND-belt, rail-SIGNAL); otherwise the last kind word (fast-transport-BELT,
-- assembling-MACHINE-2, steel-CHEST). Works the same for modded items.
local STRONG, KINDS = {}, {}
for _, w in ipairs({"underground", "splitter", "loader", "signal", "substation", "roboport",
  "combinator", "accumulator", "beacon", "lab", "radar", "turret", "wall", "gate", "silo"}) do STRONG[w] = true end
for _, w in ipairs({"belt", "inserter", "chest", "pole", "pipe", "pump", "tank", "drill", "furnace",
  "machine", "refinery", "plant", "boiler", "engine", "panel", "reactor", "exchanger", "turbine",
  "rail", "lamp", "module", "wagon", "locomotive", "car", "container", "foundry", "tower",
  "platform", "speaker", "switch", "landfill", "concrete", "brick", "tile", "crusher", "recycler",
  "smelter", "assembler", "warehouse", "storehouse", "port", "station", "generator", "heater"}) do KINDS[w] = true end
local building_type_cache = {}
local function building_type(name)
  local t = building_type_cache[name]
  if t ~= nil then return t end
  t = false
  for token in name:gmatch("[^%-]+") do
    if STRONG[token] then t = token; break end
    if KINDS[token] then t = token end
  end
  building_type_cache[name] = t
  return t
end

local function before(a, b)
  local ka, kb = sort_key(a), sort_key(b)
  for i = 1, #ka do
    if ka[i] ~= kb[i] then return ka[i] < kb[i] end
  end
  return false
end

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
local function pdata(player)
  storage.players = storage.players or {}
  local d = storage.players[player.index]
  if not d then
    d = {open = false, tab = ALL, hidden = false, width = nil, list_sig = nil, tracked_v2 = true}
    storage.players[player.index] = d
  end
  return d
end

local function mark_dirty(player_index)
  storage.dirty = storage.dirty or {}
  storage.dirty[player_index] = true
end

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------
local function main_inventory(player)
  local inv = player.get_main_inventory()
  if inv then return inv end
  local ch = player.character
  if ch and ch.valid then return ch.get_main_inventory() end
  return nil
end

---------------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------------
-- The Materials panel and Track menu live either on the free screen layer or,
-- in "below GUI Unifier" mode, in the game's mod window area under the button bar.
local function find_side(player, name)
  local el = player.gui.screen[name]
  if el then return el end
  local left = player.gui.left
  local flow = left and left.mod_gui_frame_flow
  return flow and flow[name] or nil
end

local function destroy_side(player, name)
  local el = player.gui.screen[name]
  if el then el.destroy() end
  local flow = player.gui.left.mod_gui_frame_flow
  if flow and flow[name] then flow[name].destroy() end
end

-- Remote View draws a border round the screen (left, right, bottom) and a title bar.
-- The vanilla bars move inside it; ours follow. 12 GUI units, measured in-game.
-- No Remote View Border removes it, so there's nothing to move for.
local REMOTE_BORDER = 12
local function remote_border(player)
  if player.controller_type == defines.controllers.remote and not script.active_mods["no-remote-view-border"] then
    return math.floor(REMOTE_BORDER * player.display_scale + 0.5)
  end
  return 0
end

local function say(player, msg)
  player.create_local_flying_text{text = msg, create_at_cursor = true}
end

local function group_sprite(group_name)
  local path = "item-group/" .. group_name
  if helpers.is_valid_sprite_path(path) then return path end
  return "utility/grid_view"
end

-- A slot: normal with a count, or greyed (icon with a dark layer) when you have none.
local function add_item_slot(parent, name, count, tags, quality)
  local tip = quality and {type = "item-with-quality", name = name, quality = quality} or {type = "item", name = name}
  if count then
    return parent.add{type = "sprite-button", style = "slot_button", sprite = "item/" .. name, number = count,
      quality = quality and badge(quality) or nil,
      elem_tooltip = tip, tags = tags, mouse_button_filter = {"left", "right"}}
  end
  tags.tmb_zero = true
  local b = parent.add{type = "sprite-button", style = "slot_button",
    elem_tooltip = tip, tags = tags, mouse_button_filter = {"left", "right"}}
  local icon = b.add{type = "sprite", sprite = "item/" .. name, resize_to_sprite = false, ignored_by_interaction = true}
  icon.style.size = 32
  icon.style.stretch_image_to_widget_size = true
  local dim = b.add{type = "sprite", sprite = "tmb-dim", resize_to_sprite = false, ignored_by_interaction = true}
  dim.style.size = 32
  dim.style.left_margin = -32
  dim.style.stretch_image_to_widget_size = true
  if quality and badge(quality) then
    local qb = b.add{type = "sprite", sprite = "quality/" .. quality, resize_to_sprite = false,
      ignored_by_interaction = true}
    qb.style.size = 14
    qb.style.left_margin = -32
    qb.style.top_margin = 18
    qb.style.stretch_image_to_widget_size = true
  end
  return b
end

return {
  SLOT = SLOT,
  GROUP = GROUP,
  GROUP_GAP = GROUP_GAP,
  FIXED_W = FIXED_W,
  FIXED_H = FIXED_H,
  CENTER_OFFSET = CENTER_OFFSET,
  TOGGLE_W = TOGGLE_W,
  TOGGLE_H = TOGGLE_H,
  TAB = TAB,
  TAB_COLS = TAB_COLS,
  SCROLLBAR = SCROLLBAR,
  BLOCK_COL = BLOCK_COL,
  CHECK_TICKS = CHECK_TICKS,
  ALL = ALL,
  QBTN = QBTN,
  quality_list_cache = quality_list_cache,
  quality_list = quality_list,
  quality_enabled = quality_enabled,
  cur_quality = cur_quality,
  badge = badge,
  ROBOTS = ROBOTS,
  buildable_cache = buildable_cache,
  is_buildable = is_buildable,
  recipes_for = recipes_for,
  recipe_index = recipe_index,
  all_buildables = all_buildables,
  all_buildable_names = all_buildable_names,
  CONTAINER_TYPES = CONTAINER_TYPES,
  container_subgroups = container_subgroups,
  is_container_subgroup = is_container_subgroup,
  sort_key_cache = sort_key_cache,
  sort_key = sort_key,
  before = before,
  group_by = group_by,
  building_type = building_type,
  pdata = pdata,
  remote_border = remote_border,
  mark_dirty = mark_dirty,
  main_inventory = main_inventory,
  find_side = find_side,
  destroy_side = destroy_side,
  say = say,
  group_sprite = group_sprite,
  add_item_slot = add_item_slot,
}
