-- Casper: Ghost Tracking, built into TMB (same as casper-ghost-tracking 0.8.0, with tmb- names).
-- data.lua skips this file when the standalone Casper mod is installed.

local GHOST_GREEN = {0.2, 1, 0.2}
local RITUAL_CYAN = {0.15, 0.9, 0.9}

-- Belt/pipe outline pieces, cut from the game's own copy-paste bracket art (the 1x1-size copy corner).
-- Referenced from __core__, so nothing is copied into this mod.
data:extend({
  {
    type = "sprite",
    name = "tmb-casper-outline-corner",
    filename = "__core__/graphics/cursor-boxes.png",
    priority = "extra-high-no-scale",
    flags = {"no-crop"},
    x = 128, y = 192, width = 20, height = 20,
    scale = 0.5
  },
  {
    type = "sprite",
    name = "tmb-casper-outline-dash",
    filename = "__core__/graphics/cursor-boxes.png",
    priority = "extra-high-no-scale",
    flags = {"no-crop"},
    x = 141, y = 192, width = 7, height = 9,
    scale = 0.5
  }
})

data:extend({
  -- The Casper tool itself: a cursor-only selection tool, like the copy or deconstruction planners.
  {
    type = "selection-tool",
    name = "tmb-casper-tool",
    icon = "__too-many-buildables__/graphics/casper/casper-tool.png",
    icon_size = 64,
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
    auto_recycle = false,
    hidden = true,
    subgroup = "tool",
    order = "c[automated-construction]-z[tmb-casper]",
    stack_size = 1,
    send_pre_selection_events = true,  -- live preview of what a drag will track (2.1.22+)
    select =
    {
      border_color = GHOST_GREEN,
      cursor_box_type = "copy",
      -- "entity-ghost" makes the game draw the green brackets on ghosts live while dragging.
      mode = {"entity-ghost"},
      started_sound = {filename = "__core__/sound/blueprint-select.ogg"},
      ended_sound = {filename = "__core__/sound/blueprint-create.ogg"}
    },
    -- Shift-drag: add to the current job.
    alt_select =
    {
      border_color = GHOST_GREEN,
      cursor_box_type = "copy",
      -- "entity-ghost" makes the game draw the green brackets on ghosts live while dragging.
      mode = {"entity-ghost"},
      started_sound = {filename = "__core__/sound/blueprint-select.ogg"},
      ended_sound = {filename = "__core__/sound/blueprint-create.ogg"}
    }
  },

  -- Hotkey that puts the tool in your hand.
  {
    type = "custom-input",
    name = "tmb-casper-give-tool",
    key_sequence = "SHIFT + ALT + G",
    consuming = "game-only",
    item_to_spawn = "tmb-casper-tool",
    action = "spawn-item",
    order = "a"
  },

  -- Alt-click while holding the tool cancels the current job.
  {
    type = "custom-input",
    name = "tmb-casper-cancel-job",
    key_sequence = "ALT + mouse-button-1",
    consuming = "none",
    order = "b"
  },

  -- Shortcut bar button.
  {
    type = "shortcut",
    name = "tmb-casper-give-tool",
    order = "b[blueprints]-z[tmb-casper]",
    action = "spawn-item",
    item_to_spawn = "tmb-casper-tool",
    associated_control_input = "tmb-casper-give-tool",
    style = "green",
    icon = "__too-many-buildables__/graphics/casper/shortcut-x56.png",
    icon_size = 56,
    small_icon = "__too-many-buildables__/graphics/casper/shortcut-x24.png",
    small_icon_size = 24
  }
,

  -- The Exorcist: pick types, then drag to remove their ghosts from the Casper job.
  {
    type = "selection-tool",
    name = "tmb-exorcist",
    icon = "__too-many-buildables__/graphics/casper/exorcist-tool.png",
    icon_size = 64,
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
    auto_recycle = false,
    hidden = true,
    subgroup = "tool",
    order = "c[automated-construction]-z[tmb-casper]-b[exorcist]",
    stack_size = 1,
    -- Click: pick a type. Drag: remove tracked ghosts of the picked types.
    select =
    {
      border_color = {1, 0.25, 0.25},
      cursor_box_type = "not-allowed",
      mode = {"any-entity"},
      started_sound = {filename = "__core__/sound/deconstruct-select-start.ogg"},
      ended_sound = {filename = "__core__/sound/deconstruct-select-end.ogg"}
    },
    -- Shift-click: un-pick a type. Shift-drag: pick every type in the box.
    alt_select =
    {
      border_color = {1, 0.6, 0.2},
      cursor_box_type = "not-allowed",
      mode = {"any-entity"},
      started_sound = {filename = "__core__/sound/deconstruct-select-start.ogg"},
      ended_sound = {filename = "__core__/sound/deconstruct-select-end.ogg"}
    }
  },

  {
    type = "custom-input",
    name = "tmb-casper-give-exorcist",
    key_sequence = "SHIFT + ALT + E",
    consuming = "game-only",
    item_to_spawn = "tmb-exorcist",
    action = "spawn-item",
    order = "c"
  },

  {
    type = "shortcut",
    name = "tmb-casper-give-exorcist",
    order = "b[blueprints]-z[tmb-casper]-b[exorcist]",
    action = "spawn-item",
    item_to_spawn = "tmb-exorcist",
    associated_control_input = "tmb-casper-give-exorcist",
    style = "red",
    icon = "__too-many-buildables__/graphics/casper/exorcist-shortcut-x56.png",
    icon_size = 56,
    small_icon = "__too-many-buildables__/graphics/casper/exorcist-shortcut-x24.png",
    small_icon_size = 24
  },

  -- Ritual: Casper for upgrades. Tracks entities marked for upgrade (and ghosts changed in Casper).
  {
    type = "selection-tool",
    name = "tmb-ritual-tool",
    icon = "__too-many-buildables__/graphics/casper/ritual-tool.png",
    icon_size = 64,
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
    auto_recycle = false,
    hidden = true,
    subgroup = "tool",
    order = "c[automated-construction]-z[tmb-casper]-a[ritual]",
    stack_size = 1,
    send_pre_selection_events = true,  -- live preview of what a drag will track
    select =
    {
      border_color = RITUAL_CYAN,
      cursor_box_type = "electricity",
      mode = {"nothing"},
      started_sound = {filename = "__core__/sound/blueprint-select.ogg"},
      ended_sound = {filename = "__core__/sound/blueprint-create.ogg"}
    },
    -- Shift-drag: add to the current job's area.
    alt_select =
    {
      border_color = RITUAL_CYAN,
      cursor_box_type = "electricity",
      mode = {"nothing"},
      started_sound = {filename = "__core__/sound/blueprint-select.ogg"},
      ended_sound = {filename = "__core__/sound/blueprint-create.ogg"}
    }
  },

  -- Hotkey slot for Ritual, unassigned by default (set it in Controls).
  {
    type = "custom-input",
    name = "tmb-casper-give-ritual",
    key_sequence = "",
    consuming = "game-only",
    item_to_spawn = "tmb-ritual-tool",
    action = "spawn-item",
    order = "a-b"
  },

  {
    type = "shortcut",
    name = "tmb-casper-give-ritual",
    order = "b[blueprints]-z[tmb-casper]-a[ritual]",
    action = "spawn-item",
    item_to_spawn = "tmb-ritual-tool",
    associated_control_input = "tmb-casper-give-ritual",
    style = "blue",
    icon = "__too-many-buildables__/graphics/casper/ritual-shortcut-x56.png",
    icon_size = 56,
    small_icon = "__too-many-buildables__/graphics/casper/ritual-shortcut-x24.png",
    small_icon_size = 24
  },

  -- White outline pieces, tinted cyan at runtime (the game's copy brackets only come in green).
  {
    type = "sprite",
    name = "tmb-ritual-outline-corner",
    filename = "__too-many-buildables__/graphics/casper/ritual-outline-corner.png",
    priority = "extra-high-no-scale",
    flags = {"no-crop"},
    width = 80, height = 80,
    scale = 0.125
  },
  {
    type = "sprite",
    name = "tmb-ritual-outline-dash",
    filename = "__too-many-buildables__/graphics/casper/ritual-outline-dash.png",
    priority = "extra-high-no-scale",
    flags = {"no-crop"},
    width = 28, height = 36,
    scale = 0.125
  },

  -- Auto-track: a toggle; while on, pasted blueprints are tracked by Casper (ghosts) and
  -- Ritual (upgrades). Hotkey slot unassigned by default.
  {
    type = "custom-input",
    name = "tmb-casper-auto-track",
    key_sequence = "",
    consuming = "game-only",
    action = "lua",
    order = "a-c"
  },
  {
    type = "shortcut",
    name = "tmb-casper-auto-track",
    order = "b[blueprints]-z[tmb-casper]-c[auto-track]",
    action = "lua",
    toggleable = true,
    associated_control_input = "tmb-casper-auto-track",
    icon = "__too-many-buildables__/graphics/casper/auto-track-x56.png",
    icon_size = 56,
    small_icon = "__too-many-buildables__/graphics/casper/auto-track-x24.png",
    small_icon_size = 24
  }
})
