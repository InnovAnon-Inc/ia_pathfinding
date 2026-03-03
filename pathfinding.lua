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

-- ia_pathfinding/pathfinding.lua

local function log_trace(msg)
    minetest.log('info', '[ia_pathfinding][TRACE] ' .. msg)
end

--- RECURSIVE VALIDATION: Find a bridge (door/ladder) that star can reach.
local function find_reachable_bridge(self, my_pos, goal_pos)
    local settings = ia_pathfinding.get_search_settings(self)
    local start_node = vector.round(my_pos)

    -- 1. Doors
    local doors = ia_dunce.find_nearby_doors(my_pos, 5)
    for _, d in ipairs(doors or {}) do
        local pts = ia_pathfinding.get_door_access_points(d.pos)
        local target_node = vector.round(vector.distance(my_pos, pts.front) < vector.distance(my_pos, pts.back) and pts.front or pts.back)

        if star.find_path(start_node, target_node, settings) then
            if vector.distance(d.pos, goal_pos) < vector.distance(my_pos, goal_pos) then
                return d.pos, "door"
            end
        end
    end

    -- 2. Ladders
    local ladders = ia_dunce.find_nearby_ladders(my_pos, 8, 4)
    for _, l_pos in ipairs(ladders or {}) do
        local pts = ia_pathfinding.get_ladder_access_points(l_pos, my_pos.y)
        local target_node = vector.round(pts.entry)

        -- Don't re-push a ladder if we are already standing exactly at its entry/exit
        -- and the path failed; it means this ladder isn't the solution to this specific A* failure.
        if vector.distance(my_pos, pts.entry) > 0.6 then
            if star.find_path(start_node, target_node, settings) then
                local y_diff = goal_pos.y - my_pos.y
                if math.abs(y_diff) > 1.2 then
                    -- Check if ladder extends in the direction we need to go
                    local check_pos = vector.add(l_pos, {x=0, y=(y_diff > 0 and 1 or -1), z=0})
                    if ia_dunce.is_climbable(check_pos) then
                        return l_pos, "ladder"
                    end
                end
            end
        end
    end

    return nil
end

function ia_pathfinding.process_pathfinding(self)
    if not self.object or not self.object:get_pos() then
        ia_pathfinding.clear_pathing_state(self)
        return
    end

    local current_task = ia_pathfinding.get_current_task(self)
    if not current_task then return end

    local my_pos = self.object:get_pos()
    local dist_to_task = vector.distance(my_pos, current_task.pos)
    local is_bridge = (current_task.type == "door" or current_task.type == "ladder")

    -- 1. BRIDGE DELEGATION
    if self._bridge_step or (is_bridge and dist_to_task < 1.5) then
        if self._current_path then
            self._current_path = nil
        end

        local bridge_finished = false
        if current_task.type == "door" then
            bridge_finished = ia_pathfinding.use_door_bridge(self, current_task.pos)
        elseif current_task.type == "ladder" then
            bridge_finished = ia_pathfinding.use_ladder_bridge(self, current_task.pos)
        end

        if bridge_finished then
            ia_pathfinding.pop_task(self)
            self._bridge_step = nil
            self._current_path = nil
            ia_dunce.stop(self)
        end
        return
    end

    -- 2. STANDARD MOVEMENT
    if self._current_path and self._path_index <= #self._current_path then
        local target = self._current_path[self._path_index]
        if target then
            ia_dunce.walk(self, target)
            if vector.distance(my_pos, target) < 0.5 then
                self._path_index = self._path_index + 1
                if self._path_index > #self._current_path then
                    ia_pathfinding.on_reach_destination(self)
                end
            end
        else
            self._current_path = nil
        end
    else
        ia_pathfinding.find_path_to(self, current_task.pos, current_task.type)
    end
end

function ia_pathfinding.find_path_to(self, target_pos, task_type)
    local my_pos = self.object:get_pos()
    if not my_pos then return end

    if not self._task_stack or #self._task_stack == 0 then
        ia_pathfinding.push_task(self, target_pos, task_type or "goal")
    end

    local current_task = ia_pathfinding.get_current_task(self)
    local start = vector.round(my_pos)
    local search_dest = vector.round(current_task.pos)

    -- Canonical Snapping
    if current_task.type == "door" then
        local pts = ia_pathfinding.get_door_access_points(current_task.pos)
        search_dest = vector.round(vector.distance(my_pos, pts.front) < vector.distance(my_pos, pts.back) and pts.front or pts.back)
    elseif current_task.type == "ladder" then
        local pts = ia_pathfinding.get_ladder_access_points(current_task.pos, my_pos.y)
        search_dest = vector.round(pts.entry)
    end

    local settings = ia_pathfinding.get_search_settings(self)
    local flat_result = star.find_path(start, search_dest, settings)

    if (not flat_result or #flat_result == 0) then
        -- If we can't reach the current target, look for a bridge to help
        if current_task.type == "goal" or current_task.type == "move" then
            local bridge_pos, bridge_type = find_reachable_bridge(self, my_pos, current_task.pos)
            if bridge_pos then
                ia_pathfinding.push_task(self, bridge_pos, bridge_type)
                return
            end
        end

        -- Stalemate Fallback: If close to search_dest but A* fails, force-walk
        if vector.distance(my_pos, search_dest) < 1.2 then
            ia_dunce.walk(self, search_dest)
            return
        end
    end

    local formatted = ia_pathfinding.format_star_path(flat_result)
    if formatted then
        self._current_path = formatted
        self._path_index = 1
    end
end
