local modpath = minetest.get_modpath("your_skin_v2")
local texture_path = modpath .. "/textures"
local files = minetest.get_dir_list(texture_path, false) or {}

local skins = {}
for _, file in ipairs(files) do
    if file:sub(-4):lower() == ".png" then
        table.insert(skins, file)
    end
end
table.sort(skins)

if #skins == 0 then
    skins = {"character.png"}
end

local player_skin_idx = {}
local player_skin_rot = {}

-- Fester Speicherplatz im Welt-Ordner (mod_storage/your_skin_v2)
local storage = minetest.get_mod_storage()

local function build_formspec(player_name)
    local idx = player_skin_idx[player_name] or 1
    local current_skin = skins[idx] or skins[1]

    -- "false;true" aktiviert die automatische Drehung um die Y-Achse
    local formspec = "size[8,9]" ..
        "label[2.8,0.3;=== Skin Galerie (" .. idx .. "/" .. #skins .. ") ===]" ..
        "button[7.1,0.2;0.7,0.7;go_home;X]" ..
        "model[2,0.8;4,4.5;skin_preview;character.b3d;" .. current_skin .. ";0,0;false;true;0,0]" ..
        "button[1,6.5;2,0.8;prev_skin;<- Vorheriger]" ..
        "button[5,6.5;2,0.8;next_skin;Nächster ->]" ..
        "button[2.5,7.5;3,0.8;apply_skin;Skin Auswählen]"

    return formspec
end

local function render_page(context, content)
    if sfinv and sfinv.make_page then
        return sfinv.make_page(context, content)
    end
    return content
end

local function apply_player_skin(player, skin_name)
    if not player or not skin_name then return end
    player:set_properties({
        textures = {skin_name}
    })
end

if minetest.get_modpath("sfinv") then
    sfinv.register_page("your_skin_v2:viewer", {
        title = "Skins",
        get = function(self, player, context)
            local name = player:get_player_name()
            return render_page(context, build_formspec(name))
        end,
        on_player_receive_fields = function(self, player, context, fields)
            if fields.quit then
                return
            end

            local name = player:get_player_name()

            -- X-Button gedrückt: Wechselt zurück zum Hauptinventar
            if fields.go_home then
                local home_page = sfinv.get_homepage_name and sfinv.get_homepage_name(player) or "sfinv:crafting"
                sfinv.set_page(player, home_page)
                return
            end

            local idx = player_skin_idx[name] or 1
            local rot = player_skin_rot[name] or 0
            local updated = false

            if fields.next_skin then
                idx = (idx % #skins) + 1
                updated = true
            elseif fields.prev_skin then
                idx = idx - 1
                if idx < 1 then idx = #skins end
                updated = true
            elseif fields.rot_left then
                rot = (rot - 45) % 360
                updated = true
            elseif fields.rot_right then
                rot = (rot + 45) % 360
                updated = true
            elseif fields.apply_skin then
                local chosen_skin = skins[idx]
                apply_player_skin(player, chosen_skin)
                
                -- Speichert "Spielername = Skin.png" im mod_storage
                storage:set_string(name, chosen_skin)

                minetest.chat_send_player(name, "[Your Skin] Skin gewechselt zu: " .. chosen_skin)
                return
            end

            if updated then
                player_skin_idx[name] = idx
                player_skin_rot[name] = rot
                sfinv.set_player_inventory_formspec(player, context)
            end
        end,
    })
end

-- Beim Betreten der Welt den gespeicherten Skin nach 0.2 Sekunden setzen
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local saved_skin = storage:get_string(name)

    if saved_skin and saved_skin ~= "" then
        minetest.after(0.2, function()
            local p = minetest.get_player_by_name(name)
            if p then
                apply_player_skin(p, saved_skin)
            end
        end)

        for i, s in ipairs(skins) do
            if s == saved_skin then
                player_skin_idx[name] = i
                break
            end
        end
    else
        player_skin_idx[name] = 1
    end

    player_skin_rot[name] = 0
end)
