-- ia_pathfinding/scavenge.lua

--- Scavenges for items with support for counts, groups, and custom filters.
-- @param requirements Table like { ["group:armor"] = true, ["default:stone"] = 8 }
function ia_pathfinding.handle_scavenging(self, requirements) -- FIXME probably need different scavenge_XXX methods
	minetest.log('ia_pathfinding.handle_scavenging()')
    if not requirements then return false end

    local item_filter = function(stack)
        local item_name = stack:get_name()

        -- Check every requirement in the list
        for criteria, req_value in pairs(requirements) do
            local match = false

            -- 1. Support Groups (e.g., "group:armor")
            if type(criteria) == "string" and criteria:sub(1, 6) == "group:" then
                local group_name = criteria:sub(7)
                if minetest.get_item_group(item_name, group_name) > 0 then
                    match = true
                end

            -- 2. Support Custom Filter Functions
            elseif type(criteria) == "function" then
                if criteria(stack) then match = true end

            -- 3. Standard Item Name match
            elseif criteria == item_name then
                match = true
            end

            -- If we found a match for this specific requirement...
            if match then
                -- Handle Infinite (Boolean)
                if req_value == true then
                    return ia_dunce.has_room_for(self, item_name)
                end

                -- Handle Counts (Number)
                -- Note: Count-tracking for groups is tricky; we check the specific item count
                if type(req_value) == "number" then
                    local current_count = ia_dunce.get_item_count(self, item_name)
                    if current_count < req_value then
                        return ia_dunce.has_room_for(self, item_name)
                    end
                end
            end
        end

        return false
    end

    local items = self:find_items(10, item_filter)
    if #items > 0 then
        local target = items[1]
	assert(target.object ~= nil)
	assert(target.pos ~= nil)
        self._target_data = { 
            type = "item", 
            object = target.object, 
            pos = target.pos 
        }
        self:find_path_to(target.pos)
        return true
    end
    
    return false
end
