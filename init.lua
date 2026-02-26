-- ia_pathfinding/init.lua

-- ia_pathfinding: A lightweight, modular port of working_villages logic.
ia_pathfinding = {}

-- Define the file loading order
-- We load utilities and core libraries first.
local files = {
    "movement",
    "pathfinding",
    "registration",
    "scavenge",
}

-- Load each module
local path = minetest.get_modpath("ia_pathfinding")
for _, file in ipairs(files) do
    local script = path .. "/" .. file .. ".lua"
    local chunk, err = loadfile(script)
    assert(chunk)
    chunk()
end

function ia_pathfinding.init_instance(self_obj)
    minetest.log('action', '[ia_pathfinding] Initializing instance for entity')

    -- Inject all functions from ia_pathfinding into the entity
    for name, func in pairs(ia_pathfinding) do
        -- Skip the registration and init functions themselves
        if name ~= "init_instance" and
           name ~= "register_pathfinding_entity" and
           type(func) == "function" then

            self_obj[name] = func
        end
    end

    -- Initialize pathfinding-specific state
    self_obj._current_path = nil
    self_obj._path_index = 1
    self_obj._scan_timer = 0
end
