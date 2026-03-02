-- ia_pathfinding/ladder.lua

--- Checks if the goal is vertically offset and pushes a ladder detour if pathing fails.
-- @param self The entity instance
-- @param pos The current position
-- @return boolean True if a detour was pushed
function ia_pathfinding.handle_ladder_detour(self, pos)
    -- Find ladders within 8 nodes horizontally and 4 nodes vertically
    local ladders = ia_dunce.find_nearby_ladders(pos, 8, 4)
    if ladders and #ladders > 0 then
        -- We pick the first (closest due to get_sorted_nodes usually)
        local ladder_pos = ladders[1]
        minetest.log('info', "[ia_pathfinding] Ladder detour detected at " .. minetest.pos_to_string(ladder_pos))
        ia_pathfinding.push_task(self, ladder_pos, "ladder")
        return true
    end
    return false
end

--- Handles the transition from arriving at a ladder to actually climbing it.
-- @param self The entity instance
function ia_pathfinding.traverse_ladder(self)
    local next_task = ia_pathfinding.get_current_task(self)
    
    -- If there's no task after the ladder, we don't know where we're going.
    -- We assume the original 'goal' is still on the stack below the 'ladder' task.
    local target_y = next_task and next_task.pos.y or nil
    
    minetest.log('info', "[ia_pathfinding] Arrived at ladder. Initiating climb to Y: " .. (target_y or "unknown"))
    
    -- 1. Execute the Dunce atomic climb
    ia_dunce.climb(self, target_y)
    
    -- 2. Once climb is initiated, we push a traverse task to the target altitude
    -- This ensures the mob doesn't try to re-path *while* on the ladder.
    if next_task then
        local exit_point = {x = next_task.pos.x, y = target_y, z = next_task.pos.z}
        ia_pathfinding.push_task(self, exit_point, "traverse")
    end
end
