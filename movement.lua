-- ia_pathfinding/movement.lua
-- NOTE must handle optionally digging, climbing, swimming, flying, etc

------- Helper: Checks if the entity is on the ground.
----function ia_pathfinding.is_entity_on_ground(self)
----    local pos = self.object:get_pos()
----    if not pos then return false end
----    local vel = self.object:get_velocity()
----    if math.abs(vel.y) > 0.1 then return false end
----    
----    local below = {x = pos.x, y = pos.y - 1, z = pos.z}
----    local node = minetest.get_node(below)
----    local def = minetest.registered_nodes[node.name]
----    return def and def.walkable
----end
----
------- Moves the entity toward a specific waypoint.
----function ia_pathfinding.move_to_waypoint(self, target)
----    local my_pos = self.object:get_pos()
----    if not my_pos then return end
----
----    local move_dir = vector.direction(my_pos, target)
----    local speed = self._movement_speed or 3
----
----    -- Apply Velocity (X and Z only, keep Y for gravity)
----    local curr_v = self.object:get_velocity()
----    self.object:set_velocity({
----        x = move_dir.x * speed,
----        y = curr_v.y, 
----        z = move_dir.z * speed
----    })
----
----    -- Look at the target
----    local yaw = minetest.dir_to_yaw(move_dir)
----    self.object:set_yaw(yaw)
----
----    -- Reach Detection
----    local dist = vector.distance({x=target.x, y=0, z=target.z}, {x=my_pos.x, y=0, z=my_pos.z})
----    -- UPDATED: Tightened reach detection to 0.2 to fix "Apple on the left" logic
----    if dist < 0.2 and math.abs(target.y - my_pos.y) < 1.2 then
----        self._path_index = self._path_index + 1
----        return true
----    end
----
----    -- Stuck Detection
----    if self._last_pos and vector.distance(my_pos, self._last_pos) < 0.05 then
----        if ia_pathfinding.is_entity_on_ground(self) then
----            ia_dunce.jump(self)
----        end
----    end
----    self._last_pos = my_pos
----    return false
----end
----
------ FIXME missing walking animation
------ FIXME why do they hop so much?
------ FIXME why are they drifting when they stop?
----
------- Iterates through the current path.
----function ia_pathfinding.follow_path(self)
----    if not self._current_path then return false end
----
----    local waypoint = self._current_path[self._path_index]
----    if not waypoint then
----        -- Path finished
----        self._current_path = nil
----        ia_dunce.stop(self)
----        return true
----    end
----
----    ia_pathfinding.move_to_waypoint(self, waypoint)
----    return false
----end
---- ia_pathfinding/movement.lua
--
--- Helper: Checks if the entity is on the ground.
function ia_pathfinding.is_entity_on_ground(self)
    local pos = self.object:get_pos()
    if not pos then return false end
    local vel = self.object:get_velocity()
    -- Assert to catch logic inconsistencies early
    assert(vel ~= nil, "Entity velocity is nil during ground check")
    
    if math.abs(vel.y) > 0.1 then return false end
    
    local below = {x = pos.x, y = pos.y - 0.5, z = pos.z}
    local node = minetest.get_node(below)
    local def = minetest.registered_nodes[node.name]
    return def and def.walkable
