-- ia_pathfinding/movement.lua

function ia_pathfinding.handle_obstacles(self)
	minetest.log('ia_pathfinding.handle_obstacles()')
    local pos = self.object:get_pos()
    if not pos then return end

    local ahead_pos = ia_dunce.get_relative_node_pos(self, 1, 0)
    local node = minetest.get_node(ahead_pos)
    local is_walkable, height = ia_dunce.get_node_properties(node.name)

    if not is_walkable then return end

    if minetest.get_item_group(node.name, "door") > 0 then
        return ia_dunce.handle_door_front(self, "open")
    end

    if height > 1.1 then
        return ia_pathfinding.on_path_blocked(self)
    end

    local head_pos = ia_dunce.get_relative_node_pos(self, 1, 1)
    if ia_dunce.is_buildable(head_pos) then
        ia_dunce.jump(self)
    end
end


function ia_pathfinding.get_avoidance_steering(self)
	--minetest.log('ia_pathfinding.get_avoidance_steering()')
    local pos = self.object:get_pos()
    if not pos then return vector.new(0,0,0) end

    local objects = minetest.get_objects_inside_radius(pos, 1.0)
    local avoidance = vector.new(0,0,0)
    local count = 0

    for _, obj in ipairs(objects) do
        if obj ~= self.object then
            local obj_pos = obj:get_pos()
            if obj_pos then
                local diff = vector.subtract(pos, obj_pos)
                local dist = vector.length(diff)
                if dist < 0.1 then
                    diff = {x = math.random() - 0.5, y = 0, z = math.random() - 0.5}
                    dist = 0.1
                end
                avoidance = vector.add(avoidance, vector.divide(diff, dist))
                count = count + 1
            end
        end
    end
    return count > 0 and vector.divide(avoidance, count) or vector.new(0,0,0)
end

function ia_pathfinding.on_path_blocked(self)
	minetest.log('ia_pathfinding.on_path_blocked()')
    local ahead_pos = ia_dunce.get_relative_node_pos(self, 1)
    if not ahead_pos then return end
    local node_name = minetest.get_node(ahead_pos).name

    -- 1. Check for Doors FIRST
    if minetest.get_item_group(node_name, "door") > 0 then
        -- This should call your door handling logic (right-clicking)
        return ia_dunce.handle_door_front(self, "open")
    end

    -- 2. Check for Digging
    if ia_dunce.can_dig_node then
        local can_dig, time = ia_dunce.can_dig_node(self, node_name)
        if can_dig and time < 5.0 then
            return ia_dunce.dig(self, ahead_pos)
        end
    end

    -- 3. If it's a hard wall, give up so we can recalculate
    self._current_path = nil
    return false
end

function ia_pathfinding.handle_movement_obstructions(self)
	--minetest.log('ia_pathfinding.handle_movement_obstructions()')
    -- Handle the "Closing behind us" logic first
    ia_dunce.process_door_cleanup(self)

    local ahead = ia_dunce.get_relative_node_pos(self, 1, 0)
    local node_ahead = minetest.get_node(ahead)
    local is_walkable, height = ia_dunce.get_node_properties(node_ahead.name)

    -- 1. Check for Doors
    if minetest.get_item_group(node_ahead.name, "door") > 0 then
        -- This now internally sets self._active_door_pos
        ia_pathfinding.on_path_blocked(self)
        return true
    end

    -- 2. Check for physical height obstacles
    if is_walkable then
        if height > 1.1 then
            ia_pathfinding.on_path_blocked(self)
            return true
        elseif ia_dunce.is_buildable(ia_dunce.get_relative_node_pos(self, 1, 1)) then
            ia_dunce.jump(self)
        end
    end
    
    return false
end

function ia_pathfinding.calculate_steering(self, my_pos, destination)
	--minetest.log('ia_pathfinding.calculate_steering()')
    local target_dir = vector.normalize(vector.direction(my_pos, destination))
    target_dir.y = 0

    -- Prevent "vibrating" when overlapping the target
    local dist = vector.distance(my_pos, destination)
    local weight_target = (dist < 0.3) and 0 or 0.7
    
    local avoid_dir = ia_pathfinding.get_avoidance_steering(self)

    -- Formula: Blend 70% target direction with 30% avoidance force
    local combined = vector.add(
        vector.multiply(target_dir, weight_target),
        vector.multiply(avoid_dir, 0.3)
    )

    if vector.length(combined) < 0.01 then
        return nil
    end

    return vector.normalize(combined)
end

function ia_pathfinding.navigate_to(self, pos, speed)
	minetest.log('ia_pathfinding.navigate_to()')
    if ia_dunce.is_at(self, pos, 0.5) then
        ia_dunce.stop(self)
        self._stagnant_ticks = 0
        return true
    end

    -- Stuck detection logic
    local my_pos = self.object:get_pos()
    local movement = vector.distance(my_pos, self._last_pos or my_pos)
    
    if vector.distance(my_pos, pos) < 1.5 and movement < 0.05 then
        self._stagnant_ticks = (self._stagnant_ticks or 0) + 1
    else
        self._stagnant_ticks = 0
    end
    self._last_pos = vector.new(my_pos)

    if (self._stagnant_ticks or 0) > 20 then
        ia_dunce.stop(self)
        return true -- Consider "arrived" to break the loop
    end

    ia_pathfinding.move_toward(self, pos, speed)
    return false
end

function ia_pathfinding.follow_path(self)
	--minetest.log('ia_pathfinding.follow_path()')
    if not self._current_path then return true end
    
    local target = self._current_path[self._path_index]

    -- Validation
    if not target or type(target) ~= "table" or not target.x then
        self._current_path = nil
        ia_dunce.stop(self)
        return true
    end

    -- Waypoint Logic
    if ia_dunce.is_at(self, target, 0.5) then
        self._path_index = self._path_index + 1
        
        -- Check if path is finished
        if self._path_index > #self._current_path then
            ia_dunce.stop(self)
            self._current_path = nil
            return true
        end
        target = self._current_path[self._path_index]
    end

    ia_pathfinding.move_toward(self, target)
    return false
end

function ia_pathfinding.vertical_auto_pilot(self)
	--minetest.log('ia_pathfinding.vertical_auto_pilot()')
    -- Priority: Falling -> Climbing -> Swimming -> Flying
    if ia_dunce.fall(self) then return end
    if ia_dunce.climb(self) then return end
    if ia_dunce.swim(self) then return end
    if ia_dunce.fly(self) then return end
end

function ia_pathfinding.move_toward(self, destination, speed)
	--minetest.log('ia_pathfinding.move_toward()')
    local pos = self.object:get_pos()
    if not pos then return end

    ia_pathfinding.handle_movement_obstructions(self)
    ia_pathfinding.vertical_auto_pilot(self)

    -- Adjust speed if sneaking
    local final_speed = speed or 1.5
    if self._is_sneaking then
        final_speed = final_speed * 0.4
    end

    local move_dir = ia_pathfinding.calculate_steering(self, pos, destination)
    if not move_dir then
        ia_dunce.stop(self)
        return
    end

    ia_dunce.face_pos(self, vector.add(pos, move_dir))

    local curr_v = self.object:get_velocity()
    local target_v = vector.multiply(move_dir, final_speed)

    self.object:set_velocity({
        x = target_v.x,
        y = curr_v.y, -- Keep gravity/climb velocity
        z = target_v.z
    })

    -- Only set WALK if we aren't already in a special vertical animation
    if not self._is_climbing and not self._is_falling then
        ia_dunce.set_animation(self, self._is_sneaking and 'SNEAK' or 'WALK')
    end
end
