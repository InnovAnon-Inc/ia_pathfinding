-- ia_pathfinding/init.lua

ia_pathfinding = {}

local files = {
    "doors",
    "ladder",
    "movement",
    "pathfinding",
    "registration",
    "scavenge",
    --"task",
}

local path = minetest.get_modpath("ia_pathfinding")

for _, file in ipairs(files) do
    local script = path .. "/" .. file .. ".lua"
    -- UPDATED: Capture 'err' to show the exact syntax error in the console
    local chunk, err = loadfile(script)
    
    if not chunk then
        error("\n[ia_pathfinding] Syntax error in " .. file .. ".lua: " .. tostring(err))
    end
    
    chunk()
end

function ia_pathfinding.init_instance(self_obj)
    -- Inject all functions into the entity
    for name, func in pairs(ia_pathfinding) do
        if name ~= "init_instance" and
           name ~= "register_pathfinding_entity" and
           type(func) == "function" then
            self_obj[name] = func
        end
    end

    -- Initial state
    self_obj._current_path = nil
    self_obj._path_index = 1
    self_obj._scan_timer = 0
end
