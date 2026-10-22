-- =========================================================================
-- YourSkinMod - init.lua (With Dynamic Texture Scanning & Persistence)
-- =========================================================================

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- 1. Include the UI helper module (Change to ui_retro.lua if you use the retro style)
local ui = dofile(modpath .. "/ui.lua")

-- Path for saving active skins per player in the world directory (Mod Security compliant)
local worldpath = minetest.get_worldpath()
local save_path = worldpath and (worldpath .. "/skins_data.json") or nil
local saved_player_skins = {}

-- Helper function: Load saved skin choices from JSON file
local function load_saved_skins()
    if not save_path then return end
    local file = io.open(save_path, "r")
    if file then
        local content = file:read("*a")
        file:close()
        saved_player_skins = minetest.parse_json(content) or {}
        minetest.log("action", "[YourSkinMod] Player skin configurations loaded.")
    end
end

-- Helper function: Save skin choices to JSON file
local function save_player_skins()
    if not save_path then return end
    local file = io.open(save_path, "w")
    if file then
        file:write(minetest.write_json(saved_player_skins, true))
        file:close()
    else
        minetest.log("error", "[YourSkinMod] Could not save skin configurations!")
    end
end

load_saved_skins()

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

-- 3. Combine skins: Dynamically scan textures directory + animated skins from JSON
local skins = {}
local textures_path = modpath .. "/textures"
local dir_list = minetest.get_dir_list(textures_path, false)

if dir_list then
    for _, filename in ipairs(dir_list) do
        -- Check if it's a .png file and does NOT contain an underscore "_" (underscores are reserved for animation frames)
        if filename:match("%.png$") and not filename:find("_") then
            local base_name = filename:gsub("%.png$", "")
            table.insert(skins, {
                name = base_name,
                is_animated = false,
                texture = filename
            })
        end
    end
else
    minetest.log("warning", "[YourSkinMod] Could not read textures directory.")
end

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

-- Fallback: If no static or animated skins were found at all, insert default game skin
if #skins == 0 then
    table.insert(skins, {
        name = "Default",
        is_animated = false,
        texture = "character.png"
    })
    minetest.log("action", "[YourSkinMod] No custom skins found. Using default character skin as fallback.")
end
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

-- Helper function: Find skin definition by name
local function find_skin_by_name(skin_name)
    for idx, skin in ipairs(skins) do
        if skin.name == skin_name then
            return skin, idx
        end
    end
    return nil, nil
end

-- Player states
local player_skin_idx = {}    -- Selected skin index in the menu
local player_skin_rot = {}    -- Rotation angle of the preview
local player_active_skin = {} -- Skin currently equipped in-game
local formspec_open = {}      -- Tracks open menus

-- Preview animation states
local player_preview_frame = {}
local player_preview_timer = {}
local player_last_skin_idx = {}

-- Helper function: Determine texture for a skin and frame
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

-- Helper function: Apply a skin to a player
local function apply_skin_to_player(player, skin)
    local name = player:get_player_name()
    if not skin then
        -- Reset to default game skin
        player_active_skin[name] = { is_animated = false }
        saved_player_skins[name] = nil
        save_player_skins()
        player:set_properties({ textures = { "character.png" } })
        return
    end

    saved_player_skins[name] = skin.name
    save_player_skins()

    if skin.is_animated then
        player_active_skin[name] = {
            is_animated = true,
            skin_name = skin.name,
            skin_data = skin,
            frame_index = 1,
            timer = 0
        }
        local tex = skin.frames[1] and skin.frames[1].file or "character.png"
        player:set_properties({ textures = { tex } })
    else
        player_active_skin[name] = { is_animated = false }
        player:set_properties({ textures = { skin.texture } })
    end
end

-- Helper function: Open / update the menu
local function show_skin_menu(player_name)
    local p_idx = player_skin_idx[player_name] or 1
    if p_idx > #skins then p_idx = 1; player_skin_idx[player_name] = p_idx end
    
    local skin = skins[p_idx]
    
    -- Reset preview frame when skin selection changes
    if player_last_skin_idx[player_name] ~= p_idx then
        player_last_skin_idx[player_name] = p_idx
        player_preview_frame[player_name] = 1
        player_preview_timer[player_name] = 0
    end
    
    local frame_idx = skin.is_animated and (player_preview_frame[player_name] or 1) or 1
    local current_texture = get_skin_texture(skin, frame_idx)
    
    -- Build formspec using ui.lua
    local fs = ui.build_formspec(player_name, skins, player_skin_idx, player_skin_rot, current_texture)
    minetest.show_formspec(player_name, "your_skin:menu", fs)
    formspec_open[player_name] = true
