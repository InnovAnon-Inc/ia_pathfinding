-- ia_pathfinding/pathfinding.lua
-- NOTE must handle optionally digging, climbing, swimming, flying, etc

-- mods/ia_pathfinding/pathfinding.lua

--- Helper: Converts star's flat path into a list of vectors for our movement logic.
-- @param flat_path Table from star.lua [x_dest, y_dest, z_dest, ..., x_start, y_start, z_start]
local function format_star_path(flat_path)
    if not flat_path or #flat_path == 0 then return nil end

    local path = {}
    -- star returns coordinates in reverse order (dest to start).
    -- We iterate backwards through the flat array to build a forward path of vectors.
    for i = #flat_path - 2, 1, -3 do
        table.insert(path, {
            x = flat_path[i],
            y = flat_path[i+1],
            z = flat_path[i+2]
        })
    end

    -- Skip the first node if it's the mob's current position to prevent "stuttering".
    if #path > 1 then
        table.remove(path, 1)
    end

    return path
end

function ia_pathfinding.get_search_settings(self)
    -- star.lua uses 'max_iterations' for the iteration limit.
    return {
        max_iterations = 1024,
        --max_jump = 1,
        --max_drop = 3,
        climb = true
    }
end

function ia_pathfinding.clear_pathing_state(self)
    self._current_path = nil
    self._path_index = 1
    self._path_target = nil
    self._target_object = nil
end

--- Requests a path to a position.
function ia_pathfinding.find_path_to(self, target_pos)
    -- Assertion: Ensure self.object is valid before attempting pathfinding
    assert(self.object, "find_path_to called on entity with nil object")

    local my_pos = self.object:get_pos()
    if not my_pos or not target_pos then return end

    -- Rounding coordinates to integers as star uses them for hashes.
    local start = vector.round(my_pos)
    local dest = vector.round(target_pos)

    local settings = ia_pathfinding.get_search_settings(self)

    -- Execute the A* search using default star.d_passable
    local flat_result = star.find_path(start, dest, settings)

    -- Convert the flat numerical table to a list of vector objects
    local formatted_path = format_star_path(flat_result)

    if formatted_path and #formatted_path > 0 then
        -- Update pathing state
        self._current_path = formatted_path
        self._path_index = 1
        self._path_target = vector.new(target_pos)
    else
        minetest.log('info', '[ia_pathfinding] No path found from '
            .. minetest.pos_to_string(start) .. ' to ' .. minetest.pos_to_string(dest))
        ia_pathfinding.clear_pathing_state(self)
    end
end

function ia_pathfinding.process_pathfinding(self)
    -- 1. Vitality Check: Ensure object still exists
    if not self.object or self.object:get_pos() == nil then
        ia_pathfinding.clear_pathing_state(self)
        return
    end

    -- 2. Target Check: If the target we are chasing is gone, stop.
    if self._target_object and not ia_dunce.is_valid_object(self._target_object) then
        ia_pathfinding.clear_pathing_state(self)
        ia_dunce.stop(self)
        return
    end

    -- Movement logic is handled by follow_path() in the on_step.
end
