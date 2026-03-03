-- ia_pathfinding/ladder.lua
--
-- Requirements: ia_pathfinding/ladder.lua
--   Access Point Calculation: Provide 'entry' and 'exit' vectors.
--     The entry is the horizontal landing in front of the ladder base/current level.
--     The exit is the horizontal landing at the target height to clear the ladder's collision.
--   Atomic Execution (Bridge):
--     Once a ladder task is top-of-stack, ladder.lua takes control via _bridge_step.
--     Phase 1 (Mount): Move horizontally to the ladder's base entry point.
--     Phase 2 (Climb): Vertical movement until target Y is reached.
--     Phase 3 (Dismount): Move horizontally to the exit point to clear the ladder.
--   Completion Signal: Return true only when the mob has successfully stepped onto the exit landing.
--   Obstacle Verification: provide helper to verify if a ladder is reachable and helps bridge a vertical gap.

-- ia_pathfinding/ladder.lua

local function log_trace(msg)
    minetest.log('info', '[ia_pathfinding][TRACE] ' .. msg)
end

--- Helper: Returns the horizontal offset required to stand in front of the ladder.
function ia_pathfinding.get_ladder_access_points(ladder_pos, target_y)
    -- ia_dunce.get_ladder_vectors returns the direction the ladder "faces" (the wall normal).
    local dir = ia_dunce.get_ladder_vectors(ladder_pos)

    -- Entry: The floor-level position in front of the ladder at the mob's current height.
    local entry = vector.add(ladder_pos, dir)

    -- Exit: The floor-level position in front of the ladder at the target height.
    local exit = vector.new(entry)
    exit.y = math.floor(target_y + 0.5)

    return {
        entry = entry,
        exit = exit
    }
end

--- Atomic Execution: Handles the physics-defying transition of climbing.
function ia_pathfinding.use_ladder_bridge(self, ladder_pos)
    local my_pos = self.object:get_pos()
    if not my_pos then return false end

    -- 1. Determine Goal Height
    -- Peek at the task below the ladder task (the goal) to see our desired Y.
    local goal_task = self._task_stack[#self._task_stack - 1]
    local target_y = goal_task and goal_task.pos.y or ladder_pos.y

    local points = ia_pathfinding.get_ladder_access_points(ladder_pos, target_y)

    -- 2. Initialize Bridge State
    if not self._bridge_step then
        self._bridge_step = "MOUNT"
        log_trace("Bridge START: Ladder at " .. minetest.pos_to_string(ladder_pos) .. " targeting Y=" .. target_y)
    end

    -- 3. Execute Steps
    if self._bridge_step == "MOUNT" then
        -- Step 1: Get to the base of the ladder
        -- Use horizontal distance check to avoid Y-diff jitter during approach
        local dist_h = vector.distance({x=my_pos.x, y=0, z=my_pos.z}, {x=points.entry.x, y=0, z=points.entry.z})

        if dist_h < 0.3 then
            self._bridge_step = "CLIMB"
            log_trace("Ladder MOUNTED. Beginning vertical phase.")
        else
            ia_dunce.walk(self, points.entry)
        end
        return false

    elseif self._bridge_step == "CLIMB" then
        -- Step 2: Move vertically
        -- We call walk(points.entry) to keep X/Z locked so we don't slip off the ladder
        ia_dunce.walk(self, points.entry)

        local is_up = target_y > my_pos.y
        local finished = false

        if is_up then
            ia_dunce.climb_up(self, target_y)
            finished = ia_dunce.is_at_climb_up_target(self, target_y)
        else
            ia_dunce.climb_down(self, target_y)
            finished = ia_dunce.is_at_climb_down_target(self, target_y)
        end

        if finished then
            self._bridge_step = "DISMOUNT"
            log_trace("Target height reached. DISMOUNTING...")
        end
        return false

    elseif self._bridge_step == "DISMOUNT" then
        -- Step 3: Step off the ladder onto solid ground
        -- We use ia_dunce.walk which will now benefit from any ledge clearing velocity
        ia_dunce.walk(self, points.exit)

        local dist_total = vector.distance(my_pos, points.exit)
        if dist_total < 0.4 then
            ia_dunce.stop(self)
            self._bridge_step = nil
            log_trace("Bridge COMPLETE: Ladder dismounted.")
            return true
        end
        return false
    end

    return false
end
