-- ia_pathfinding/doors.lua
--
-- Requirements: ia_pathfinding/doors.lua
--   Access Point Calculation: Must provide two static, non-colliding coordinates (front and back) offset by at least 1.2 nodes from the door center
--   Atomic Execution (Bridge)
--     Once a door task is top-of-stack, doors.lua takes total control of movement via _bridge_step.
--     Phase 1 (Open): Interact with door.
--     Phase 2 (Walk): Move precisely to the opposite access point.
--     Phase 3 (Close): Interact to close once the doorway is clear.
--   Completion Signal: Return true only when the mob is physically standing on the exit access point, signaling pathfinding.lua to pop the task.
--   Obstacle Verification: Provide a helper to pathfinding.lua to verify if a specific door node is actually what is currently blocking the path to the goal.

local function log_trace(msg)
    minetest.log('info', '[ia_pathfinding][TRACE] ' .. msg)
end

function ia_pathfinding.get_door_access_points(pos)
    local node = minetest.get_node(pos)
    local p2 = node.param2
    assert(minetest.get_item_group(node.name, "door") > 0, "get_door_access_points: node is not a door: " .. node.name)

    local is_open = string.find(node.name, "_c") ~= nil
    local offset = {x = 0, y = 0, z = 1.2}

    -- Determine orientation axis
    if not is_open then
        if p2 == 0 or p2 == 2 then offset = {x = 0, y = 0, z = 1.2}
        else offset = {x = 1.2, y = 0, z = 0} end
    else
        if p2 == 1 or p2 == 3 then offset = {x = 0, y = 0, z = 1.2}
        else offset = {x = 1.2, y = 0, z = 0} end
    end

    return {
        front = vector.add(pos, offset),
        back = vector.subtract(pos, offset)
    }
end

-- TODO need a helper to use `star` to determine which access point we need to be targeting at each step?


function ia_pathfinding.use_door_bridge(self, door_pos)
    local my_pos = self.object:get_pos()
    if not my_pos then return false end

    local points = ia_pathfinding.get_door_access_points(door_pos)

    -- 1. Initialize Bridge State
    if not self._bridge_step then
        local dist_front = vector.distance(my_pos, points.front)
        local dist_back = vector.distance(my_pos, points.back)
        -- The exit is always the point furthest from where we started the bridge
        self._bridge_exit_target = (dist_front < dist_back) and points.back or points.front
        self._bridge_step = "OPEN"
        log_trace("Bridge START: Target exit " .. minetest.pos_to_string(self._bridge_exit_target))
    end

    -- 2. Execute Steps
    if self._bridge_step == "OPEN" then
        ia_dunce.prepare_door_path(self, door_pos, true)
        self._bridge_step = "WALK"
        return false
    elseif self._bridge_step == "WALK" then
        local arrived = not ia_dunce.walk(self, self._bridge_exit_target)
        if arrived and vector.distance(self.object:get_pos(), self._bridge_exit_target) < 0.6 then
            self._bridge_step = "CLOSE"
        end
        return false
    elseif self._bridge_step == "CLOSE" then
        if ia_dunce.is_doorway_clear(door_pos) then
            ia_dunce.interact_door(self, door_pos, "close")
        end
        -- Clean up
        self._bridge_step = nil
        self._bridge_exit_target = nil
        return true
    end
    return false
end

--function ia_pathfinding.handle_door_detour(self, pos) -- the position of the doo:
--	-- TODO assert there's a door at that pos
--
--    -- Check if we are already standing at an access point for this door
--    local pts = ia_pathfinding.get_door_access_points(pos)
--    local dist_a = vector.distance(pos, pts.front)
--    local dist_b = vector.distance(pos, pts.back)
--
--    -- If we are already at an access point and A* still failed,
--    -- it means the door is the obstacle. Push it to the stack.
--    log_trace("Detour: Pushing door task for " .. minetest.pos_to_string(target_door.pos))
--    ia_pathfinding.push_task(self, target_door.pos, "door") -- pushing tasks from doors.lua is prohibited
--    return true
--end
