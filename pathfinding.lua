-- ia_pathfinding/pathfinding.lua
-- NOTE must handle optionally digging, climbing, swimming, flying, etc

local function log_trace(msg)
    minetest.log('info', '[ia_pathfinding][TRACE] ' .. msg)
end

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
        climb = false,
    }
end


--- Helper: Returns the current top task.
function ia_pathfinding.get_current_task(self)
    if not self._task_stack or #self._task_stack == 0 then return nil end
    return self._task_stack[#self._task_stack]
end

--- Helper: Pops the top task from the stack.

-- Update clear_pathing_state to include the stack
function ia_pathfinding.clear_pathing_state(self)
    self._current_path = nil
    self._path_index = 1
    self._path_target = nil
    self._target_object = nil
    self._target_data = nil
    self._task_stack = {} -- Initialize as empty table
end

function ia_pathfinding.push_task(self, pos, task_type, metadata)
    self._task_stack = self._task_stack or {}

    local top = ia_pathfinding.get_current_task(self)
    if top and top.type == task_type and vector.equals(vector.round(top.pos), vector.round(pos)) then
        return -- Already doing this!
    end

    log_trace(string.format("PUSH: %s at %s", task_type, minetest.pos_to_string(pos)))
    table.insert(self._task_stack, {
        pos = vector.new(pos),
        type = task_type or "move",
        meta = metadata or {}
    })
end

function ia_pathfinding.pop_task(self)
    if self._task_stack and #self._task_stack > 0 then
        local task = table.remove(self._task_stack)
        log_trace(string.format("POP: %s at %s", task.type, minetest.pos_to_string(task.pos)))
        return task
    end
    return nil
end

local function get_best_access_point(my_pos, target_pos)
    local neighbors = {
        {x=target_pos.x+1, y=target_pos.y, z=target_pos.z},
        {x=target_pos.x-1, y=target_pos.y, z=target_pos.z},
        {x=target_pos.x, y=target_pos.y, z=target_pos.z+1},
        {x=target_pos.x, y=target_pos.y, z=target_pos.z-1}
    }

    local best_node = nil
    local min_dist = math.huge

    for _, n in ipairs(neighbors) do
        local node = minetest.get_node(n)
        local def = minetest.registered_nodes[node.name]
        -- Explicit assertion: Ensure we don't path into a solid block
        if def and not def.walkable then
            local d = vector.distance(my_pos, n)
            if d < min_dist then
                min_dist = d
                best_node = n
            end
        end
    end

    if best_node then
        log_trace("Best access point for " .. minetest.pos_to_string(target_pos) .. " is " .. minetest.pos_to_string(best_node))
    end
    return best_node or target_pos
end

function ia_pathfinding.process_pathfinding(self)
    -- 1. Vitality Check
    if not self.object or self.object:get_pos() == nil then
        ia_pathfinding.clear_pathing_state(self)
        return
    end

    -- 2. Target Check
    if self._target_object and not ia_dunce.is_valid_object(self._target_object) then
        log_trace("Target object lost, clearing state.")
        ia_pathfinding.clear_pathing_state(self)
        ia_dunce.stop(self)
        return
    end

    -- 3. Iteration Logic: If we have a task but no path, trigger a search.
    local current_task = ia_pathfinding.get_current_task(self)
    if current_task and not self._current_path then
        log_trace("Task exists but no path found. Triggering search for: " .. current_task.type)
        ia_pathfinding.find_path_to(self, current_task.pos, current_task.type)
    end
end

function ia_pathfinding.on_reach_destination(self)
    local completed_task = ia_pathfinding.pop_task(self)
    ia_dunce.stop(self)

    if not completed_task then
        ia_pathfinding.clear_pathing_state(self)
        return
    end

    if completed_task.type == "door" then
        ia_pathfinding.traverse_doorway(self)
    elseif completed_task.type == "ladder" then
        -- NEW: Delegate to ladder module
        ia_pathfinding.traverse_ladder(self)
    elseif completed_task.type == "traverse" then
        minetest.log('info', "[ia_pathfinding] Traversal/Bridge complete.")
    elseif completed_task.type == "goal" then
        local my_pos = self.object:get_pos()
        if vector.distance(my_pos, completed_task.pos) < 1.5 then
            if self._target_data then
                ia_pathfinding.perform_arrival_action(self, self._target_data)
            end
        end
        ia_pathfinding.clear_pathing_state(self)
        return
    end

    self._current_path = nil
end

function ia_pathfinding.find_path_to(self, target_pos, task_type)
    assert(self.object, "find_path_to: self.object is nil")
    local my_pos = self.object:get_pos()
    if not my_pos or not target_pos then return end

    -- Stack management
    self._task_stack = self._task_stack or {}
    if #self._task_stack == 0 then
        ia_pathfinding.push_task(self, target_pos, task_type or "goal")
    end

    local current_task = ia_pathfinding.get_current_task(self)
    local start = vector.round(my_pos)
    local dest = vector.round(current_task.pos)

    -- Traverse bypass: Direct movement for bridges
    if current_task.type == "traverse" then
        self._current_path = {dest}
        self._path_index = 1
        self._path_target = vector.new(dest)
        return
    end

    -- Arrival Check
    local dist = vector.distance(my_pos, current_task.pos)
    if dist < 1.2 then
        ia_pathfinding.on_reach_destination(self)
        return
    end

    -- Target selection for A*
    local search_dest = dest
    if current_task.type == "door" or current_task.type == "ladder" then
        search_dest = get_best_access_point(my_pos, dest)
    end

    -- Execute A*
    local settings = ia_pathfinding.get_search_settings(self)
    local flat_result = star.find_path(start, search_dest, settings)

    -- Detour Logic
    if (not flat_result or #flat_result == 0) and current_task.type == "goal" then
        -- Check Doors
        if ia_pathfinding.handle_door_detour(self, start) then return end

        -- Check Ladders
        if ia_pathfinding.handle_ladder_detour(self, start) then return end
    end

    -- Path Assignment
    local formatted_path = format_star_path(flat_result)
    if formatted_path and #formatted_path > 0 then
        self._current_path = formatted_path
        self._path_index = 1
        self._path_target = vector.new(dest)
    elseif (current_task.type == "door" or current_task.type == "ladder") and dist < 5 then
        -- Blind approach for interactive nodes that A* might struggle to center on
        self._current_path = {vector.round(current_task.pos)}
        self._path_index = 1
    else
        ia_pathfinding.clear_pathing_state(self)
    end
end
