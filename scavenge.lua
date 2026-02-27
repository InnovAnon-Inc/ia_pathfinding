-- ia_pathfinding/scavenge.lua
-- NOTE must handle optionally searching within chests & stealing

------- Scavenges for items with support for counts, groups, and custom filters.
------ @param requirements Table like { ["group:armor"] = true, ["default:stone"] = 8 }
----function ia_pathfinding.handle_scavenging(self, requirements)
----    if not requirements then return false end
----
----    local item_filter = function(stack)
----        local item_name = stack:get_name()
----
----        -- Check every requirement in the list
----        for criteria, req_value in pairs(requirements) do
----            local match = false
----
----            -- 1. Support Groups
----            if type(criteria) == "string" and criteria:sub(1, 6) == "group:" then
----                local group_name = criteria:sub(7)
----                if minetest.get_item_group(item_name, group_name) > 0 then
----                    match = true
----                end
----
----            -- 2. Support Custom Filter Functions
----            elseif type(criteria) == "function" then
----                if criteria(stack) then match = true end
----
----            -- 3. Standard Item Name match
----            elseif criteria == item_name then
----                match = true
----            end
----
----            if match then
----                -- Handle Infinite (Boolean)
----                if req_value == true then
----                    return ia_dunce.has_room_for(self, item_name)
----                end
----
----                -- Handle Counts (Number)
----                if type(req_value) == "number" then
----                    local current_count = ia_dunce.get_item_count(self, item_name)
----                    if current_count < req_value then
----                        return ia_dunce.has_room_for(self, item_name)
----                    end
----                end
----            end
----        end
----
----        return false
----    end
----
----    local items = self:find_items(20, item_filter)
----    if #items > 0 then
----        local target = items[1]
----        
----        -- IMPORTANT: Set _target_object so pathfinding.lua can track its validity
----        self._target_object = target.object
----        
----        self._target_data = { 
----            type = "item", 
----            object = target.object, 
----            pos = target.pos 
----        }
----        
----        -- This triggers pathfinding.lua's find_path_to
----        self:find_path_to(target.pos)
----        return true
----    end
----    
----    return false
----end
---- ia_pathfinding/scavenge.lua
--
----- Scavenges for items with support for counts, groups, and custom filters.
--function ia_pathfinding.handle_scavenging_helper(self, requirements)
--    if not requirements then return false end
--
--    local item_filter = function(stack)
--        local item_name = stack:get_name()
--
--        for criteria, req_value in pairs(requirements) do
--            local match = false
--
--            if type(criteria) == "string" and criteria:sub(1, 6) == "group:" then
--                local group_name = criteria:sub(7)
--                if minetest.get_item_group(item_name, group_name) > 0 then
--                    match = true
--                end
--            elseif type(criteria) == "function" then
--                if criteria(stack) then match = true end
--            elseif criteria == item_name then
--                match = true
--            end
--
--            if match then
--                if req_value == true then
--                    return ia_dunce.has_room_for(self, item_name)
--                end
--
--                if type(req_value) == "number" then
--                    local current_count = ia_dunce.get_item_count(self, item_name)
--                    if current_count < req_value then
--                        return ia_dunce.has_room_for(self, item_name)
--                    end
--                end
--            end
--        end
--
--        return false
--    end
--
--    local items = self:find_items(20, item_filter)
--    if #items > 0 then
--        local target = items[1]
--        
--        self._target_object = target.object
--        self._target_data = { 
--            type = "item", 
--            object = target.object, 
--            pos = target.pos 
--        }
--        
--        self:find_path_to(target.pos)
--        return true
--    else
--        -- FIX: If no items found, ensure we aren't holding onto old movement intent
--        if not self._current_path then
--            ia_pathfinding.clear_pathing_state(self)
--        end
--    end
--    
--    return false
--end
--function ia_pathfinding.handle_scavenging(self, requirements)
--	if not ia_pathfinding.handle_scavenging_helper(self, requirements) then
--		return false
--	end
--	self:follow_path()
--	return true
--end
-- ia_pathfinding/scavenge.lua
--
----- Internal logic for finding and targeting an item.
--function ia_pathfinding.scavenge_for_item(self, requirements)
--    local item_filter = function(stack)
--        local item_name = stack:get_name()
--        for criteria, req_value in pairs(requirements) do
--            -- [Match logic for groups, functions, and names remains same]
--            -- ...
--            if match then
--                return ia_dunce.has_room_for(self, item_name)
--            end
--        end
--        return false
--    end
--
--    -- Increase search radius to 20 for better discovery
--    local items = self:find_items(20, item_filter)
--    if #items > 0 then
--        local target = items[1]
--        self._target_object = target.object
--        -- Set the path once
--        self:find_path_to(target.pos)
--        return true
--    end
--    return false
--end
--
----- The main Scavenge entry point.
---- Use this in your on_step.
--function ia_pathfinding.handle_scavenging(self, requirements)
--    if not requirements then return false end
--
--    -- 1. Brain: If we don't have a path, look for an item.
--    if ia_pathfinding.is_idle(self) then
--        ia_pathfinding.scavenge_for_item(self, requirements)
--    end
--
--    -- 2. Legs: If we have a path (newly found or existing), WALK.
--    -- This ensures movement continues even after the 'scan' is finished.
--    if not ia_pathfinding.is_idle(self) then
--        self:follow_path()
--        return true
--    end
--
--    return false
--end
-- ia_pathfinding/scavenge.lua

function ia_pathfinding.is_idle(self)
    return self._current_path == nil
end

--- Internal helper to check item requirements.
local function matches_requirement(stack, requirements, self)
    local name = stack:get_name()
    for criteria, val in pairs(requirements) do
        local match = false
        if type(criteria) == "string" and criteria:sub(1,6) == "group:" then
            if minetest.get_item_group(name, criteria:sub(7)) > 0 then match = true end
        elseif type(criteria) == "function" then
            if criteria(stack) then match = true end
        elseif criteria == name then
            match = true
        end

        if match then
            -- Check room/count
            if type(val) == "number" then
                if ia_dunce.get_item_count(self, name) < val then return true end
            else
                return ia_dunce.has_room_for(self, name)
            end
        end
    end
    return false
end

function ia_pathfinding.handle_scavenging(self, requirements)
    if not requirements then return false end

    -- 1. BRAIN: Only look for new items if we aren't already walking to one.
    if ia_pathfinding.is_idle(self) then
        local filter = function(stack) return matches_requirement(stack, requirements, self) end
        local items = self:find_items(20, filter)
        
        if #items > 0 then
            self._target_object = items[1].object
            self:find_path_to(items[1].pos)
        end
    end

    -- 2. LEGS: If we have a path, walk it.
    if not ia_pathfinding.is_idle(self) then
        self:follow_path()
        return true
    end

    return false
end
