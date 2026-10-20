-- =========================================================================
-- YourSkinMod - init.lua (With ui.lua Integration & Live Preview)
-- =========================================================================

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- 1. Include the original ui.lua
local ui = dofile(modpath .. "/ui.lua")

-- 2. Load animation.json for animated skins
local json_path = modpath .. "/animation.json"
local json_file = io.open(json_path, "r")
local skin_animations = {}

if json_file then
    local content = json_file:read("*a")
    json_file:close()
    skin_animations = minetest.parse_json(content) or {}
    minetest.log("action", "[YourSkinMod] animation.json loaded successfully.")
else
    minetest.log("warning", "[YourSkinMod] Could not load animation.json.")
end

-- 3. Combine skins: static skins + animated skins from JSON
local skins = {
    { name = "Luanti", is_animated = false, texture = "luanti.png" },
    { name = "Goose", is_animated = false, texture = "goose.png" },
    { name = "Normal Skin", is_animated = false, texture = "normal-skin.png" }
}

-- Add animated skins from JSON
for skin_name, anim_data in pairs(skin_animations) do
    table.insert(skins, {
        name = skin_name,
        is_animated = true,
        fps = anim_data.fps or 2,
        on_finish = anim_data.on_finish or 1,
        frames = anim_data.frames or {}
    })
end

-- Player states
local player_skin_idx = {}    -- Which skin is currently selected in the menu
local player_skin_rot = {}    -- Rotation angle of the preview
local player_active_skin = {} -- The skin currently equipped in-game
local formspec_open = {}      -- Stores whether the menu is open

-- Helper function: Determine the correct texture for a skin and frame
local function get_skin_texture(skin, frame_idx)
    if not skin then return "character.png" end
    if not skin.is_animated then
        return skin.texture
    else
        local frames = skin.frames
        if frames and #frames > 0 then
            local idx = ((frame_idx - 1) % #frames) + 1
            return frames[idx].file
        end
        return "character.png"
    end
end

-- Helper function: Open / update the menu
local function show_skin_menu(player_name)
    local p_idx = player_skin_idx[player_name] or 1
    if p_idx > #skins then p_idx = 1; player_skin_idx[player_name] = p_idx end
    
    local skin = skins[p_idx]
    local active_state = player_active_skin[player_name]
    local frame_idx = 1
    if active_state and active_state.skin_name == skin.name then
        frame_idx = active_state.frame_index or 1
    end
    
    -- Get the current texture (including animation frame for the preview)
    local current_texture = get_skin_texture(skin, frame_idx)
    
    -- Use ui.lua to build the formspec
    local fs = ui.build_formspec(player_name, skins, player_skin_idx, player_skin_rot, current_texture)
    minetest.show_formspec(player_name, "your_skin:menu", fs)
    formspec_open[player_name] = true
end

-- 4. Globalstep: Runs in the background for player animation and live preview
minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        
        -- Update the equipped skin's animation in-game
        local active = player_active_skin[name]
        if active and active.is_animated then
            active.timer = (active.timer or 0) + dtime
            local skin_data = active.skin_data
            local current_frame_data = skin_data.frames[active.frame_index]
            local duration = current_frame_data and current_frame_data.duration or (1.0 / (skin_data.fps or 2))
            
            if active.timer >= duration then
                active.timer = 0
                active.frame_index = active.frame_index + 1
                if active.frame_index > #skin_data.frames then
                    active.frame_index = skin_data.on_finish or 1
                end
                local tex = skin_data.frames[active.frame_index].file
                player:set_properties({ textures = { tex } })
            end
        end
        
        -- If the menu is open, update it so the preview animates smoothly
        if formspec_open[name] then
            show_skin_menu(name)
        end
    end
end)

-- 5. Handle button clicks and menu controls
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "your_skin:menu" then return end
    local name = player:get_player_name()
    
    player_skin_idx[name] = player_skin_idx[name] or 1
    player_skin_rot[name] = player_skin_rot[name] or 0
    
    -- "X" button or close
    if fields.go_home or fields.quit then
        formspec_open[name] = false
        minetest.close_formspec(name, "your_skin:menu")
        return
    end
    
    -- <- Previous Skin
    if fields.prev_skin then
        player_skin_idx[name] = player_skin_idx[name] - 1
        if player_skin_idx[name] < 1 then
            player_skin_idx[name] = #skins
        end
        show_skin_menu(name)
        return
    end
    
    -- Next -> Skin
    if fields.next_skin then
        player_skin_idx[name] = player_skin_idx[name] + 1
        if player_skin_idx[name] > #skins then
            player_skin_idx[name] = 1
        end
        show_skin_menu(name)
        return
    end
    
    -- Select Skin (Auswählen)
    if fields.apply_skin then
        local idx = player_skin_idx[name]
        local skin = skins[idx]
        
        if skin.is_animated then
            player_active_skin[name] = {
                is_animated = true,
                skin_name = skin.name,
                skin_data = skin,
                frame_index = 1,
                timer = 0
            }
            local tex = skin.frames[1].file
            player:set_properties({ textures = { tex } })
            minetest.chat_send_player(name, "Animated skin selected: " .. skin.name)
        else
            player_active_skin[name] = { is_animated = false }
            player:set_properties({ textures = { skin.texture } })
            minetest.chat_send_player(name, "Skin selected: " .. skin.name)
        end
        formspec_open[name] = false
        minetest.close_formspec(name, "your_skin:menu")
        return
    end
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    player_skin_idx[name] = nil
    player_skin_rot[name] = nil
    player_active_skin[name] = nil
    formspec_open[name] = nil
end)

-- 6. Sfinv integration (adds the "Skins" tab to the inventory)
if minetest.get_modpath("sfinv") then
    sfinv.register_page("your_skin:skin_page", {
        title = "Skins",
        get = function(self, player, context)
            local name = player:get_player_name()
            local p_idx = player_skin_idx[name] or 1
            local skin = skins[p_idx] or skins[1]
            local active_state = player_active_skin[name]
            local frame_idx = (active_state and active_state.skin_name == skin.name) and (active_state.frame_index or 1) or 1
            local current_texture = get_skin_texture(skin, frame_idx)
            
            formspec_open[name] = true
            return ui.build_formspec(name, skins, player_skin_idx, player_skin_rot, current_texture)
        end,
        on_player_receive_fields = function(self, player, context, fields)
            -- Handled by the global handler
        end,
    })
end
