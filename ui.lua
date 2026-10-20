#-- Standard UI Theme for Your Skin V2
local ui = {}

function ui.build_formspec(player_name, skins, player_skin_idx, player_skin_rot, current_texture)
    local idx = player_skin_idx[player_name] or 1
    local rot = player_skin_rot[player_name] or 0

    -- Formspec without rotation buttons, automatic rotation enabled
    local formspec = "size[8,9]" ..
        "label[2.8,0.3;=== Skin Gallery (" .. idx .. "/" .. #skins .. ") ===]" ..
        "button[7.1,0.2;0.7,0.7;go_home;X]" ..
        "model[2,0.8;4,4.5;skin_preview;character.b3d;" .. current_texture .. ";0," .. rot .. ";true;true;0,0]" ..
        "button[1,6.5;2,0.8;prev_skin;<- Previous]" ..
        "button[5,6.5;2,0.8;next_skin;Next ->]" ..
        "button[2.5,7.5;3,0.8;apply_skin;Select Skin]"

    return formspec
end

return ui
