-- ia_pathfinding/ladder.lua

--- Helper: Finds a valid landing node adjacent to the ladder at a specific height.
-- @param ladder_pos Vector of the ladder column
-- @param target_y The Y level we want to step off at
-- @param face_offset The vector pointing from the ladder to the standing space
local function find_valid_landing(ladder_pos, target_y, face_offset)
    local landing = vector.add({x=ladder_pos.x, y=target_y, z=ladder_pos.z}, face_offset)
    local node = minetest.get_node(landing)
    local def = minetest.registered_nodes[node.name]

    -- If the direct landing is walkable (solid), we are stuck.
    -- We'll add a small check for the node above it (head space).
    local head_pos = vector.add(landing, {x=0, y=1, z=0})
    local head_node = minetest.get_node(head_pos)
    local head_def = minetest.registered_nodes[head_node.name]

    if def and not def.walkable and head_def and not head_def.walkable then
        return landing
    end

    return nil
end

--function ia_pathfinding.get_ladder_points(ladder_pos, target_y)
--    -- Use the atomic Dunce helper to get the standing offset
--    local offset = ia_dunce.get_ladder_vectors(ladder_pos)
--
--    -- Determine intended exit Y (where the goal actually is)
--    local exit_y = math.floor(target_y + 0.5)
--
--    -- Try to find a valid landing at the target height, or +/- 1
--    local landing = find_valid_landing(ladder_pos, exit_y, offset)
--    if not landing then
--        landing = find_valid_landing(ladder_pos, exit_y + 1, offset) or
--                  find_valid_landing(ladder_pos, exit_y - 1, offset)
--    end
--
--    -- If no air is found, we fall back to the offset position at target height
--    local final_exit = landing or vector.add({x=ladder_pos.x, y=exit_y, z=ladder_pos.z}, offset)
--
--    return {
--        entry = vector.add(ladder_pos, offset),
--        exit = final_exit
--    }
--end
-- mods/ia_pathfinding/ladder.lua

function ia_pathfinding.get_ladder_points(ladder_pos, target_y)
    -- ia_dunce.get_ladder_vectors usually returns the direction the ladder is FACING.
    -- We need to stand in FRONT of it.
    local dir = ia_dunce.get_ladder_vectors(ladder_pos)
    
    -- If dir is the wall-normal, the entry point should be ladder_pos + dir
    local entry = vector.add(ladder_pos, dir)
    
    -- LOGGING: Is the entry point inside a wall?
    local node = minetest.get_node(entry)
    minetest.log("action", string.format("[ia_debug] Ladder at %s. Entry: %s (Node: %s)", 
        minetest.pos_to_string(ladder_pos), minetest.pos_to_string(entry), node.name))

    -- Ensure the exit point is also shifted away from the ladder at the target height
    local exit = vector.new(entry)
    exit.y = math.floor(target_y + 0.5)

    return { entry = entry, exit = exit }
end

--- Encapsulated Bridge API: The "High-Level" ladder handler.
-- Blocks pathfinding until the mob has successfully transitioned to the target height.
function ia_pathfinding.use_ladder_bridge(self, ladder_pos)
    local my_pos = self.object:get_pos()
    if not my_pos then return false end

    -- 1. Determine Goal Height
    -- We peek at the task below the ladder task to see where the mob actually wants to go.
    local goal_task = self._task_stack[#self._task_stack - 1]
    local target_y = goal_task and goal_task.pos.y or ladder_pos.y

    local points = ia_pathfinding.get_ladder_points(ladder_pos, target_y)

    -- 2. State Management
    self._bridge_step = self._bridge_step or "MOUNT"

    if self._bridge_step == "MOUNT" then
        -- Move horizontally into the ladder's "climbable" zone
        local arrived = not ia_dunce.walk(self, points.entry)
        if arrived then
            self._bridge_step = "CLIMB"
            minetest.log('action', "[ia_pathfinding] Ladder mounted, beginning climb.")
        end
        return false

    elseif self._bridge_step == "CLIMB" then
        -- Vertical movement via Dunce
        ia_dunce.climb(self, target_y)

        -- Check if we have reached the target altitude (within a small margin)
        if math.abs(my_pos.y - target_y) < 0.5 then
            self._bridge_step = "DISMOUNT"
        end
        return false

    elseif self._bridge_step == "DISMOUNT" then
        -- Move horizontally to the landing/exit point to clear the ladder
        local arrived = not ia_dunce.walk(self, points.exit)
        if arrived then
            -- Sequence Complete
            ia_dunce.stop(self)
            self._bridge_step = nil
            minetest.log('action', "[ia_pathfinding] Ladder dismounted at Y=" .. target_y)
            return true
        end
        return false
    end

    return false
end

--- Scans for ladders to bridge vertical gaps.
function ia_pathfinding.handle_ladder_detour(self, pos)
    -- Dunce-level sensor for ladder nodes
    local ladders = ia_dunce.find_nearby_ladders(pos, 8)
    if ladders and #ladders > 0 then
        minetest.log('info', "[ia_pathfinding] Found ladder detour at " .. minetest.pos_to_string(ladders[1]))
        ia_pathfinding.push_task(self, ladders[1], "ladder")
        return true
    end
    return false
end
