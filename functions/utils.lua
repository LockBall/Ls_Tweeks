-- Shared utility functions used across all modules: addon.deep_copy_into() and addon.apply_defaults().
-- deep_copy_into() does a full recursive overwrite from a source table into a destination; apply_defaults() fills missing DB keys from a defaults table without overwriting existing values.
local addon_name, addon = ...

-- Use after table.wipe(dest) to restore a DB table from defaults.
function addon.deep_copy_into(src, dest)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = {}
            addon.deep_copy_into(v, dest[k])
        else
            dest[k] = v
        end
    end
end

-- Recursive fill-missing copy: only writes keys that are absent in dest.
-- Use to apply defaults onto an existing DB without overwriting user values.
function addon.apply_defaults(src, dest)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = dest[k] or {}
            addon.apply_defaults(v, dest[k])
        else
            if dest[k] == nil then dest[k] = v end
        end
    end
end
