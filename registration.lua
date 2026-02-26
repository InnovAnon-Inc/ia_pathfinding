-- ia_pathfinding/registration.lua

function ia_pathfinding.register_pathfinding_entity(name, definition)
	minetest.log('ia_pathfinding.register_pathfinding_entity()')
    local user_on_activate = definition.on_activate
    local user_on_step = definition.on_step

    -- Injected On Step: This is the "Brain Tick"
    definition.on_step = function(self, dtime)
        -- 1. Process Pathfinding Coroutines (The "Thinking" phase)
        ia_pathfinding.process_pathfinding(self)

        -- 2. Process Appliance/Task Coroutines (The "Working" phase)
        -- We can use the same logic for your appliance.lua yields!

        -- 3. Run the user's logic (Scavenging, etc.)
        if user_on_step then
            user_on_step(self, dtime)
        end
    end

    --definition.on_activate = function(self, staticdata, dtime_s)
    --    ia_dunce.init_instance(self)
    --    if user_on_activate then
    --        user_on_activate(self, staticdata, dtime_s)
    --    end
    --end

    ia_dunce.register_dunce_entity(name, definition)

    minetest.log("action", "[ia_pathfinding] Registered worker entity: " .. name)
end
