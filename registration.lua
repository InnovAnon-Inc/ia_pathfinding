-- ia_pathfinding/registration.lua

function ia_pathfinding.register_pathfinding_entity(name, definition)
    -- CHANGE: Standardized all whitespace to standard ASCII spaces to fix syntax error
    minetest.log('action', '[ia_pathfinding] Registering: ' .. name)
    
    local user_on_activate = definition.on_activate
    local user_on_step = definition.on_step

    -- Injected On Step: The Brain Tick
    definition.on_step = function(self, dtime)
        -- 1. Process Pathfinding Coroutines
        if ia_pathfinding.process_pathfinding then
            ia_pathfinding.process_pathfinding(self)
        end

        -- 2. Run the user's specific mob logic (on_step from ia_mob)
        if user_on_step then
            user_on_step(self, dtime)
        end
    end

    -- We must override the on_activate that ia_dunce would have set
    definition.on_activate = function(self, staticdata, dtime_s)
        -- 1. Initialize Dunce (Base Layer)
        ia_dunce.init_instance(self)
        
        -- 2. Initialize Pathfinding (This Layer - provides handle_scavenging, etc.)
        ia_pathfinding.init_instance(self)
        
        -- 3. Run original mob logic
        if user_on_activate then
            user_on_activate(self, staticdata, dtime_s)
        end
    end

    -- Delegate the actual registration to ia_dunce
    -- ia_dunce will then delegate to ia_humanoid
    ia_dunce.register_dunce_entity(name, definition)
end
