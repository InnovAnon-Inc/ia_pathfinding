-- mods/ia_pathfinding/pathfinding.lua

function ia_pathfinding.clear_pathing_state(self)
    self._current_path = nil
    self._path_index = 1
    -- The stack stores {pos = vector, type = string, metadata = table}
    self._task_stack = {} 
    self._target_object = nil
end

-- Helper to push a new goal onto the stack
function ia_pathfinding.push_task(self, pos, task_type, metadata)
	assert(pos.x ~= nil)
	assert(pos.y ~= nil)
	assert(pos.z ~= nil)
    self._task_stack = self._task_stack or {}
    table.insert(self._task_stack, {
        pos = vector.new(pos),
        type = task_type or "move",
        meta = metadata or {}
    })
end

-- Helper to get the current top-of-stack goal
function ia_pathfinding.get_current_task(self)
    if not self._task_stack or #self._task_stack == 0 then return nil end
    return self._task_stack[#self._task_stack]
end

-- Helper to pop a completed task
function ia_pathfinding.pop_task(self)
    if self._task_stack and #self._task_stack > 0 then
        return table.remove(self._task_stack)
    end
    return nil
end
