-- ia_pathfinding/pathfinding.lua

local PF_BUDGET = 100 -- How many nodes to check per tick
local MAX_NODES = 1000 -- Maximum search depth before giving up

-- TODO dynamically adjust depending on actual time taken or server load?
-- i.e., better a* if resources allow for it

--- Internal: Follows parents back to the start
function ia_pathfinding._reconstruct_path(node)
	--minetest.log('ia_pathfinding._reconstruct_path()')
    local path = {}
    local curr = node
    while curr do
        table.insert(path, 1, curr.pos)
        curr = curr.parent
    end
    return path
end

function ia_pathfinding.get_node_cost(self, pos)
	--minetest.log('ia_pathfinding.get_node_cost()')
    local node = minetest.get_node(pos)
    local node_name = node.name
    local is_walkable, height = ia_dunce.get_node_properties(node_name)

    -- 1. Handle Doors (A* should prefer these over walls)
    if minetest.get_item_group(node_name, "door") > 0 then
        return 2.0 -- Cost of "opening" the door
    end

    -- 2. Physical Obstacles
    if not is_walkable then return 1 end
    if height > 1.1 then return 999 end

    -- 3. Social Cost (Crowds)
    if ia_dunce.is_node_occupied(pos, self.object) then
        return 25
    end

    -- 4. Digging Cost
    if ia_dunce.can_dig_node then
        local can_dig, time = ia_dunce.can_dig_node(self, node_name)
        if can_dig then return 1 + (time * 5) end
    end

    return 1
end

--- High-level path trigger.
-- Now detects if the target object has moved significantly.
function ia_pathfinding.find_path_to(self, target_pos)
	minetest.log('ia_pathfinding.find_path_to()')
    local actual_dest = self:get_navigable_destination(target_pos)

    -- Detect if the target has moved more than 1 block from our last calculation
    local target_moved = false
    if self._path_target then
        if vector.distance(self._path_target, actual_dest) > 1.0 then
            target_moved = true
        end
    end

    -- If we are already heading there and it hasn't moved, stay the course.
    if not target_moved and self._path_target and vector.equals(self._path_target, actual_dest) then
        if self._current_path or self._path_thread then
            return 
        end
    end

    -- Reset and start new search
    self._current_path = nil
    self._path_target = vector.new(actual_dest)
    
    local my_pos = self.object:get_pos()
    if not my_pos then return end
    
    self._path_thread = ia_pathfinding.create_path_coroutine(self, my_pos, actual_dest)
end

--- Finds a reachable empty space near a target.
function ia_pathfinding.get_navigable_destination(self, target_pos)
	minetest.log('ia_pathfinding.get_navigable_destination()')
    if not ia_dunce.is_node_occupied(target_pos, self.object) then
        return target_pos
    end

    local neighbors = ia_pathfinding._get_neighbors(target_pos)
    for _, pos in ipairs(neighbors) do
        if not ia_dunce.is_node_occupied(pos, self.object) then
            return pos
        end
    end
    return target_pos
end

function ia_pathfinding._get_neighbors(pos)
	--minetest.log('ia_pathfinding._get_neighbors()')
    if not pos or not pos.y then 
        return {} 
    end

    local offsets = {
        {x = 1,  y = 0, z = 0}, 
        {x = -1, y = 0, z = 0}, 
        {x = 0,  y = 0, z = 1}, 
        {x = 0,  y = 0, z = -1}
    }
    
    local valid = {}
    
    for _, o in ipairs(offsets) do
        local check_pos = vector.add(pos, o)
        -- Use our ground finder (Jump 1, Fall 3) to find valid walking surfaces
        local ground = ia_dunce.find_ground_level(check_pos, 1, 3)

        if ground then 
            table.insert(valid, ground) 
        end
    end
    
    return valid
end

--- Internal: Selects node with lowest f-score.
function ia_pathfinding._get_best_node(set)
	--minetest.log('ia_pathfinding._get_best_node()')
    local best_id, best_node = nil, nil
    local min_f = math.huge
    for id, node in pairs(set) do
        local f = node.g + node.h
        if f < min_f then
            min_f = f
            best_id, best_node = id, node
        end
    end
    return best_id, best_node
end

--- Creates the A* coroutine thread.
function ia_pathfinding.create_path_coroutine(self, start, dest)
	minetest.log('ia_pathfinding.create_path_coroutine()')
    return coroutine.create(function()
        local open_set = { [vector.to_string(start)] = {pos = start, g = 0, h = vector.distance(start, dest)} }
        local closed_set = {}
        local count = 0
        local closed_count = 0

        while next(open_set) do
            local current_id, current = ia_pathfinding._get_best_node(open_set)

            if vector.distance(current.pos, dest) <= 1.1 then
                local path = {}
                local curr = current
                while curr do
                    table.insert(path, 1, curr.pos)
                    curr = curr.parent
                end
                return path
            end

            open_set[current_id] = nil
            closed_set[current_id] = current

            for _, neighbor_pos in ipairs(ia_pathfinding._get_neighbors(current.pos)) do
                local neighbor_id = vector.to_string(neighbor_pos)
                if not closed_set[neighbor_id] then
                    local cost = ia_pathfinding.get_node_cost(self, neighbor_pos)
                    if cost < 999 then
                        local g_score = current.g + cost
                        if not open_set[neighbor_id] or g_score < open_set[neighbor_id].g then
                            open_set[neighbor_id] = {
                                pos = neighbor_pos, parent = current,
                                g = g_score, h = vector.distance(neighbor_pos, dest)
                            }
                        end
                    end
                end
            end

            count = count + 1
            closed_count = closed_count + 1
            if count >= PF_BUDGET then
                count = 0
                coroutine.yield(nil)
            end
            if closed_count > MAX_NODES then return nil end
        end
        return nil
    end)
end

--- Triggers pathing and manages coroutine lifecycle.
function ia_pathfinding.process_pathfinding(self)
	--minetest.log('ia_pathfinding.process_pathfinding()')
    if self._target_object and not ia_dunce.is_valid_object(self._target_object) then
        self._current_path = nil
        self._path_thread = nil
        ia_dunce.stop(self)
        return
    end

    if not self._path_thread then return end

    local status, result = coroutine.resume(self._path_thread)
    if coroutine.status(self._path_thread) == "dead" then
        self._path_thread = nil
        if status and result and #result > 0 then
            self._current_path = result
            self._path_index = ia_dunce.is_at(self, result[1], 0.8) and 2 or 1
        else
            self._current_path = nil
        end
    end
end
