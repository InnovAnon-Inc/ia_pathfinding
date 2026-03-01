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

--function ia_pathfinding.clear_pathing_state(self)
--    self._current_path = nil
--    self._path_index = 1
--    self._path_target = nil
--    self._target_object = nil
--end
--
------- Requests a path to a position.
----function ia_pathfinding.find_path_to(self, target_pos)
----    -- Assertion: Ensure self.object is valid before attempting pathfinding
----    assert(self.object, "find_path_to called on entity with nil object")
----
----    local my_pos = self.object:get_pos()
----    if not my_pos or not target_pos then return end
----
----    -- Rounding coordinates to integers as star uses them for hashes.
----    local start = vector.round(my_pos)
----    local dest = vector.round(target_pos)
----
----    local settings = ia_pathfinding.get_search_settings(self)
----
----    -- Execute the A* search using default star.d_passable
----    local flat_result = star.find_path(start, dest, settings)
----
----    -- Convert the flat numerical table to a list of vector objects
----    local formatted_path = format_star_path(flat_result)
----
----    if formatted_path and #formatted_path > 0 then
----        -- Update pathing state
----        self._current_path = formatted_path
----        self._path_index = 1
----        self._path_target = vector.new(target_pos)
----    else
----        minetest.log('info', '[ia_pathfinding] No path found from '
----            .. minetest.pos_to_string(start) .. ' to ' .. minetest.pos_to_string(dest))
----        ia_pathfinding.clear_pathing_state(self)
----    end
----end
--function ia_pathfinding.find_path_to(self, target_pos, task_type)
--    assert(self.object, "find_path_to: self.object is nil")
--    local my_pos = self.object:get_pos()
--    if not my_pos or not target_pos then return end
--
--    -- If the stack is empty, this is a new "root" task (e.g., "Get Apple")
--    if not self._task_stack or #self._task_stack == 0 then
--        ia_pathfinding.push_task(self, target_pos, task_type or "goal")
--    end
--
--    local current_goal = ia_pathfinding.get_current_task(self)
--    local start = vector.round(my_pos)
--    local dest = vector.round(current_goal.pos)
--    local settings = ia_pathfinding.get_search_settings(self)
--
--    -- 1. Try A* to the current top of stack
--    local flat_result = star.find_path(start, dest, settings)
--
--    -- 2. If blocked, look for an intermediate (Door, Ladder, etc.)
--    if not flat_result or #flat_result == 0 then
--        local door_pos = ia_dunce.find_nearby_doors(start, 8) -- Radius 8
--        
--        if door_pos and #door_pos > 0 then
--            -- Take the nearest door and push it as a new task
--            local nearest_door = door_pos[1]
--            
--            -- Guard: Don't push the same door if we are already trying to reach it
--            if not vector.equals(nearest_door, dest) then
--                ia_pathfinding.push_task(self, nearest_door, "door")
--                -- Recursively try to path to the door we just pushed
--                return ia_pathfinding.find_path_to(self, nearest_door, "door")
--            end
--        end
--    end
--
--    -- 3. Finalize path if successful
--    local formatted_path = format_star_path(flat_result)
--    if formatted_path and #formatted_path > 0 then
--        self._current_path = formatted_path
--        self._path_index = 1
--    else
--        -- If we still can't find a path even to an intermediate, fail the stack
--        minetest.log('info', "[ia_pathfinding] Pathfinding failed for stack depth: "..#self._task_stack)
--        ia_pathfinding.clear_pathing_state(self)
--    end
--end

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
    elseif completed_task.type == "goal" then
        -- This was the final destination (the item we wanted)
        if self._target_data then
            ia_pathfinding.perform_arrival_action(self, self._target_data)
        end
        -- Final goal reached, full cleanup
        ia_pathfinding.clear_pathing_state(self)
        return
    end

    -- RESUME: If there are tasks left (like the original goal), find a new path
    local next_task = ia_pathfinding.get_current_task(self)
    if next_task then
        -- We just opened a door or climbed a ladder; now re-calculate to the next goal
        ia_pathfinding.find_path_to(self, next_task.pos, next_task.type)
    else
        ia_pathfinding.clear_pathing_state(self)
    end
end

































-- mods/ia_pathfinding/pathfinding.lua

----- Helper: Pushes a new goal onto the task stack.
----function ia_pathfinding.push_task(self, pos, task_type, metadata)
----    -- Ensure the stack exists
----    self._task_stack = self._task_stack or {}
----
----    -- Assertion to catch the crash you saw: pos must be a valid vector
----    assert(pos and pos.x, "[ia_pathfinding] push_task: Invalid position passed")
----
----    table.insert(self._task_stack, {
----        pos = vector.new(pos),
----        type = task_type or "move",
----        meta = metadata or {}
----    })
----
----    minetest.log('info', string.format("[ia_pathfinding] Pushed task: %s at %s (Stack depth: %d)",
----        task_type or "move", minetest.pos_to_string(pos), #self._task_stack))
----end
--function ia_pathfinding.push_task(self, pos, task_type, metadata)
--    self._task_stack = self._task_stack or {}
--    
--    -- Prevent duplicate consecutive tasks to the same spot
--    local top = ia_pathfinding.get_current_task(self)
--    if top and vector.equals(vector.round(top.pos), vector.round(pos)) then
--        return 
--    end
--
--    table.insert(self._task_stack, {
--        pos = vector.new(pos),
--        type = task_type or "move",
--        meta = metadata or {}
--    })
--end
-- mods/ia_pathfinding/pathfinding.lua

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

----- Modified to initialize stack and handle recursive intermediate searches.
--function ia_pathfinding.find_path_to(self, target_pos, task_type)
--    assert(self.object, "find_path_to: self.object is nil")
--    local my_pos = self.object:get_pos()
--    if not my_pos or not target_pos then return end
--
--    -- Initialize stack if this is the first call for a new goal
--    if not self._task_stack or #self._task_stack == 0 then
--        ia_pathfinding.push_task(self, target_pos, task_type or "goal")
--    end
--
--    local current_goal = ia_pathfinding.get_current_task(self)
--    -- Use the top of the stack as the actual destination for A*
--    local start = vector.round(my_pos)
--    local dest = vector.round(current_goal.pos)
--    local settings = ia_pathfinding.get_search_settings(self)
--
--    -- 1. Try A* to the current goal
--    local flat_result = star.find_path(start, dest, settings)
--
--    -- 2. If blocked, look for an intermediate (Door)
--    if not flat_result or #flat_result == 0 then
--        -- Search for doors in a radius of 8
--        local door_nodes = ia_dunce.find_nearby_doors(start, 8)
--
--        if door_nodes and #door_nodes > 0 then
--            -- get_sorted_nodes returns { {pos, distance}, ... }
--            local nearest_door_pos = door_nodes[1].pos
--
--            -- Prevent infinite recursion: don't push the door if it's already the target
--            if not vector.equals(vector.round(nearest_door_pos), dest) then
--                ia_pathfinding.push_task(self, nearest_door_pos, "door")
--                -- Recursively path to the door
--                return ia_pathfinding.find_path_to(self, nearest_door_pos, "door")
--            end
--        end
--    end
--
--    -- 3. Finalize path
--    local formatted_path = format_star_path(flat_result)
--    if formatted_path and #formatted_path > 0 then
--        self._current_path = formatted_path
--        self._path_index = 1
--    else
--        minetest.log('info', "[ia_pathfinding] Total failure. Clearing stack.")
--        ia_pathfinding.clear_pathing_state(self)
--    end
--end
---- mods/ia_pathfinding/pathfinding.lua
--
--function ia_pathfinding.find_path_to(self, target_pos, task_type)
--    assert(self.object, "find_path_to: self.object is nil")
--    local my_pos = self.object:get_pos()
--    if not my_pos or not target_pos then return end
--
--    -- 1. Stack Initialization
--    self._task_stack = self._task_stack or {}
--    if #self._task_stack == 0 then
--        ia_pathfinding.push_task(self, target_pos, task_type or "goal")
--    end
--
--    local current_task = ia_pathfinding.get_current_task(self)
--    local start = vector.round(my_pos)
--    local dest = vector.round(current_task.pos)
--    local settings = ia_pathfinding.get_search_settings(self)
--
--    -- 2. Attempt A* Path
--    local flat_result = star.find_path(start, dest, settings)
--
--    -- 3. INTERMEDIATE LOGIC: If blocked, look for a door
--    if (not flat_result or #flat_result == 0) and current_task.type ~= "door" then
--        minetest.log('info', "[ia_pathfinding] Path blocked to " .. current_task.type .. ". Searching for doors...")
--        
--        -- Search slightly wider (radius 8) for a door that might be the obstacle
--        local doors = ia_dunce.find_nearby_doors(start, 8)
--        
--        if doors and #doors > 0 then
--            local door_pos = doors[1].pos -- get_sorted_nodes returns {pos, distance}
--            
--            -- PUSH the door task and RE-PATH to it
--            ia_pathfinding.push_task(self, door_pos, "door")
--            minetest.log('action', "[ia_pathfinding] Pathing detour: Target door at " .. minetest.pos_to_string(door_pos))
--            
--            -- We call ourselves recursively to find the path to the door
--            return ia_pathfinding.find_path_to(self, door_pos, "door")
--        end
--    end
--
--    -- 4. Finalize
--    local formatted_path = format_star_path(flat_result)
--    if formatted_path and #formatted_path > 0 then
--        self._current_path = formatted_path
--        self._path_index = 1
--        -- IMPORTANT: Set this so follow_path() knows where the legs are going
--        self._path_target = vector.new(dest) 
--    else
--        minetest.log('info', "[ia_pathfinding] Failed to find path to: " .. (current_task.type or "unknown"))
--        -- If we can't even path to the door, clear everything so we don't loop
--        ia_pathfinding.clear_pathing_state(self)
--    end
--end
-- mods/ia_pathfinding/pathfinding.lua

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
--    -- If we are already at the door/goal, don't path, just trigger reach logic
--    if vector.distance(start, dest) < 1 then
--        ia_pathfinding.on_reach_destination(self)
--        return
--    end
--
--    local settings = ia_pathfinding.get_search_settings(self)
--    local flat_result = star.find_path(start, dest, settings)
--
--    -- If blocked and we aren't already targeting a door
--    if (not flat_result or #flat_result == 0) and current_task.type ~= "door" then
--        local doors = ia_dunce.find_nearby_doors(start, 8)
--        if doors and #doors > 0 then
--            local door_pos = doors[1].pos
--            
--            -- Important: Check if this door is actually different from our current goal
--            if not vector.equals(vector.round(door_pos), dest) then
--                minetest.log('action', "[ia_pathfinding] Pathing detour: Target door at " .. minetest.pos_to_string(door_pos))
--                ia_pathfinding.push_task(self, door_pos, "door")
--                -- Recursively find path to the door
--                return ia_pathfinding.find_path_to(self, door_pos, "door")
--            end
--        end
--    end
--
--    local formatted_path = format_star_path(flat_result)
--    if formatted_path and #formatted_path > 0 then
--        self._current_path = formatted_path
--        self._path_index = 1
--        self._path_target = vector.new(dest) 
--    else
--        -- If we fail to path even to a door, we must clear the stack to stop the loop
--        minetest.log('info', "[ia_pathfinding] Hard failure finding path to " .. (current_task.type or "goal"))
--        ia_pathfinding.clear_pathing_state(self)
--    end
--end
-- mods/ia_pathfinding/pathfinding.lua

-- mods/ia_pathfinding/pathfinding.lua

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

    -- 1. If targeting a door, try to path to the AIR next to it instead of the block itself
    local search_dest = dest
    if current_task.type == "door" then
        -- Find a walkable neighbor to the door so A* doesn't fail
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

    -- 4. Detour Logic
    if (not flat_result or #flat_result == 0) and current_task.type ~= "door" then
        local doors = ia_dunce.find_nearby_doors(start, 8)
        if doors and #doors > 0 then
            local door_pos = doors[1].pos
            ia_pathfinding.push_task(self, door_pos, "door")
            return ia_pathfinding.find_path_to(self, door_pos, "door")
        end
    end

    -- 5. Fallback for Doors: If we can't path to a door but we're close, just walk blindly
    if (not flat_result or #flat_result == 0) and current_task.type == "door" and dist < 5 then
        minetest.log('action', "[ia_pathfinding] A* failed for door, using blind approach")
        self._current_path = {vector.round(current_task.pos)}
        self._path_index = 1
        return
    end

    local formatted_path = format_star_path(flat_result)
    if formatted_path and #formatted_path > 0 then
        self._current_path = formatted_path
        self._path_index = 1
        self._path_target = vector.new(dest)
    else
        ia_pathfinding.clear_pathing_state(self)
    end
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
