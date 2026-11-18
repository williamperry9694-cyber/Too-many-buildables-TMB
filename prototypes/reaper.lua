-- Reaper: a finder for things already marked for deconstruction. It never marks or cancels anything.
local PURPLE = {0.7, 0.35, 1}

data:extend({
  {
    type = "selection-tool",
    name = "tmb-reaper",
    icon = "__too-many-buildables__/graphics/reaper/reaper-tool.png",
    icon_size = 64,
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
    auto_recycle = false,
    hidden = true,
    subgroup = "tool",
    order = "c[automated-construction]-z[tmb-casper]-d[reaper]",
    stack_size = 1,
    -- Drag: count what's marked for deconstruction in the box (radar range only).
    select = {
      border_color = PURPLE,
      cursor_box_type = "not-allowed",
      mode = {"cancel-deconstruct", "any-entity"},  -- the game brackets what is marked while you drag
      started_sound = {filename = "__core__/sound/deconstruct-select-start.ogg"},
      ended_sound = {filename = "__core__/sound/deconstruct-select-end.ogg"}
    },
    -- Shift-drag: add another box.
    alt_select = {
      border_color = PURPLE,
      cursor_box_type = "not-allowed",
      mode = {"cancel-deconstruct", "any-entity"},  -- the game brackets what is marked while you drag
      started_sound = {filename = "__core__/sound/deconstruct-select-start.ogg"},
      ended_sound = {filename = "__core__/sound/deconstruct-select-end.ogg"}
    }
  },

  -- Hotkey slot, unassigned by default (set it in Controls).
  {
    type = "custom-input",
    name = "tmb-reaper-give",
    key_sequence = "",
    consuming = "game-only",
    item_to_spawn = "tmb-reaper",
    action = "spawn-item",
    order = "d"
  },

  -- Alt-click while holding Reaper clears its bar.
  {
    type = "custom-input",
    name = "tmb-reaper-clear",
    key_sequence = "ALT + mouse-button-1",
    consuming = "none",
    order = "d-b"
  },

  {
    type = "shortcut",
    name = "tmb-reaper-give",
    order = "b[blueprints]-z[tmb-casper]-d[reaper]",
    action = "spawn-item",
    item_to_spawn = "tmb-reaper",
    associated_control_input = "tmb-reaper-give",
    -- There is no purple shortcut style, so the button's purple face is a floating layer drawn
    -- under the glyph, scaled to cover the whole (grey) button.
    icons = {
      {icon = "__too-many-buildables__/graphics/reaper/reaper-shortcut-bg.png", icon_size = 152,
       scale = 0.146, floating = true},
      {icon = "__too-many-buildables__/graphics/reaper/reaper-shortcut-x56.png", icon_size = 56},
    },
    small_icon = "__too-many-buildables__/graphics/reaper/reaper-shortcut-x24.png",
    small_icon_size = 24
  },

  -- Yellow crosshair on hunted types.
  {type = "sprite", name = "tmb-hunt", filename = "__too-many-buildables__/graphics/hunt.png",
   size = 32, scale = 0.5, flags = {"gui-icon"}}
})