end

-- 4. Automatically load saved skin when player joins
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local saved_skin_name = saved_player_skins[name]
    if saved_skin_name then
        local skin, idx = find_skin_by_name(saved_skin_name)
        if skin then
            player_skin_idx[name] = idx
            apply_skin_to_player(player, skin)
        end
    end
end)

-- 5. Globalstep: Handles live preview and active player animations
minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        
        -- Update active in-game animated skin
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
        
        -- Update preview animation if menu is open
        if formspec_open[name] then
            local p_idx = player_skin_idx[name] or 1
            local skin = skins[p_idx]
            if skin and skin.is_animated then
                player_preview_timer[name] = (player_preview_timer[name] or 0) + dtime
                local frames = skin.frames
                local current_frame_data = frames[player_preview_frame[name] or 1]
                local duration = current_frame_data and current_frame_data.duration or (1.0 / (skin.fps or 2))
                
                if player_preview_timer[name] >= duration then
                    player_preview_timer[name] = 0
                    player_preview_frame[name] = (player_preview_frame[name] or 1) + 1
                    if player_preview_frame[name] > #frames then
                        player_preview_frame[name] = skin.on_finish or 1
                    end
                end
            end
            show_skin_menu(name)
        end
    end
end)

-- 6. Handle UI events and buttons
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "your_skin:menu" then return end
    local name = player:get_player_name()
    
    player_skin_idx[name] = player_skin_idx[name] or 1
    player_skin_rot[name] = player_skin_rot[name] or 0
    
    -- Close button / return to homepage
    if fields.go_home or fields.quit then
        formspec_open[name] = false
        minetest.close_formspec(name, "your_skin:menu")
        if minetest.get_modpath("sfinv") then
            sfinv.set_page(player, sfinv.get_homepage_name(player))
        end
        return
    end
    
    -- Previous Skin
    if fields.prev_skin then
        player_skin_idx[name] = player_skin_idx[name] - 1
        if player_skin_idx[name] < 1 then
            player_skin_idx[name] = #skins
        end
        show_skin_menu(name)
        return
    end
    
    -- Next Skin
    if fields.next_skin then
        player_skin_idx[name] = player_skin_idx[name] + 1
        if player_skin_idx[name] > #skins then
            player_skin_idx[name] = 1
        end
        show_skin_menu(name)
        return
    end
    
    -- Apply selected skin
    if fields.apply_skin then
        local idx = player_skin_idx[name]
        local skin = skins[idx]
        apply_skin_to_player(player, skin)
        minetest.chat_send_player(name, "Skin applied: " .. skin.name)
        
        formspec_open[name] = false
        minetest.close_formspec(name, "your_skin:menu")
        if minetest.get_modpath("sfinv") then
            sfinv.set_page(player, sfinv.get_homepage_name(player))
        end
        return
    end

    -- Reset skin to default game character skin
    if fields.reset_skin then
        apply_skin_to_player(player, nil)
        minetest.chat_send_player(name, "Skin reset to default.")
        
        formspec_open[name] = false
        minetest.close_formspec(name, "your_skin:menu")
        if minetest.get_modpath("sfinv") then
            sfinv.set_page(player, sfinv.get_homepage_name(player))
        end
        return
    end
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    player_skin_idx[name] = nil
    player_skin_rot[name] = nil
    player_active_skin[name] = nil
    formspec_open[name] = nil
    player_preview_frame[name] = nil
    player_preview_timer[name] = nil
    player_last_skin_idx[name] = nil
end)

-- 7. Sfinv tab integration
if minetest.get_modpath("sfinv") then
    sfinv.register_page("your_skin:skin_page", {
        title = "Skins",
        get = function(self, player, context)
            local name = player:get_player_name()
            local p_idx = player_skin_idx[name] or 1
            local skin = skins[p_idx] or skins[1]
            
            if player_last_skin_idx[name] ~= p_idx then
                player_last_skin_idx[name] = p_idx
                player_preview_frame[name] = 1
                player_preview_timer[name] = 0
            end
            
            local frame_idx = skin.is_animated and (player_preview_frame[name] or 1) or 1
            local current_texture = get_skin_texture(skin, frame_idx)
            
            formspec_open[name] = true
            return ui.build_formspec(name, skins, player_skin_idx, player_skin_rot, current_texture)
        end,
        on_player_receive_fields = function(self, player, context, fields)
            -- Handled in register_on_player_receive_fields
        end,
    })
end 