end
--
----- Moves the entity toward a specific waypoint.
--function ia_pathfinding.move_to_waypoint(self, target)
--    local my_pos = self.object:get_pos()
--    if not my_pos then return end
--
--    local dist_raw = vector.distance(my_pos, target)
--    local dist_xz = vector.distance({x=target.x, y=0, z=target.z}, {x=my_pos.x, y=0, z=my_pos.z})
--
--    -- 1. Reach Detection (Fixed Drifting)
--    -- If we are close enough, kill velocity IMMEDIATELY before finishing
--    if dist_xz < 0.3 and math.abs(target.y - my_pos.y) < 1.2 then
--        ia_dunce.stop(self) -- Apply the handbrake
--        self._path_index = self._path_index + 1
--        return true
--    end
--
--    -- 2. Direction and Speed
--    local move_dir = vector.direction(my_pos, target)
--    local speed = self._movement_speed or 3
--
--    -- 3. Animation Logic (Fixes missing walking animation)
--    ia_dunce.set_animation(self, 'WALK')
--
--    -- 4. Apply Velocity
--    local curr_v = self.object:get_velocity()
--    self.object:set_velocity({
--        x = move_dir.x * speed,
--        y = curr_v.y, 
--        z = move_dir.z * speed
--    })
--
--    -- 5. Look at the target
--    local yaw = minetest.dir_to_yaw(move_dir)
--    self.object:set_yaw(yaw)
--
--    -- 6. Stuck Detection / Anti-Hop
--    -- Only jump if there is a vertical difference or a physical obstruction
--    if self._last_pos and vector.distance(my_pos, self._last_pos) < 0.05 then
--        local node_ahead = ia_dunce.get_relative_node_pos(self, 1, 0)
--        local def = minetest.registered_nodes[minetest.get_node(node_ahead).name]
--        
--        if def and def.walkable and ia_pathfinding.is_entity_on_ground(self) then
--            ia_dunce.jump(self)
--        end
--    end
--
--    self._last_pos = my_pos
--    return false
--end
--
----- Iterates through the current path.
--function ia_pathfinding.follow_path(self)
--    if not self._current_path then return false end
--
--    local waypoint = self._current_path[self._path_index]
--    if not waypoint then
--        -- Path finished
--        self._current_path = nil
--        ia_dunce.stop(self)
--        
--        -- Trigger arrival action if data exists
--        if self._target_data then
--            ia_pathfinding.perform_arrival_action(self, self._target_data)
--            self._target_data = nil
--        end
--        return true
--    end
--
--    ia_pathfinding.move_to_waypoint(self, waypoint)
--    return false
--end
-- ia_pathfinding/movement.lua

--- Moves the entity toward a specific waypoint.
function ia_pathfinding.move_to_waypoint(self, target)
    local my_pos = self.object:get_pos()
    if not my_pos then return end

    -- 1. Reach Detection
    -- We check XZ distance for "arrival" at a node
    local dist_xz = vector.distance({x=target.x, y=0, z=target.z}, {x=my_pos.x, y=0, z=my_pos.z})
    
    -- If we are at the waypoint, stop moving and signal to increment path
    if dist_xz < 0.3 and math.abs(target.y - my_pos.y) < 1.2 then
        ia_dunce.stop(self)
        return true
    end

    -- 2. Direction and Speed
    local move_dir = vector.direction(my_pos, target)
    local speed = self._movement_speed or 3

    -- 3. Animation
    ia_dunce.set_animation(self, 'WALK')

    -- 4. Apply Velocity
    local curr_v = self.object:get_velocity()
    self.object:set_velocity({
        x = move_dir.x * speed,
        y = curr_v.y, 
        z = move_dir.z * speed
    })

    -- 5. Look at the target
    local yaw = minetest.dir_to_yaw(move_dir)
    self.object:set_yaw(yaw)

    -- 6. Stuck Detection
    if self._last_pos and vector.distance(my_pos, self._last_pos) < 0.05 then
        if ia_pathfinding.is_entity_on_ground(self) then
            ia_dunce.jump(self)
        end
    end
    self._last_pos = my_pos
    
    return false
end

--- Iterates through the current path.
function ia_pathfinding.follow_path(self)
    if not self._current_path then return false end

    -- 1. Check if the target object is still there before taking a step
    -- This prevents walking toward items that players already picked up
    if self._target_object and not ia_dunce.is_valid_object(self._target_object) then
        minetest.log('info', '[ia_pathfinding] Target lost, clearing path')
        ia_pathfinding.clear_pathing_state(self)
        ia_dunce.stop(self)
        return false
    end

    local waypoint = self._current_path[self._path_index]
    
    -- 2. Handle Path Completion
    if not waypoint then
        -- We reached the end of the calculated path
        local data = self._target_data
        
        -- IMMEDIATELY clear state so on_step doesn't call follow_path again
        ia_pathfinding.clear_pathing_state(self)
        ia_dunce.stop(self)

        -- 3. Perform the actual action (Pickup/Equip)
        if data then
            ia_pathfinding.perform_arrival_action(self, data)
        end
        return true
    end

    -- 3. Move toward current waypoint
    if ia_pathfinding.move_to_waypoint(self, waypoint) then
        self._path_index = self._path_index + 1
    end
    
    return false
end
