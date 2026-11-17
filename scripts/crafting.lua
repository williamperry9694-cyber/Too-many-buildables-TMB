-- Too Many Buildables (TMB): hand-crafting and picking items into the hand.
local U = require("scripts.util")
local recipe_index, say = U.recipe_index, U.say
local shared = require("scripts.shared")

-- A craft came up short: let the built-in Casper's Ghost Project know (if it's loaded).
local function short_of(player, name)
  if shared.note_craft_failure then shared.note_craft_failure(player, name) end
end
---------------------------------------------------------------------------
-- Crafting and picking
---------------------------------------------------------------------------
-- A ghost of the item in your hand (robots build it).
local function grab_ghost(player, name, quality)
  player.clear_cursor()
  pcall(function() player.cursor_ghost = {name = name, quality = quality or "normal"} end)
end

-- Hand-craft `want` (or as many as possible if want == nil).
-- The recipe TMB hand-crafts an item with: the one named like the item first, then the
-- rest; it must be unlocked and hand-craftable. Returns recipe name, or nil + message.
local function find_recipe(player, name, recipe)
  if player.controller_type == defines.controllers.remote or not (player.character and player.character.valid) then
    return nil, {"tmb.craft-remote"}
  end
  local cats = player.character.prototype.crafting_categories or {}
  local recipes = player.force.recipes
  local list
  if recipe then
    list = {recipe}
  else
    list = recipe_index()[name]
    if not list then return nil, {"tmb.craft-no-recipe"} end
  end
  local ordered = {}
  for _, rname in ipairs(list) do
    if rname == name then table.insert(ordered, 1, rname) else ordered[#ordered + 1] = rname end
  end
  local any_enabled = false
  for _, rname in ipairs(ordered) do
    local r = recipes[rname]
    if r and r.enabled then
      any_enabled = true
      for _, cat in pairs(r.prototype.categories) do
        if cats[cat] then return rname end
      end
    end
  end
  if not any_enabled then return nil, {"tmb.craft-locked"} end
  return nil, {"tmb.craft-not-handcraftable"}
end

-- Hand-craft `want` crafts (or as many as possible if want == nil).
local function craft(player, name, want, quality)
  -- hand-crafting only makes normal quality (from normal ingredients)
  if quality and quality ~= "normal" then return say(player, {"tmb.craft-normal-only"}) end
  local chosen, err = find_recipe(player, name)
  if not chosen then return say(player, err) end
  local can = player.get_craftable_count(chosen)
  if can < 1 then
    short_of(player, name)
    return say(player, {"tmb.craft-no-ingredients"})
  end
  local count = want and math.min(want, can) or can
  local started = player.begin_crafting{count = count, recipe = chosen, silent = true}
  if want and started < want then
    short_of(player, name)
    say(player, {"tmb.craft-partial", started, want})
  end
end

-- How many of `name` one craft of `recipe` makes (at least 1).
local function per_craft(recipe, name)
  for _, prod in pairs(prototypes.recipe[recipe].products) do
    if prod.type == "item" and prod.name == name then
      local amount = prod.amount or ((prod.amount_min or 1) + (prod.amount_max or 1)) / 2
      amount = amount * (prod.probability or 1)
      return math.max(1, math.floor(amount))
    end
  end
  return 1
end

-- Hand-craft enough to make `items` of `name` (rounded up to whole crafts).
local function craft_items(player, name, items, recipe)
  local chosen, err = find_recipe(player, name, recipe)
  if not chosen then return say(player, err) end
  local each = per_craft(chosen, name)
  local want = math.ceil(items / each)
  local can = player.get_craftable_count(chosen)
  if can < 1 then
    short_of(player, name)
    return say(player, {"tmb.craft-no-ingredients"})
  end
  local count = math.min(want, can)
  local started = player.begin_crafting{count = count, recipe = chosen, silent = true}
  if started < want then
    short_of(player, name)
    say(player, {"tmb.craft-partial", started * each, want * each})
  end
end

-- Pick an item up into the hand, like the vanilla quickbar.
local function pick(player, name, no_ghost, quality)
  quality = quality or "normal"
  local function none()
    if no_ghost then return say(player, {"tmb.none-carried"}) end
    return grab_ghost(player, name, quality)
  end
  -- remote view: no inventory to take from, give a ghost instead
  if player.controller_type == defines.controllers.remote then return none() end

  local cursor = player.cursor_stack
  if not cursor then return end
  -- clicking what you're already holding puts it back
  if cursor.valid_for_read and cursor.name == name and cursor.quality.name == quality then
    player.clear_cursor()
    return
  end

  local inv = player.get_main_inventory()
  if not inv then return none() end
  if not player.clear_cursor() then
    player.create_local_flying_text{text = {"tmb.cursor-busy"}, create_at_cursor = true}
    return
  end
  local stack, index = inv.find_item_stack({name = name, quality = quality})
  if not stack then return none() end
  if cursor.transfer_stack(stack) and inv.index then
    pcall(function() player.hand_location = {inventory = inv.index, slot = index} end)
  end
end

return {
  grab_ghost = grab_ghost,
  find_recipe = find_recipe,
  craft = craft,
  per_craft = per_craft,
  craft_items = craft_items,
  pick = pick,
}
