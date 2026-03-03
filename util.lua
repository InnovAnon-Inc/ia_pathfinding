-- ia_pathfinding/util.lua

local function log_trace(msg)
    minetest.log('info', '[ia_pathfinding][TRACE] ' .. msg)
end

function ia_pathfinding.log_stack(self)
    if not self._task_stack or #self._task_stack == 0 then
        log_trace("Stack is EMPTY")
        return
    end
    local report = "Task Stack: "
    for i, task in ipairs(self._task_stack) do
        report = report .. string.format("[%d: %s at %s] ", i, task.type, minetest.pos_to_string(vector.round(task.pos)))
    end
    log_trace(report)
end

function ia_pathfinding.format_star_path(flat_path)
    if not flat_path or #flat_path == 0 then return nil end

    local path = {}
    for i = #flat_path - 2, 1, -3 do
        table.insert(path, {
            x = flat_path[i],
            y = flat_path[i+1],
            z = flat_path[i+2]
        })
    end

    if #path > 1 then
        table.remove(path, 1)
    end

    return path
end

function ia_pathfinding.get_search_settings(self)
    return {
        max_iterations = 1024,
        climb = false, -- Requirement: Bridges handle verticality
    }
end

function ia_pathfinding.get_current_task(self)
    if not self._task_stack or #self._task_stack == 0 then return nil end
    return self._task_stack[#self._task_stack]
end

function ia_pathfinding.clear_pathing_state(self)
    self._current_path = nil
    self._path_index = 1
    self._path_target = nil
    self._target_object = nil
    self._target_data = nil
    self._task_stack = {}
end

function ia_pathfinding.push_task(self, pos, task_type, metadata)
    self._task_stack = self._task_stack or {}
    local rounded_pos = vector.round(pos)

    -- Check if this task is already the top of the stack to prevent recursion loops
    local top = ia_pathfinding.get_current_task(self)
    if top and top.type == task_type and vector.equals(vector.round(top.pos), rounded_pos) then
        return
    end

    table.insert(self._task_stack, {
        pos = rounded_pos,
        type = task_type or "move",
        meta = metadata or {}
    })

    log_trace(string.format("PUSH: %s at %s", task_type, minetest.pos_to_string(rounded_pos)))
    ia_pathfinding.log_stack(self)
end

function ia_pathfinding.pop_task(self)
    if self._task_stack and #self._task_stack > 0 then
        local task = table.remove(self._task_stack)
        log_trace(string.format("POP: %s at %s. New Top: %s",
            task.type,
            minetest.pos_to_string(task.pos),
            (#self._task_stack > 0 and self._task_stack[#self._task_stack].type or "NONE")))
        return task
    end
    return nil
end

function ia_pathfinding.on_reach_destination(self)
    local completed_task = ia_pathfinding.pop_task(self)
    ia_dunce.stop(self)

    if not completed_task or completed_task.type == "goal" then
        log_trace("Final goal reached.")
        ia_pathfinding.clear_pathing_state(self)
    end

    self._current_path = nil
end
