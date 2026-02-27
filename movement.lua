-- ia_pathfinding/movement.lua
-- NOTE must handle optionally digging, climbing, swimming, flying, etc

--- Helper: Checks if the entity is currently standing on a solid surface.
-- Replaces the missing ia_dunce.is_on_ground function.
function ia_pathfinding.is_entity_on_ground(self)
    local pos = self.object:get_pos()
    if not pos then return false end
    
    -- Check vertical velocity (near 0 means not falling or jumping)
    local vel = self.object:get_velocity()
    if math.abs(vel.y) > 0.01 then return false end
    
    -- Check if the node directly below the entity is walkable (solid)
    local below = {x = pos.x, y = pos.y - 1, z = pos.z}
    local node = minetest.get_node(below)
    local def = minetest.registered_nodes[node.name]
    
    return def and def.walkable
end

--- Helper: Logic to make the mob jump when it hits an obstacle.
function ia_pathfinding.execute_stuck_jump(self)
    if ia_pathfinding.is_entity_on_ground(self) then
        if ia_dunce and ia_dunce.jump then
            ia_dunce.jump(self)
        else
            -- Manual jump fallback: apply upward velocity
            local v = self.object:get_velocity()
            self.object:set_velocity({x = v.x, y = 4.5, z = v.z})
        end
    end
end

--- Handles physical movement and obstacle logic
function ia_pathfinding.move_to_waypoint(self, target, overrides)
    overrides = overrides or {}
    local my_pos = self.object:get_pos()
    if not my_pos then return end

    local move_dir = vector.direction(my_pos, target)
    local speed = self._movement_speed or 3

    -- Interaction: If the node ahead is a door, try to open it
    local ahead_pos = vector.add(my_pos, vector.multiply(move_dir, 1))
    local node_ahead = minetest.get_node(ahead_pos)
    if minetest.get_item_group(node_ahead.name, "door") > 0 then
        ia_dunce.handle_door_front(self, "open")
    end

    -- Apply speed modifiers based on entity state
    if self._is_climbing then speed = speed * 0.7 end
    if self._is_sneaking then speed = speed * 0.4 end

    local curr_v = self.object:get_velocity()
    local target_v = vector.multiply(move_dir, speed)

    -- Apply movement (preserving vertical velocity for gravity)
    self.object:set_velocity({
        x = target_v.x,
        y = curr_v.y, 
        z = target_v.z
    })

    -- Update rotation to look toward the movement direction
    if speed > 0 then
        local yaw = minetest.dir_to_yaw(move_dir)
        self.object:set_yaw(yaw)
    end

    -- Animation handling
    if overrides.animate then
        overrides.animate(self)
    else
        if self._is_climbing then
            ia_dunce.set_animation(self, 'CLIMB')
        elseif not self._is_falling then
            ia_dunce.set_animation(self, self._is_sneaking and 'SNEAK' or 'WALK')
        end
    end
end

--- High-level waypoint follower
function ia_pathfinding.follow_path(self, overrides)
    if not self._current_path then return true end

    local target = self._current_path[self._path_index]
    if not target then
        self._current_path = nil
        ia_dunce.stop(self)
        return true
    end

    local my_pos = self.object:get_pos()
    local horizontal_dist = vector.distance({x=target.x, y=0, z=target.z}, {x=my_pos.x, y=0, z=my_pos.z})
    local vertical_dist = math.abs(target.y - my_pos.y)

    -- Waypoint Reach Detection
    if horizontal_dist < 0.6 and vertical_dist < 1.2 then
        self._path_index = self._path_index + 1
        self._last_waypoint_pos = nil -- Reset stuck detection on progress
        
        if self._path_index > #self._current_path then
            self._current_path = nil
            ia_dunce.stop(self)
            return true
        end
        return false
    end

    -- Stuck Detection and Recovery Logic
    local current_time = minetest.get_gametime()
    if not self._last_move_check or current_time > self._last_move_check then
        if self._last_waypoint_pos and vector.distance(my_pos, self._last_waypoint_pos) < 0.1 then
            -- We haven't moved: Attempt a jump to clear obstacles
            ia_pathfinding.execute_stuck_jump(self)
            
            -- If stuck for too long, force a path recalculation
            self._stuck_timer = (self._stuck_timer or 0) + 1
            if self._stuck_timer > 5 then
                self._current_path = nil 
                self._stuck_timer = 0
            end
        else
            self._stuck_timer = 0
        end
        self._last_waypoint_pos = vector.new(my_pos)
        self._last_move_check = current_time + 1
    end

    self:move_to_waypoint(target, overrides)
    return false
end
