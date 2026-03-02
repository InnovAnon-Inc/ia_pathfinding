-- ia_pathfinding/doors.lua

--- Checks if the current goal is blocked and pushes a door detour if necessary.
-- @param self The entity instance
-- @param pos The current position of the entity
-- @return boolean True if a detour was pushed
function ia_pathfinding.handle_door_detour(self, pos)
    local doors = ia_dunce.find_nearby_doors(pos, 8)
    if doors and #doors > 0 then
        minetest.log('info', "[ia_pathfinding] Door detour detected at " .. minetest.pos_to_string(doors[1].pos))
        ia_pathfinding.push_task(self, doors[1].pos, "door")
        return true
    end
    return false
end

--- Handles the logic for crossing the threshold once at a door.
-- @param self The entity instance
function ia_pathfinding.traverse_doorway(self)
    -- 1. Open the door via Dunce
    ia_dunce.handle_door_front(self, "open")

    -- 2. Calculate the "Point B" across the threshold
    local my_pos = self.object:get_pos()
    local dir = self.object:get_yaw()
    -- Standard Minetest yaw to vector conversion
    local forward = {x = -math.sin(dir), y = 0, z = math.cos(dir)}
    local pass_through_point = vector.add(my_pos, vector.multiply(forward, 2))

    minetest.log('info', "[ia_pathfinding] Door opened. Pushing traverse task to " .. minetest.pos_to_string(pass_through_point))
    
    -- 3. Push the traverse task to move the mob physically through the door
    ia_pathfinding.push_task(self, pass_through_point, "traverse")
end
