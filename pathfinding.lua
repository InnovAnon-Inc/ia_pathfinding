-- ia_pathfinding/pathfinding.lua
-- NOTE must handle optionally digging, climbing, swimming, flying, etc
--
-- Requirements: ia_pathfinding/pathfinding.lua
--   Task Stack Ownership: Must maintain a stack where the bottom is the goal and higher entries are the "Bridges" (doors/ladders) needed to reach it.
--   Recursive Validation:
--     Attempt star from current_pos to top_task.
--     If star fails, scan for nearby interactables (doors).
--     Test if star can reach the interactable.
--     If yes, push the interactable to the stack as a new top_task.
--   Canonical Start/End:
--     A* searches must always use vector.round(access_point) as the source/destination for doors to ensure star doesn't evaluate inside a collision box.
--   State Clean-up: Must pop the task and clear _current_path only when the specific "Bridge" logic (in doors.lua) signals completion.
--   Stalemate Prevention: If the stack is empty or star fails with no detectable obstacles, trigger a short direct-walk fallback to resolve rounding jitter.

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

--- Arrival Logic
function ia_pathfinding.on_reach_destination(self)
    local completed_task = ia_pathfinding.pop_task(self)
    ia_dunce.stop(self)

    if not completed_task or completed_task.type == "goal" then
        log_trace("Final goal reached.")
        ia_pathfinding.clear_pathing_state(self)
    end

    -- Invalidate path so the next task in the stack (if any) generates a new one
    self._current_path = nil
end

-- ia_pathfinding/pathfinding.lua

-- mods/ia_pathfinding/pathfinding.lua

function ia_pathfinding.process_pathfinding(self)
    -- 0. Basic Sanity
    if not self.object or not self.object:get_pos() then
        ia_pathfinding.clear_pathing_state(self)
        return
    end

    -- 1. GOAL VALIDATION (Priority)
    -- If the apple/target is gone, we MUST break out of bridges and paths immediately.
    -- Assuming self._target_object is how you track the apple entity.
    local target_lost = self._target_object and not self._target_object:get_pos()
    
    if target_lost then
        log_trace("Target lost mid-process. Clearing all state.")
        ia_pathfinding.clear_pathing_state(self)
        self._bridge_step = nil -- Force break the bridge latch
        self._bridge_exit_target = nil
        ia_dunce.stop(self)
        return
    end

    local current_task = ia_pathfinding.get_current_task(self)
    if not current_task then return end

    local my_pos = self.object:get_pos()
    local dist_to_task = vector.distance(my_pos, current_task.pos)
    local is_bridge = (current_task.type == "door" or current_task.type == "ladder")

    -- 2. BRIDGE DELEGATION
    if self._bridge_step or (is_bridge and dist_to_task < 1.4) then
        if self._current_path then
            log_trace("Hand-off: Entering atomic bridge mode for " .. current_task.type)
            self._current_path = nil 
            ia_dunce.stop(self)
        end

        local bridge_finished = false
        if current_task.type == "door" then
            bridge_finished = ia_pathfinding.use_door_bridge(self, current_task.pos)
        elseif current_task.type == "ladder" then
            bridge_finished = ia_pathfinding.use_ladder_bridge(self, current_task.pos)
        end

        if bridge_finished then
            log_trace("Bridge sequence complete: " .. current_task.type)
            ia_pathfinding.pop_task(self)
            self._bridge_step = nil
            self._current_path = nil
        end
        return 
    end

    -- 3. STANDARD MOVEMENT EXECUTION
    if self._current_path then
        local target = self._current_path[self._path_index]
        ia_dunce.walk(self, target)

        if vector.distance(my_pos, target) < 0.5 then
            self._path_index = self._path_index + 1
            if self._path_index > #self._current_path then
                ia_pathfinding.on_reach_destination(self)
            end
        end
    else
        -- 4. PATH SEARCHING
        ia_pathfinding.find_path_to(self, current_task.pos, current_task.type)
    end
end

--- RECURSIVE VALIDATION: Find a bridge (door) that star can reach.
-- This fulfills the requirement to piece together the path via obstacles.
local function find_reachable_bridge(self, my_pos, goal_pos)
    local doors = ia_dunce.find_nearby_doors(my_pos, 5)
    if not doors or #doors == 0 then return nil end

    local settings = ia_pathfinding.get_search_settings(self)
    local start_node = vector.round(my_pos)

    for _, d in ipairs(doors) do
        local pts = ia_pathfinding.get_door_access_points(d.pos)
        -- Canonical Start/End: Always round the access point for star
        local target_node = vector.round(pts.front)
        if vector.distance(my_pos, pts.front) > vector.distance(my_pos, pts.back) then
            target_node = vector.round(pts.back)
        end

        -- Can star reach this door's access point?
        local test_path = star.find_path(start_node, target_node, settings)
        if test_path and #test_path > 0 then
            -- Verify this door actually gets us closer to the goal than we are now
            if vector.distance(d.pos, goal_pos) < vector.distance(my_pos, goal_pos) then
                log_trace("Bridge Found: Star can reach door at " .. minetest.pos_to_string(d.pos))
                return d.pos
            end
        end
    end
    return nil
end

function ia_pathfinding.find_path_to(self, target_pos, task_type)
    local my_pos = self.object:get_pos()
    if not my_pos then return end

    -- Task Stack Ownership: Ensure we always have a goal
    if not self._task_stack or #self._task_stack == 0 then
        ia_pathfinding.push_task(self, target_pos, task_type or "goal")
    end

    local current_task = ia_pathfinding.get_current_task(self)
    local start = vector.round(my_pos)
    local search_dest = vector.round(current_task.pos)

    -- Canonical Start/End: If we are near a door, snap start to the access point node
    local nearby_doors = ia_dunce.find_nearby_doors(my_pos, 2)
    if nearby_doors and #nearby_doors > 0 then
        local pts = ia_pathfinding.get_door_access_points(nearby_doors[1].pos)
        if vector.distance(my_pos, pts.front) < 0.8 then
            start = vector.round(pts.front)
        elseif vector.distance(my_pos, pts.back) < 0.8 then
            start = vector.round(pts.back)
        end
    end

    -- If the current top task is a door, search_dest is its closest access point node
    if current_task.type == "door" then
        local pts = ia_pathfinding.get_door_access_points(current_task.pos)
        search_dest = vector.round(vector.distance(my_pos, pts.front) < vector.distance(my_pos, pts.back)
                      and pts.front or pts.back)
    end

    -- Execute Star Search
    local settings = ia_pathfinding.get_search_settings(self)
    local flat_result = star.find_path(start, search_dest, settings)

    -- Recursive Validation Logic
    if (not flat_result or #flat_result == 0) then
        if current_task.type == "goal" or current_task.type == "move" then
            -- Star failed to goal; find a bridge we CAN reach.
            local bridge_pos = find_reachable_bridge(self, my_pos, current_task.pos)
            if bridge_pos then
                ia_pathfinding.push_task(self, bridge_pos, "door")
                return -- Next frame will process the new top task (the door)
            end
        end

        -- Stalemate Prevention: Jitter resolution
        if vector.distance(my_pos, search_dest) < 1.1 then
            log_trace("Stalemate: Forcing direct walk to " .. minetest.pos_to_string(search_dest))
            ia_dunce.walk(self, search_dest)
            return
        end
    end

    -- Apply Path if found
    local formatted = format_star_path(flat_result)
    if formatted then
        self._current_path = formatted
        self._path_index = 1
    end
end
