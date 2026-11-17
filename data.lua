local styles = data.raw["gui-style"]["default"]

data:extend({
  -- Optional toggle key: unbound by default.
  {
    type = "custom-input",
    name = "tmb-toggle",
    key_sequence = "",
    consuming = "none",
    action = "lua",
    order = "a"
  },
  {type = "sprite", name = "tmb-arrow-down", filename = "__too-many-buildables__/graphics/arrow-down.png",
   size = 32, scale = 0.5, flags = {"gui-icon"}},
  -- "How many?" popup: Ctrl + click on an item or recipe (also in the vanilla menus).
  -- Alt + click is left to the game (Factoriopedia).
  {
    type = "custom-input",
    name = "tmb-how-many",
    key_sequence = "CONTROL + mouse-button-1",
    consuming = "none",
    include_selected_prototype = true,
    action = "lua",
    order = "c"
  },
  -- Pipette (Q by default) over a TMB slot puts that item in your hand, or its ghost.
  -- Linked to the game's own Pipette control, so it follows the player's key binding.
  {
    type = "custom-input",
    name = "tmb-pipette",
    key_sequence = "",
    linked_game_control = "pipette",
    consuming = "none",
    include_selected_prototype = true,
    action = "lua"
  },
  -- Materials panel: optional toggle key, unbound by default
  {
    type = "custom-input",
    name = "tmb-toggle-materials",
    key_sequence = "",
    consuming = "none",
    action = "lua",
    order = "b"
  },
  {type = "sprite", name = "tmb-arrow-right", filename = "__too-many-buildables__/graphics/arrow-right.png",
   size = 32, scale = 0.5, flags = {"gui-icon"}},
  {type = "sprite", name = "tmb-arrow-left", filename = "__too-many-buildables__/graphics/arrow-left.png",
   size = 32, scale = 0.5, flags = {"gui-icon"}},
  {type = "sprite", name = "tmb-list", filename = "__too-many-buildables__/graphics/list.png",
   size = 32, scale = 0.5, flags = {"gui-icon"}},
  {type = "sprite", name = "tmb-lock", filename = "__too-many-buildables__/graphics/lock.png",
   size = 32, scale = 0.5, flags = {"gui-icon"}},
  {type = "sprite", name = "tmb-unlock", filename = "__too-many-buildables__/graphics/unlock.png",
   size = 32, scale = 0.5, flags = {"gui-icon"}},
  -- dark layer drawn over items you have none of
  {type = "sprite", name = "tmb-dim", filename = "__too-many-buildables__/graphics/dim.png",
   size = 32, flags = {"gui-icon"}},
  {type = "sprite", name = "tmb-arrow-up", filename = "__too-many-buildables__/graphics/arrow-up.png",
   size = 32, scale = 0.5, flags = {"gui-icon"}}
})

-- The ▾/▴ tab on top of the quickbar.
styles.tmb_toggle_button = {
  type = "button_style",
  parent = "frame_button",
  width = 48,
  height = 20,
  padding = 0
}

-- Outer frame: the vanilla quickbar frame, sized from Lua.
styles.tmb_bar_frame = {
  type = "frame_style",
  parent = "quick_bar_slot_window_frame",
  minimal_width = 0,
  top_padding = 5,
  bottom_padding = 11,
  left_padding = 4,
  right_padding = 4
}

-- Scroll areas: no scrollbar drawn, mouse wheel still scrolls.
styles.tmb_scroll = {
  type = "scroll_pane_style",
  parent = "naked_scroll_pane",
  padding = 0,
  extra_padding_when_activated = 0
}

-- Category tabs: 28x28 with thin 3px borders so the group icon has room.
local function tab_tex(name)
  return {base = {filename = "__too-many-buildables__/graphics/" .. name .. ".png",
                  position = {0, 0}, corner_size = 3}}
end
styles.tmb_tab_button = {
  type = "button_style",
  parent = "button",
  size = 28,
  padding = 0,
  default_graphical_set = tab_tex("tab"),
  hovered_graphical_set = tab_tex("tab-hover"),
  clicked_graphical_set = tab_tex("tab-selected"),
  selected_graphical_set = tab_tex("tab-selected"),
  selected_hovered_graphical_set = tab_tex("tab-selected"),
  selected_clicked_graphical_set = tab_tex("tab-selected"),
  left_click_sound = {filename = "__core__/sound/gui-square-button.ogg", volume = 0.6}
}

-- Small toggle for the Materials panel, next to the quickbar tab.
styles.tmb_mat_toggle_button = {
  type = "button_style",
  parent = "frame_button",
  width = 28,
  height = 20,
  padding = 0
}

-- Section strip inside the Materials panel / Track menu: a flat, full-width button
-- so the whole strip is clickable (collapses the section).
styles.tmb_strip_button = {
  type = "button_style",
  parent = "button",
  horizontally_stretchable = "on",
  height = 22,
  padding = 0,
  left_padding = 4,
  horizontal_align = "left",
  font = "default-bold",
  default_font_color = {0.9, 0.9, 0.9},
  hovered_font_color = {1, 1, 1},
  clicked_font_color = {1, 1, 1},
  default_graphical_set = {},
  -- centre pixel of the vanilla button graphics only (no border, so no extra padding)
  hovered_graphical_set = {base = {center = {position = {42, 25}, size = {1, 1}}, opacity = 0.35}},
  clicked_graphical_set = {base = {center = {position = {59, 25}, size = {1, 1}}, opacity = 0.5}}
}

styles.tmb_strip_frame = {
  type = "frame_style",
  parent = "subheader_frame",
  height = 24,
  padding = 0,
  left_padding = 2,
  right_padding = 4,
  horizontally_stretchable = "on"
}

-- Side windows (Materials panel, Track menu): vanilla frame with a fixed 4px gap
-- between title bar and body, so TMB can work out their height.
styles.tmb_side_frame = {
  type = "frame_style",
  parent = "frame",
  vertical_flow_style = {type = "vertical_flow_style", vertical_spacing = 4}
}

-- Small tab that shows the Materials panel (left edge / panel spot).
styles.tmb_side_tab = {
  type = "button_style",
  parent = "frame_button",
  size = 28,
  padding = 0
}

-- Upright version of the toolbelt tab, for the left-edge (centred) panel.
styles.tmb_toggle_button_v = {
  type = "button_style",
  parent = "frame_button",
  width = 20,
  height = 48,
  padding = 0
}

-- Quality buttons: same look as the category tabs, 20x20.
styles.tmb_quality_button = {
  type = "button_style",
  parent = "tmb_tab_button",
  size = 20,
  padding = 2
}

-- Casper: Ghost Tracking, built in. Left out when the standalone Casper mod is installed.
if not mods["casper-ghost-tracking"] then
  require("prototypes.casper")
end
