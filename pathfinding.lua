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
        climb = false,
    }
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

function ia_pathfinding.push_task(self, pos, task_type, metadata)
    self._task_stack = self._task_stack or {}
    
    -- Check if the top of the stack is already this exact task
    local top = ia_pathfinding.get_current_task(self)
    if top and top.type == task_type and vector.equals(vector.round(top.pos), vector.round(pos)) then
        return -- Already doing this!
    end

    table.insert(self._task_stack, {
        pos = vector.new(pos),
        type = task_type or "move",
        meta = metadata or {}
    })
end

--- Helper: Returns the current top task.
function ia_pathfinding.get_current_task(self)
    if not self._task_stack or #self._task_stack == 0 then return nil end
    return self._task_stack[#self._task_stack]
end

--- Helper: Pops the top task from the stack.
function ia_pathfinding.pop_task(self)
    if self._task_stack and #self._task_stack > 0 then
        return table.remove(self._task_stack)
    end
    return nil
end

-- Update clear_pathing_state to include the stack
function ia_pathfinding.clear_pathing_state(self)
    self._current_path = nil
    self._path_index = 1
    self._path_target = nil
    self._target_object = nil
    self._target_data = nil
    self._task_stack = {} -- Initialize as empty table
end

--function ia_pathfinding.on_reach_destination(self)
--    local completed_task = ia_pathfinding.pop_task(self)
--
--    -- Stop physical movement immediately
--    ia_dunce.stop(self)
--
--    if not completed_task then
--        ia_pathfinding.clear_pathing_state(self)
--        return
--    end
--
--    -- Handle specific interaction for the task type
--    if completed_task.type == "door" then
--        minetest.log('action', '[ia_pathfinding] Interacting with door at waypoint')
--        ia_dunce.handle_door_front(self, "open")
--    elseif completed_task.type == "goal" then
--        -- This was the final destination (the item we wanted)
--        if self._target_data then
--            ia_pathfinding.perform_arrival_action(self, self._target_data)
--        end
--        -- Final goal reached, full cleanup
--        ia_pathfinding.clear_pathing_state(self)
--        return
--    end
--
--    -- RESUME: If there are tasks left (like the original goal), find a new path
--    local next_task = ia_pathfinding.get_current_task(self)
--    if next_task then
--        -- We just opened a door or climbed a ladder; now re-calculate to the next goal
--        ia_pathfinding.find_path_to(self, next_task.pos, next_task.type)
--    else
--        ia_pathfinding.clear_pathing_state(self)
--    end
--end
--
--function ia_pathfinding.find_path_to(self, target_pos, task_type)
--    assert(self.object, "find_path_to: self.object is nil")
--    local my_pos = self.object:get_pos()
--    if not my_pos or not target_pos then return end
--
--    self._task_stack = self._task_stack or {}
--    if #self._task_stack == 0 then
--        ia_pathfinding.push_task(self, target_pos, task_type or "goal")
--    end
--
--    local current_task = ia_pathfinding.get_current_task(self)
--    local start = vector.round(my_pos)
--    local dest = vector.round(current_task.pos)
--
--    -- 1. If targeting a door, try to path to the AIR next to it instead of the block itself
--    local search_dest = dest
--    if current_task.type == "door" then
--        -- Find a walkable neighbor to the door so A* doesn't fail
--        local neighbors = {
--            {x=dest.x+1, y=dest.y, z=dest.z}, {x=dest.x-1, y=dest.y, z=dest.z},
--            {x=dest.x, y=dest.y, z=dest.z+1}, {x=dest.x, y=dest.y, z=dest.z-1}
--        }
--        for _, n in ipairs(neighbors) do
--            local node = minetest.get_node(n)
--            local def = minetest.registered_nodes[node.name]
--            if def and not def.walkable then
--                search_dest = n
--                break
--            end
--        end
--    end
--
--    -- 2. Proximity Check
--    local dist = vector.distance(my_pos, current_task.pos)
--    if dist < 1.2 then
--        ia_pathfinding.on_reach_destination(self)
--        return
--    end
--
--    -- 3. Pathfinding
--    local settings = ia_pathfinding.get_search_settings(self)
--    local flat_result = star.find_path(start, search_dest, settings)
--
--    -- 4. Detour Logic
--    if (not flat_result or #flat_result == 0) and current_task.type ~= "door" then
--        local doors = ia_dunce.find_nearby_doors(start, 8)
--        if doors and #doors > 0 then
--            local door_pos = doors[1].pos
--            ia_pathfinding.push_task(self, door_pos, "door")
--            return ia_pathfinding.find_path_to(self, door_pos, "door")
--        end
--    end
--
--    -- 5. Fallback for Doors: If we can't path to a door but we're close, just walk blindly
--    if (not flat_result or #flat_result == 0) and current_task.type == "door" and dist < 5 then
--        minetest.log('action', "[ia_pathfinding] A* failed for door, using blind approach")
--        self._current_path = {vector.round(current_task.pos)}
--        self._path_index = 1
--        return
--    end
--
--    local formatted_path = format_star_path(flat_result)
--    if formatted_path and #formatted_path > 0 then
--        self._current_path = formatted_path
--        self._path_index = 1
--        self._path_target = vector.new(dest)
--    else
--        ia_pathfinding.clear_pathing_state(self)
--    end
--end
-- mods/ia_pathfinding/pathfinding.lua

function ia_pathfinding.on_reach_destination(self)
    local completed_task = ia_pathfinding.pop_task(self)

    -- Stop physical movement immediately
    ia_dunce.stop(self)

    if not completed_task then
        ia_pathfinding.clear_pathing_state(self)
        return
    end

    -- Handle specific interaction for the task type
    if completed_task.type == "door" then
        minetest.log('action', '[ia_pathfinding] Interacting with door at waypoint')
        ia_dunce.handle_door_front(self, "open")
    elseif completed_task.type == "ladder" then
        -- NEW: Determine if we need to go UP or DOWN based on the next task
        local next_task = ia_pathfinding.get_current_task(self)
        local target_y = next_task and next_task.pos.y or nil
        minetest.log('action', '[ia_pathfinding] Interacting with ladder, target_y: ' .. (target_y or "nil"))
        ia_dunce.climb(self, target_y)
    elseif completed_task.type == "goal" then
        if self._target_data then
            ia_pathfinding.perform_arrival_action(self, self._target_data)
        end
        ia_pathfinding.clear_pathing_state(self)
        return
    end

    -- RESUME: Re-calculate path for the next task on the stack
    local next_task = ia_pathfinding.get_current_task(self)
    if next_task then
        ia_pathfinding.find_path_to(self, next_task.pos, next_task.type)
    else
        ia_pathfinding.clear_pathing_state(self)
    end
end

function ia_pathfinding.find_path_to(self, target_pos, task_type)
    assert(self.object, "find_path_to: self.object is nil")
    local my_pos = self.object:get_pos()
    if not my_pos or not target_pos then return end

    self._task_stack = self._task_stack or {}
    if #self._task_stack == 0 then
        ia_pathfinding.push_task(self, target_pos, task_type or "goal")
    end

    local current_task = ia_pathfinding.get_current_task(self)
    local start = vector.round(my_pos)
    local dest = vector.round(current_task.pos)

    -- 1. Neighbors Check: Path to AIR next to interactive blocks
    local search_dest = dest
    if current_task.type == "door" or current_task.type == "ladder" then
        local neighbors = {
            {x=dest.x+1, y=dest.y, z=dest.z}, {x=dest.x-1, y=dest.y, z=dest.z},
            {x=dest.x, y=dest.y, z=dest.z+1}, {x=dest.x, y=dest.y, z=dest.z-1}
        }
        for _, n in ipairs(neighbors) do
            local node = minetest.get_node(n)
            local def = minetest.registered_nodes[node.name]
            if def and not def.walkable then
                search_dest = n
                break
            end
        end
    end

    -- 2. Proximity Check
    local dist = vector.distance(my_pos, current_task.pos)
    if dist < 1.2 then
        ia_pathfinding.on_reach_destination(self)
        return
    end

    -- 3. Pathfinding
    local settings = ia_pathfinding.get_search_settings(self)
    local flat_result = star.find_path(start, search_dest, settings)

    -- 4. Detour Logic (Refined)
    -- Only look for detours if we are currently pursuing the main GOAL
    if (not flat_result or #flat_result == 0) and current_task.type == "goal" then
        -- Check Doors
        local doors = ia_dunce.find_nearby_doors(start, 8)
        if doors and #doors > 0 then
            local door_pos = doors[1].pos
            ia_pathfinding.push_task(self, door_pos, "door")
            return ia_pathfinding.find_path_to(self, door_pos, "door")
        end

        -- Check Ladders
        local ladders = ia_dunce.find_nearby_ladders(start, 8, 4)
        if ladders and #ladders > 0 then
            local ladder_pos = ladders[1]
            ia_pathfinding.push_task(self, ladder_pos, "ladder")
            return ia_pathfinding.find_path_to(self, ladder_pos, "ladder")
        end
    end

    -- 5. Fallback for interactive tasks (Blind approach)
    if (not flat_result or #flat_result == 0) and 
       (current_task.type == "door" or current_task.type == "ladder") and dist < 5 then
        minetest.log('action', "[ia_pathfinding] A* failed for " .. current_task.type .. ", using blind approach")
        self._current_path = {vector.round(current_task.pos)}
        self._path_index = 1
        return
    end

    -- 6. Path Construction
    local formatted_path = format_star_path(flat_result)
    if formatted_path and #formatted_path > 0 then
        self._current_path = formatted_path
        self._path_index = 1
        self._path_target = vector.new(dest)
    else
        ia_pathfinding.clear_pathing_state(self)
    end
end
