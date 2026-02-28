-- ia_pathfinding/movement.lua
-- NOTE must handle optionally digging, climbing, swimming, flying, etc

--- Helper: Checks if the entity is on the ground.
function ia_pathfinding.is_entity_on_ground(self)
    local pos = self.object:get_pos()
    if not pos then return false end
    local vel = self.object:get_velocity()
    if math.abs(vel.y) > 0.1 then return false end
    
    local below = {x = pos.x, y = pos.y - 1, z = pos.z}
    local node = minetest.get_node(below)
    local def = minetest.registered_nodes[node.name]
    return def and def.walkable
end

--- Moves the entity toward a specific waypoint.
function ia_pathfinding.move_to_waypoint(self, target)
    local my_pos = self.object:get_pos()
    if not my_pos then return end

    local move_dir = vector.direction(my_pos, target)
    local speed = self._movement_speed or 3

    -- Apply Velocity (X and Z only, keep Y for gravity)
    local curr_v = self.object:get_velocity()
    self.object:set_velocity({
        x = move_dir.x * speed,
        y = curr_v.y, 
        z = move_dir.z * speed
    })

    -- Look at the target
    local yaw = minetest.dir_to_yaw(move_dir)
    self.object:set_yaw(yaw)

    -- Reach Detection
    local dist = vector.distance({x=target.x, y=0, z=target.z}, {x=my_pos.x, y=0, z=my_pos.z})
    -- UPDATED: Tightened reach detection to 0.2 to fix "Apple on the left" logic
    if dist < 0.2 and math.abs(target.y - my_pos.y) < 1.2 then
        self._path_index = self._path_index + 1
        return true
    end

    -- Stuck Detection
    if self._last_pos and vector.distance(my_pos, self._last_pos) < 0.05 then
        if ia_pathfinding.is_entity_on_ground(self) then
            ia_dunce.jump(self)
        end
    end
    self._last_pos = my_pos
    return false
end

-- FIXME missing walking animation
-- FIXME why do they hop so much?
-- FIXME why are they drifting when they stop?

--- Iterates through the current path.
function ia_pathfinding.follow_path(self)
    if not self._current_path then return false end

    local waypoint = self._current_path[self._path_index]
    if not waypoint then
        -- Path finished
        self._current_path = nil
        ia_dunce.stop(self)
        return true
    end

    ia_pathfinding.move_to_waypoint(self, waypoint)
    return false
end
