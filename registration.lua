-- ia_pathfinding/registration.lua

function ia_pathfinding.register_pathfinding_entity(name, definition)
    -- CHANGE: Standardized all whitespace to standard ASCII spaces to fix syntax error
    minetest.log('action', '[ia_pathfinding] Registering: ' .. name)
    
    local final_def        = table.copy(definition)
    local user_on_activate = definition.on_activate
    local user_on_step     = definition.on_step

    -- Injected On Step: The Brain Tick
    final_def.on_step = function(self, dtime)
	assert(self)
	assert(self.object)
	assert(self:get_hp() > 0)
	local pos     = self:get_pos()
	if pos == nil then
		minetest.log('ia_humanoid.on_step() no pos')
		return
	end
	assert(pos ~= nil)
        -- 1. Process Pathfinding Coroutines
        --if ia_pathfinding.process_pathfinding then
            ia_pathfinding.process_pathfinding(self)
        --end

	local hp = self:get_hp()
	--minetest.log('ia_pathfinding.on_step() '..self:get_player_name()..' hp='..hp)
	if hp <= 0 then
            return
        end

        -- 2. Run the user's specific mob logic (on_step from ia_mob)
        if user_on_step then
            user_on_step(self, dtime)
        end
    end

    -- TODO ensure that this doesn't run twice
    -- We must override the on_activate that ia_dunce would have set
    final_def.on_activate = function(self, staticdata, dtime_s)
        -- 1. Initialize Dunce (Base Layer)
        --ia_dunce.init_instance(self)
        assert(self:is_player() == true)
        
        -- 2. Initialize Pathfinding (This Layer - provides handle_scavenging, etc.)
        ia_pathfinding.init_instance(self)
        assert(self:is_player() == true)
        
        -- 3. Run original mob logic
        if user_on_activate then
            user_on_activate(self, staticdata, dtime_s)
        end
        assert(self:is_player() == true)
    end

    -- Delegate the actual registration to ia_dunce
    -- ia_dunce will then delegate to ia_humanoid
    ia_dunce.register_dunce_entity(name, final_def)
end
