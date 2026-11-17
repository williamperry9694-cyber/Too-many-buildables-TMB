-- Shared event registration.
-- The game keeps only one handler per event per mod, so TMB and the built-in Casper
-- both register through here and every handler gets called, in the order added.

local events = {}

local lists = {}      -- [event id or custom input name] = {handlers}
local nth_lists = {}  -- [tick interval] = {handlers}
local init_list, config_list = {}, {}

local function call_all(list)
  return function(e)
    for i = 1, #list do list[i](e) end
  end
end

local function add_one(id, fn)
  local list = lists[id]
  if not list then
    list = {}
    lists[id] = list
    script.on_event(id, call_all(list))
  end
  list[#list + 1] = fn
end

-- Accepts one event id / custom input name, or an array of them (no filters).
function events.on_event(id, fn)
  if type(id) == "table" then
    for _, one in pairs(id) do add_one(one, fn) end
  else
    add_one(id, fn)
  end
end

function events.on_nth_tick(n, fn)
  local list = nth_lists[n]
  if not list then
    list = {}
    nth_lists[n] = list
    script.on_nth_tick(n, call_all(list))
  end
  list[#list + 1] = fn
end

function events.on_init(fn)
  if #init_list == 0 then script.on_init(call_all(init_list)) end
  init_list[#init_list + 1] = fn
end

function events.on_configuration_changed(fn)
  if #config_list == 0 then script.on_configuration_changed(call_all(config_list)) end
  config_list[#config_list + 1] = fn
end

return events
