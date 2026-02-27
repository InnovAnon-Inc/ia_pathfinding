-- ia_pathfinding/pathfinding.lua
-- NOTE must handle optionally digging, climbing, swimming, flying, etc

--------- Helper: Returns the configuration table for the star pathfinder.
------function ia_pathfinding.get_search_settings(self)
------    -- `width`: Specifies the object size along x- and z-axes. Defaults to `1`.
------    -- `height`: Specifies the object size along the y-axis. Defaults to `2`.
------    -- `max_jump`: Specifies the maximum jump height. Defaults to `1`.
------    -- `max_drop`: Specifies the maximum drop height. Defaults to `1`.
------    -- `max_iter`: Specifies the maximum number of main loop iterations before quitting. Defaults to `256`. For now, has a hard limit of `1024`.
------    -- `climb`: Sets the ability to climb ladders (`true` or `false`). Defaults to `false`.
------    local settings = {}
------    settings.max_iter = 1024
------    -- Future: Add digging/climbing capabilities here
------    return settings
------end
------
--------- Helper: Validates if the target object or node still exists.
------function ia_pathfinding.is_target_still_valid(target)
------    if not target then return false end
------
------    -- Handle Minetest Objects (Players, Dropped Items, Mobs)
------    if type(target) == "userdata" or (type(target) == "table" and target.get_pos) then
------        if not ia_dunce.is_valid_object(target) then return false end
------        -- Check if dropped item is still real (not picked up)
------        local ent = target:get_luaentity()
------        if ent and ent.name == "__builtin:item" and ent.itemstring == "" then
------            return false
------        end
------        return true
------    end
------
------    -- Handle positions
------    if type(target) == "table" and target.x then
------        local node = minetest.get_node_or_nil(target)
------        if not node or node.name == "ignore" then return false end
------        return true
------    end
------
------    return false
------end
------
--------- Helper: Removes redundant nodes from the library output.
-------- This makes the path followable by the movement logic.
------function ia_pathfinding.smooth_path(path)
------    if not path or #path <= 2 then return path end
------    local smoothed = {path[1]}
------    local current_index = 1
------
------    while current_index < #path do
------        local last_visible = current_index + 1
------        local max_look = math.min(current_index + 8, #path)
------
------        for look_ahead = current_index + 2, max_look do
------            -- Only skip nodes if there is a clear line of sight
------            if ia_dunce.is_line_of_sight_clear(path[current_index], path[look_ahead]) then
------                last_visible = look_ahead
------            else
------                break
------            end
------        end
------
------        table.insert(smoothed, path[last_visible])
------        current_index = last_visible
------    end
------    return smoothed
------end
------
--------- Helper: Updates the entity's pathing state variables.
------function ia_pathfinding.apply_path_to_actor(self, path)
------    -- Path smoothing prevents the mob from stuttering on raw node-by-node steps
------    self._current_path = ia_pathfinding.smooth_path(path)
------    self._path_index = 1
------end
------
--------- Helper: Handles logic when a path cannot be found.
------function ia_pathfinding.handle_path_failure(self, my_pos, actual_dest)
------    if ia_dunce.is_line_of_sight_clear(my_pos, actual_dest) then
------        ia_pathfinding.apply_path_to_actor(self, {actual_dest})
------    else
------        self._current_path = nil
------        ia_dunce.stop(self)
------    end
------end
------
--------- Helper: Finds the nearest navigable ground near a target position.
------function ia_pathfinding.get_navigable_destination(self, pos)
------    if not pos then return nil end
------
------    local node = minetest.get_node(pos)
------    local def = minetest.registered_nodes[node.name]
------
------    if def and def.walkable then
------        -- Search upward for a 2-block air gap
------        for dy = 1, 3 do
------            local up = vector.add(pos, {x=0, y=dy, z=0})
------            local up_node = minetest.get_node(up)
------            local up_def = minetest.registered_nodes[up_node.name]
------            if up_def and not up_def.walkable then
------                return up
------            end
------        end
------        local ground = ia_dunce.find_ground_level(pos, 1, 5)
------        return ground or pos
------    end
------
------    return pos
------end
------
--------- Wrapper for the 'star' mod pathfinder.
------function ia_pathfinding.calculate_star_path(self, start, dest)
------    local settings = ia_pathfinding.get_search_settings(self)
------    local path = star.find_path(start, dest, settings)
------
------    if path and #path > 0 then
------        return path
------    end
------    return nil
------end
------
--------- Starts a pathfinding task.
------function ia_pathfinding.find_path_to(self, target_pos, overrides)
------    local my_pos = self.object:get_pos()
------    
------    if not my_pos or not target_pos then return end
------
------    -- Shortcut: Direct movement if clear line of sight exists
------    if ia_dunce.is_line_of_sight_clear(my_pos, target_pos) then
------        ia_pathfinding.apply_path_to_actor(self, {target_pos})
------        self._path_target = vector.new(target_pos)
------        return
------    end
------
------    local actual_dest = ia_pathfinding.get_navigable_destination(self, target_pos)
------
------    -- Optimization: Skip calculation if target hasn't moved significantly
------    if self._path_target and vector.distance(self._path_target, actual_dest) < 0.2 then
------        if self._current_path then return end
------    end
------
------    self._path_target = vector.new(actual_dest)
------
------    local result = ia_pathfinding.calculate_star_path(self, my_pos, actual_dest)
------
------    if result then
------        ia_pathfinding.apply_path_to_actor(self, result)
------    else
------        ia_pathfinding.handle_path_failure(self, my_pos, actual_dest)
------    end
------end
------
--------- Process lifecycle health-check.
------function ia_pathfinding.process_pathfinding(self)
------    -- Ensure the mob stops if its current chase target (e.g. apple) vanishes
------    if self._target_object and not ia_pathfinding.is_target_still_valid(self._target_object) then
------        self._current_path = nil
------        self._target_object = nil
------        ia_dunce.stop(self)
------    end
------end
------ ia_pathfinding/pathfinding.lua
----
------- Helper: Resets all navigation-related state variables.
----function ia_pathfinding.clear_pathing_state(self)
----    self._current_path = nil
----    self._path_index = 1
----    self._path_target = nil
----    self._target_object = nil
----    self._target_data = nil
----    ia_dunce.stop(self)
----end
----
------- Helper: Returns the configuration table for the star pathfinder.
----function ia_pathfinding.get_search_settings(self)
----    local settings = {}
----    settings.max_iter = 1024
----    return settings
----end
----
------- Helper: Validates if the target object or node still exists.
----function ia_pathfinding.is_target_still_valid(target)
----    if not target then return false end
----
----    if type(target) == "userdata" or (type(target) == "table" and target.get_pos) then
----        if not ia_dunce.is_valid_object(target) then return false end
----        local ent = target:get_luaentity()
----        if ent and ent.name == "__builtin:item" and ent.itemstring == "" then
----            return false
----        end
----        return true
----    end
----
----    if type(target) == "table" and target.x then
----        local node = minetest.get_node_or_nil(target)
----        if not node or node.name == "ignore" then return false end
----        return true
----    end
----
----    return false
----end
----
------- Helper: Removes redundant nodes from the library output.
----function ia_pathfinding.smooth_path(path)
----    if not path or #path <= 2 then return path end
----    local smoothed = {path[1]}
----    local current_index = 1
----
----    while current_index < #path do
----        local last_visible = current_index + 1
----        local max_look = math.min(current_index + 8, #path)
----
----        for look_ahead = current_index + 2, max_look do
----            if ia_dunce.is_line_of_sight_clear(path[current_index], path[look_ahead]) then
----                last_visible = look_ahead
----            else
----                break
----            end
----        end
----
----        table.insert(smoothed, path[last_visible])
----        current_index = last_visible
----    end
----    return smoothed
----end
----
------- Helper: Updates the entity's pathing state variables.
----function ia_pathfinding.apply_path_to_actor(self, path)
----    self._current_path = ia_pathfinding.smooth_path(path)
----    self._path_index = 1
----end
----
------- Helper: Handles logic when a path cannot be found.
----function ia_pathfinding.handle_path_failure(self, my_pos, actual_dest)
----    if ia_dunce.is_line_of_sight_clear(my_pos, actual_dest) then
----        ia_pathfinding.apply_path_to_actor(self, {actual_dest})
----    else
----        ia_pathfinding.clear_pathing_state(self)
----    end
----end
----
------- Helper: Finds the nearest navigable ground near a target position.
----function ia_pathfinding.get_navigable_destination(self, pos)
----    if not pos then return nil end
----
----    local node = minetest.get_node(pos)
----    local def = minetest.registered_nodes[node.name]
----
----    -- If the target is inside a solid block, look for air above it
----    if def and def.walkable then
----        for dy = 1, 3 do
----            local up = vector.add(pos, {x=0, y=dy, z=0})
----            local up_node = minetest.get_node(up)
----            local up_def = minetest.registered_nodes[up_node.name]
----            if up_def and not up_def.walkable then
----                return up
----            end
----        end
----    end
----
----    -- If target is in air, ensure we find the floor beneath it
----    local ground = ia_dunce.find_ground_level(pos, 1, 5)
----    return ground or pos
----end
----
------- Wrapper for the 'star' mod pathfinder.
----function ia_pathfinding.calculate_star_path(self, start, dest)
----    local settings = ia_pathfinding.get_search_settings(self)
----    local path = star.find_path(start, dest, settings)
----
----    if path and #path > 0 then
----        return path
----    end
----    return nil
----end
----
------- Starts a pathfinding task.
----function ia_pathfinding.find_path_to(self, target_pos, overrides)
----    local my_pos = self.object:get_pos()
----    if not my_pos or not target_pos then return end
----
----    if ia_dunce.is_line_of_sight_clear(my_pos, target_pos) then
----        ia_pathfinding.apply_path_to_actor(self, {target_pos})
----        self._path_target = vector.new(target_pos)
----        return
----    end
----
----    local actual_dest = ia_pathfinding.get_navigable_destination(self, target_pos)
----
----    -- FIX: Lowered threshold and ensured calculation runs if no path exists
----    if self._path_target and vector.distance(self._path_target, actual_dest) < 0.1 then
----        if self._current_path then return end
----    end
----
----    self._path_target = vector.new(actual_dest)
----    local result = ia_pathfinding.calculate_star_path(self, my_pos, actual_dest)
----
----    if result then
----        ia_pathfinding.apply_path_to_actor(self, result)
----    else
----        ia_pathfinding.handle_path_failure(self, my_pos, actual_dest)
----    end
----end
----
------- Process lifecycle health-check.
----function ia_pathfinding.process_pathfinding(self)
----    if self._target_object and not ia_pathfinding.is_target_still_valid(self._target_object) then
----        ia_pathfinding.clear_pathing_state(self)
----    end
----end
---- ia_pathfinding/pathfinding.lua
---- Integrated with 'star' mod for robust A* calculation
--
----- Helper: Resets all navigation-related state variables.
---- Each line of code should do just one thing and be self-documenting.
--function ia_pathfinding.clear_pathing_state(self)
--    self._current_path = nil -- Remove current route
--    self._path_index = 1     -- Reset progress
--    self._path_target = nil  -- Clear destination memory
--    self._target_object = nil -- Clear tracked entity
--    self._target_data = nil   -- Clear metadata
--    ia_dunce.stop(self)       -- Physically stop velocity
--end
--
----- Helper: Returns true if the mob has no current movement goals.
--function ia_pathfinding.is_idle(self)
--    return self._current_path == nil or self._path_index > #self._current_path
--end
--
----- Helper: Returns the configuration table for the star pathfinder.
--function ia_pathfinding.get_search_settings(self)
--    local settings = {}
--    settings.max_iter = 1024
--    return settings
--end
--
----- Helper: Validates if the target object or node still exists.
--function ia_pathfinding.is_target_still_valid(target)
--    if not target then return false end
--
--    -- Handle Minetest Objects (Players, Dropped Items, Mobs)
--    if type(target) == "userdata" or (type(target) == "table" and target.get_pos) then
--        if not ia_dunce.is_valid_object(target) then return false end
--        -- Check if dropped item is still real (not picked up)
--        local ent = target:get_luaentity()
--        if ent and ent.name == "__builtin:item" and ent.itemstring == "" then
--            return false
--        end
--        return true
--    end
--
--    -- Handle positions
--    if type(target) == "table" and target.x then
--        local node = minetest.get_node_or_nil(target)
--        if not node or node.name == "ignore" then return false end
--        return true
--    end
--
--    return false
--end
--
----- Helper: Removes redundant nodes from the library output.
--function ia_pathfinding.smooth_path(path)
--    if not path or #path <= 2 then return path end
--    local smoothed = {path[1]}
--    local current_index = 1
--
--    while current_index < #path do
--        local last_visible = current_index + 1
--        local max_look = math.min(current_index + 8, #path)
--
--        for look_ahead = current_index + 2, max_look do
--            -- Only skip nodes if there is a clear line of sight
--            if ia_dunce.is_line_of_sight_clear(path[current_index], path[look_ahead]) then
--                last_visible = look_ahead
--            else
--                break
--            end
--        end
--
--        table.insert(smoothed, path[last_visible])
--        current_index = last_visible
--    end
--    return smoothed
--end
--
----- Helper: Updates the entity's pathing state variables.
--function ia_pathfinding.apply_path_to_actor(self, path)
--    -- Path smoothing prevents the mob from stuttering on raw node-by-node steps
--    self._current_path = ia_pathfinding.smooth_path(path)
--    self._path_index = 1
--end
--
----- Helper: Handles logic when a path cannot be found.
--function ia_pathfinding.handle_path_failure(self, my_pos, actual_dest)
--    -- If A* failed, try one last direct dash if clear, otherwise give up.
--    if ia_dunce.is_line_of_sight_clear(my_pos, actual_dest) then
--        ia_pathfinding.apply_path_to_actor(self, {actual_dest})
--    else
--        ia_pathfinding.clear_pathing_state(self)
--    end
--end
--
----- Helper: Finds the nearest navigable ground near a target position.
--function ia_pathfinding.get_navigable_destination(self, pos)
--    if not pos then return nil end
--
--    local node = minetest.get_node(pos)
--    local def = minetest.registered_nodes[node.name]
--
--    -- If target is inside a solid block, look for air above it
--    if def and def.walkable then
--        for dy = 1, 3 do
--            local up = vector.add(pos, {x=0, y=dy, z=0})
--            local up_node = minetest.get_node(up)
--            local up_def = minetest.registered_nodes[up_node.name]
--            if up_def and not up_def.walkable then
--                return up
--            end
--        end
--    end
--
--    -- If target is in air (floating item), find the floor beneath it
--    local ground = ia_dunce.find_ground_level(pos, 1, 5)
--    return ground or pos
--end
--
----- Wrapper for the 'star' mod pathfinder.
--function ia_pathfinding.calculate_star_path(self, start, dest)
--    local settings = ia_pathfinding.get_search_settings(self)
--    local path = star.find_path(start, dest, settings)
--
--    if path and #path > 0 then
--        return path
--    end
--    return nil
--end
--
----- Starts a pathfinding task.
--function ia_pathfinding.find_path_to(self, target_pos, overrides)
--    local my_pos = self.object:get_pos()
--    if not my_pos or not target_pos then return end
--
--    -- REFACTOR: Removed the early LOS shortcut. 
--    -- We now rely on the 'star' module to provide the path first.
--
--    local actual_dest = ia_pathfinding.get_navigable_destination(self, target_pos)
--
--    -- Optimization: Skip calculation if target hasn't moved significantly
--    if self._path_target and vector.distance(self._path_target, actual_dest) < 0.1 then
--        if self._current_path then return end
--    end
--
--    self._path_target = vector.new(actual_dest)
--
--    local result = ia_pathfinding.calculate_star_path(self, my_pos, actual_dest)
--
--    if result then
--        ia_pathfinding.apply_path_to_actor(self, result)
--    else
--        ia_pathfinding.handle_path_failure(self, my_pos, actual_dest)
--    end
--end
--
----- Process lifecycle health-check.
--function ia_pathfinding.process_pathfinding(self)
--    -- Ensure the mob stops if its current chase target (e.g. apple) vanishes
--    if self._target_object and not ia_pathfinding.is_target_still_valid(self._target_object) then
--        ia_pathfinding.clear_pathing_state(self)
--    end
--end
-- ia_pathfinding/pathfinding.lua
-- Minimalist wrapper for the 'star' mod.

--- Helper: Settings for the star pathfinder.
function ia_pathfinding.get_search_settings(self)
    return {
        max_iter = 1024,
        max_jump = 1,
        max_drop = 3,
        climb = true,
    }
end

--- Updates the entity's pathing state.
function ia_pathfinding.apply_path_to_actor(self, path)
    self._current_path = path
    self._path_index = 1
end

--- The main pathfinding entry point.
--function ia_pathfinding.find_path_to(self, target_pos)
--    local my_pos = self.object:get_pos()
--    if not my_pos or not target_pos then return end
--
--    -- NO LOS SHORTCUT: We trust the A* library to find the way.
--    -- NO DISTANCE OPTIMIZATION: We update every time we're told to.
--
--    local settings = ia_pathfinding.get_search_settings(self)
--    local path = star.find_path(my_pos, target_pos, settings)
--
--    if path and #path > 0 then
--        ia_pathfinding.apply_path_to_actor(self, path)
--    else
--        -- If pathfinding fails, we clear the path so we don't walk into walls.
--        self._current_path = nil
--    end
--end

--- Lifecycle check: Clears path if the target entity (like an apple) is gone.
function ia_pathfinding.process_pathfinding(self)
    if self._target_object and not ia_dunce.is_valid_object(self._target_object) then
        self._current_path = nil
        self._target_object = nil
    end
end






-- ia_pathfinding/pathfinding.lua

--- Helper: Returns true if the mob has no current movement goals.
function ia_pathfinding.is_idle(self)
    return self._current_path == nil or self._path_index > #self._current_path
end

--- Helper: Resets pathing state.
function ia_pathfinding.clear_pathing_state(self)
    self._current_path = nil
    self._path_index = 1
    self._path_target = nil
    self._target_object = nil
end

-- ... [get_search_settings and is_target_still_valid remain the same] ...

--- Starts a pathfinding task.
function ia_pathfinding.find_path_to(self, target_pos)
    local my_pos = self.object:get_pos()
    if not my_pos or not target_pos then return end

    -- CHANGE: Removed the Line of Sight shortcut.
    -- We now rely entirely on 'star' to find the most valid route.

    local actual_dest = ia_pathfinding.get_navigable_destination(self, target_pos)

    -- CHANGE: Removed distance optimization.
    -- If this function is called, we force a fresh path calculation.
    self._path_target = vector.new(actual_dest)

    local settings = ia_pathfinding.get_search_settings(self)
    local result = star.find_path(my_pos, actual_dest, settings)

    if result and #result > 0 then
        ia_pathfinding.apply_path_to_actor(self, result)
    else
        ia_pathfinding.clear_pathing_state(self)
    end
end
