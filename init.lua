-- ia_pathfinding/init.lua

-- ia_pathfinding: A lightweight, modular port of working_villages logic.
ia_pathfinding = {}

-- Define the file loading order
-- We load utilities and core libraries first.
local files = {
    "movement",
    "pathfinding",
    "registration",
}

-- Load each module
local path = minetest.get_modpath("ia_pathfinding")
for _, file in ipairs(files) do
    local script = path .. "/" .. file .. ".lua"
    local chunk, err = loadfile(script)
    assert(chunk)
    chunk()
end

----- Constructor for a new Dunce instance.
---- Wraps an ia_fakelib object with our village-worker logic.
---- @param self_obj The base entity object (from ia_fakelib)
--function ia_pathfinding.init_instance(self_obj)
--    -- This allows us to call ia_pathfinding methods directly on the entity
--    -- without overwriting the base ia_fakelib methods.
--    for name, func in pairs(ia_pathfinding) do
--        if name ~= "init_instance" then
--            self_obj[name] = func
--        end
--    end
--    
--    minetest.log("action", "[ia_pathfinding] Initialized worker logic for: " .. (self_obj:get_player_name() or "unknown"))
--end
function ia_pathfinding.init_instance(self_obj)
	minetest.log('ia_pathfinding.init_instance()')
    -- Inject methods
    for name, func in pairs(ia_pathfinding) do
        if name ~= "init_instance" and name ~= "register_dunce_entity" and name ~= "register_pathfinding_entity" then
            self_obj[name] = func
        end
    end
    
    -- Safe logging with a fallback
    local name = "Unknown"
    if self_obj.get_player_name then
        name = self_obj:get_player_name()
    elseif self_obj.fake_player and self_obj.fake_player.get_player_name then
        name = self_obj.fake_player:get_player_name()
    end

    self_obj._last_pos = vector.new(0,0,0)
    self_obj._stagnant_ticks = 0

    minetest.log("action", "[ia_pathfinding] Worker logic attached to: " .. name)
end

minetest.log("action", "[ia_pathfinding] API Loaded Successfully.")

