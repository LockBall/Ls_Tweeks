-- Default DB values for the Settings module: interface_alpha, minimap visibility, and open_on_reload.
-- Consumed by addon.apply_defaults() on first load and after a global reset.
local addon_name, addon = ...

local M = {}

M.defaults = {
    minimap = { hide = false },
    open_on_reload = false,
    interface_alpha = 0.5,
}

addon.module_defaults = addon.module_defaults or {}
addon.module_defaults.st = M.defaults

return M
