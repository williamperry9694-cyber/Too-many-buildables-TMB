data:extend({
  {
    type = "int-setting",
    name = "tmb-rows",
    setting_type = "runtime-per-user",
    default_value = 2,
    allowed_values = {1, 2, 3, 4},
    order = "a"
  },
  {
    type = "string-setting",
    name = "tmb-width",
    setting_type = "runtime-per-user",
    default_value = "auto",
    allowed_values = {"auto", "10", "15", "20", "25", "30"},
    order = "b"
  },
  {
    type = "string-setting",
    name = "tmb-tab-position",
    setting_type = "runtime-per-user",
    default_value = "left",
    allowed_values = {"left", "top", "right"},
    order = "b1"
  },
  {
    type = "string-setting",
    name = "tmb-slot-layout",
    setting_type = "runtime-per-user",
    default_value = "rows",
    allowed_values = {"rows", "compact", "columns", "dense"},
    order = "b2"
  },
  {
    type = "string-setting",
    name = "tmb-sort",
    setting_type = "runtime-per-user",
    default_value = "crafting",
    allowed_values = {"crafting", "type"},
    order = "b3"
  },
  {
    type = "string-setting",
    name = "tmb-mat-sort",
    setting_type = "runtime-per-user",
    default_value = "type",
    allowed_values = {"crafting", "type"},
    order = "f1"
  },
  {
    type = "int-setting",
    name = "tmb-offset-x",
    setting_type = "runtime-per-user",
    default_value = 0,
    minimum_value = -400,
    maximum_value = 400,
    order = "c"
  },
  {
    type = "int-setting",
    name = "tmb-offset-y",
    setting_type = "runtime-per-user",
    default_value = 0,
    minimum_value = -400,
    maximum_value = 400,
    order = "d"
  },
  {
    type = "int-setting",
    name = "tmb-mat-width",
    setting_type = "runtime-per-user",
    default_value = 6,
    minimum_value = 6,
    maximum_value = 9,
    order = "e"
  },
  {
    type = "string-setting",
    name = "tmb-mat-position",
    setting_type = "runtime-per-user",
    default_value = "equipment",
    allowed_values = (mods["GUI_Unifyer"] or mods["GUI_Unifyer_Unified"])
      and {"equipment", "center", "gui-unifier", "free"}
      or {"equipment", "center", "free"},
    order = "f"
  },
  {
    type = "int-setting",
    name = "tmb-mat-offset-x",
    setting_type = "runtime-per-user",
    default_value = 0,
    minimum_value = -400,
    maximum_value = 400,
    order = "g"
  },
  {
    type = "int-setting",
    name = "tmb-mat-offset-y",
    setting_type = "runtime-per-user",
    default_value = 0,
    minimum_value = -400,
    maximum_value = 400,
    order = "h"
  }
})
