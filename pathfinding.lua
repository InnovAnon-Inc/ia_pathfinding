-- ia_pathfinding/pathfinding.lua
-- NOTE must handle optionally digging, climbing, swimming, flying, etc

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

--- Generates a customized passable table for the current search.
-- This allows the pathfinder to "see" through doors.
local function get_door_aware_passable()
    local custom_passable = {}
    -- Copy the default passable list from star mod
    for id, val in pairs(star.d_passable) do
        custom_passable[id] = val
    end

    -- Force all nodes in the 'door' group to be passable (0)
    for name, def in pairs(minetest.registered_nodes) do
        if minetest.get_item_group(name, "door") > 0 then
            local id = minetest.get_content_id(name)
            custom_passable[id] = 0
        end
    end

    return custom_passable
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
    local my_pos = self.object:get_pos()
    if not my_pos or not target_pos then return end

    -- Rounding coordinates to integers as star uses them for hashes.
    local start = vector.round(my_pos)
    local dest = vector.round(target_pos)

    local settings = ia_pathfinding.get_search_settings(self)

    -- CHANGE: Hot-swap star's passable table.
    -- Since star.lua uses star.d_passable directly and ignores the settings.passable key,
    -- we temporarily swap the global table to allow doors to be treated as passable.
    local original_passable = star.d_passable
    star.d_passable = get_door_aware_passable()

    -- Execute the A* search
    local flat_result = star.find_path(start, dest, settings)

    -- Restore original passable table immediately
    star.d_passable = original_passable

    -- Convert the flat numerical table to a list of vector objects
    local formatted_path = format_star_path(flat_result)

    if formatted_path and #formatted_path > 0 then
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
    -- If the target we are chasing is gone, stop.
    if self._target_object and not ia_dunce.is_valid_object(self._target_object) then
        ia_pathfinding.clear_pathing_state(self)
        ia_dunce.stop(self)
        return
    end

    -- Door Handling: Since the pathfinder now treats doors as air,
    -- we check the node ahead and open it if it's a door.
    if self._current_path then
        local ahead = ia_dunce.get_relative_node_pos(self, 1, 0)
        local node = minetest.get_node(ahead)
        if minetest.get_item_group(node.name, "door") > 0 then
            ia_dunce.handle_door_front(self, "open")
        end
    end
end
