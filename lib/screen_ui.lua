-- lib/screen_ui.lua v0.7
-- CHANGELOG v0.7:
-- 1. UI: Cables dibujados por encima de los nodos. Respiración añadida a los nodos en pantalla.
-- 2. UI: Textos descriptivos en menús (nombre real del parámetro).
-- 3. CONTROL: Resolución científica para encoders (Hz absolutos) y Attenuverters.
-- 4. FIX: Botones K2/K3 arreglados usando params.lookup.

local ScreenUI = {}

local MenuDef = {
    [1] = { A = { title = "1004-T (A) MIXER", e1 = "m1_mix_sine", e2 = "m1_mix_tri", e3 = "m1_mix_saw", e4 = "m1_mix_pulse" }, B = { title = "1004-T (A) CORE", e1 = "m1_pwm", e2 = "m1_tune", e3 = "m1_fine", k3 = "m1_range" } },[2] = { A = { title = "1004-T (B) MIXER", e1 = "m2_mix_sine", e2 = "m2_mix_tri", e3 = "m2_mix_saw", e4 = "m2_mix_pulse" }, B = { title = "1004-T (B) CORE", e1 = "m2_pwm", e2 = "m2_tune", e3 = "m2_fine", k3 = "m2_range" } },
    [3] = { A = { title = "1023 - OSC 1", e1 = "m3_pwm1", e2 = "m3_tune1", e3 = "m3_morph1", k3 = "m3_range1" }, B = { title = "1023 - OSC 2", e1 = "m3_pwm2", e2 = "m3_tune2", e3 = "m3_morph2", k3 = "m3_range2" } },
    [4] = { A = { title = "1016 NOISE", e1 = "m4_slow_rate", e2 = "m4_tilt1", e3 = "m4_tilt2", k2 = "m4_type1", k3 = "m4_type2" }, B = { title = "1036 S&H", e1 = "m4_clk_rate", e2 = "m4_prob_skew", e3 = "m4_glide" } },
    [5] = { A = { title = "1005 STATE", e1 = "m5_mod_gain", e2 = "m5_unmod_gain", e3 = "m5_drive", k2 = "m5_state" }, B = { title = "1005 VCA", e1 = "m5_vca_base", e2 = "m5_vca_resp", e3 = "m5_xfade", k2 = "m5_state" } },
    [6] = { A = { title = "1047 (A) FILTER", e1 = "m6_cutoff", e2 = "m6_fine", e3 = "m6_q", e4 = "m6_jfet" }, B = { title = "1047 (A) NOTCH", e1 = "m6_notch", e2 = "m6_final_q", e3 = "m6_out_lvl" } },
    [7] = { A = { title = "1047 (B) FILTER", e1 = "m7_cutoff", e2 = "m7_fine", e3 = "m7_q", e4 = "m7_jfet" }, B = { title = "1047 (B) NOTCH", e1 = "m7_notch", e2 = "m7_final_q", e3 = "m7_out_lvl" } },
    [8] = { A = { title = "NEXUS MASTER", e1 = "m8_cut_l", e2 = "m8_cut_r", e3 = "m8_res", e4 = "m8_drive", k2 = "m8_filt_byp", k3 = "m8_adc_mon" }, B = { title = "NEXUS TAPE", e1 = "m8_tape_time", e2 = "m8_tape_fb", e3 = "m8_tape_mix", e4 = "m8_wow", k2 = "m8_tape_sat", k3 = "m8_tape_mute" } }
}

local function grid_to_screen(x, y)
    return (x - 1) * 8 + 4, (y - 1) * 8 + 4
end

local function get_p_name(id)
    local idx = params.lookup[id]
    return idx and params.params[idx].name or id
end

function ScreenUI.draw_idle(G)
    for x = 1, 16 do
        for y = 1, 8 do
            local node = G.grid_map[x][y]
            local is_menu = (y == 4)
            if (node and node.type ~= "dummy") or is_menu then
                local px, py = grid_to_screen(x, y)
                local is_even = (math.ceil(x / 2) % 2 == 0)
                local base_bright = is_even and 4 or 2
                
                if node and G.node_levels and G.node_levels[node.id] then
                    local audio_mod = math.floor(util.clamp(G.node_levels[node.id] * 10, 0, 6))
                    base_bright = util.clamp(base_bright + audio_mod, 0, 14)
                end
                
                screen.level(base_bright)
                screen.rect(px - 2, py - 2, 4, 4)
                screen.fill()
            end
        end
    end

    screen.aa(1)
    screen.level(10)
    if G.patch then
        for src_id, dests in pairs(G.patch) do
            for dst_id, data in pairs(dests) do
                if data.active then
                    local src_node = G.nodes[src_id]
                    local dst_node = G.nodes[dst_id]
                    if src_node and dst_node and src_node.type ~= "dummy" and dst_node.type ~= "dummy" then
                        local sx1, sy1 = grid_to_screen(src_node.x, src_node.y)
                        local sx2, sy2 = grid_to_screen(dst_node.x, dst_node.y)
                        screen.move(sx1, sy1)
                        local cx = (sx1 + sx2) / 2
                        local cy = math.max(sy1, sy2) + 10 
                        screen.curve(sx1, sy1, cx, cy, sx2, sy2)
                        screen.stroke()
                    end
                end
            end
        end
    end
    screen.aa(0)
    
    screen.level(15)
    screen.move(2, 62)
    screen.text("ELIANNE")
    screen.move(126, 62)
    screen.text_right("ARP 2500")
end

function ScreenUI.draw_node_menu(G)
    if not G.focus.node_x or not G.focus.node_y then return end
    local node = G.grid_map[G.focus.node_x][G.focus.node_y]
    if not node or node.type == "dummy" then return end
    
    screen.level(15)
    screen.move(64, 10)
    screen.text_center("MOD " .. node.module .. ": " .. node.name)
    
    screen.level(4)
    screen.move(64, 20)
    screen.text_center(node.type == "in" and "INPUT ATTENUVERTER" or "OUTPUT LEVEL")
    
    screen.level(15)
    local val_px = (node.level or 0) * 50
    if val_px > 0 then
        screen.rect(64, 32, val_px, 6)
    else
        screen.rect(64 + val_px, 32, math.abs(val_px), 6)
    end
    screen.fill()
    
    screen.move(10, 55)
    screen.text("E2 Level: " .. string.format("%.2f", node.level or 0))
    
    if node.module == 8 and node.type == "in" then
        screen.move(118, 55)
        screen.text_right("E3 Pan: " .. string.format("%.2f", node.pan or 0))
    end
end

function ScreenUI.draw_module_menu(G)
    if not G.focus.module_id or not G.focus.page then return end
    local def = MenuDef[G.focus.module_id][G.focus.page]
    if not def then return end

    screen.level(15)
    screen.move(64, 10)
    screen.text_center(def.title)
    screen.line(10, 14, 118, 14)
    screen.stroke()

    screen.level(4)
    if def.e1 then screen.move(2, 30); screen.text("E1 " .. get_p_name(def.e1) .. ": " .. params:string(def.e1)) end
    if def.e2 then screen.move(2, 45); screen.text("E2 " .. get_p_name(def.e2) .. ": " .. params:string(def.e2)) end
    if def.e3 then screen.move(2, 60); screen.text("E3 " .. get_p_name(def.e3) .. ": " .. params:string(def.e3)) end
    if def.e4 then screen.move(70, 60); screen.text("E4 " .. get_p_name(def.e4) .. ": " .. params:string(def.e4)) end

    screen.level(4)
    if def.k2 then screen.move(126, 30); screen.text_right("K2: " .. params:string(def.k2)) end
    if def.k3 then screen.move(126, 45); screen.text_right("K3: " .. params:string(def.k3)) end
end

function ScreenUI.draw(G)
    if G.focus.state == "idle" or G.focus.state == "patching" then
        ScreenUI.draw_idle(G)
    elseif G.focus.state == "in" or G.focus.state == "out" then
        ScreenUI.draw_node_menu(G)
    elseif G.focus.state == "menu" then
        ScreenUI.draw_module_menu(G)
    end
end

local last_enc_time = 0

function ScreenUI.enc(G, n, d)
    local now = util.time()
    local dt = now - last_enc_time
    last_enc_time = now
    
    local accel = 1.0
    if dt < 0.05 then accel = 5.0 
    elseif dt > 0.15 then accel = 0.1 end 

    if G.focus.state == "in" or G.focus.state == "out" then
        if not G.focus.node_x or not G.focus.node_y then return end
        local node = G.grid_map[G.focus.node_x][G.focus.node_y]
        if not node or node.type == "dummy" then return end
        
        local Matrix = include('lib/matrix') 
        if n == 2 then
            local step = (accel < 1) and 0.005 or 0.05
            node.level = util.clamp((node.level or 0) + (d * step), -1.0, 1.0)
            Matrix.update_node_params(node)
        elseif n == 3 and node.module == 8 and node.type == "in" then
            local step = (accel < 1) and 0.005 or 0.05
            node.pan = util.clamp((node.pan or 0) + (d * step), -1.0, 1.0)
            Matrix.update_node_params(node)
        end
    elseif G.focus.state == "menu" then
        if not G.focus.module_id or not G.focus.page then return end
        local def = MenuDef[G.focus.module_id][G.focus.page]
        if not def then return end
        
        local target_param = nil
        if n == 1 then target_param = def.e1
        elseif n == 2 then target_param = def.e2
        elseif n == 3 then target_param = def.e3
        elseif n == 4 then target_param = def.e4 end 
        
        if target_param then
            if string.find(target_param, "tune") or string.find(target_param, "cutoff") then
                local current = params:get(target_param)
                local step = 0.1
                if accel > 1 then step = 10.0 end
                if accel < 1 then step = 0.01 end
                params:set(target_param, util.clamp(current + (d * step), 0.01, 20000.0))
            elseif string.find(target_param, "fine") then
                local current = params:get(target_param)
                local step = (accel < 1) and 0.001 or 0.01
                params:set(target_param, util.clamp(current + (d * step), -5.0, 5.0))
            else
                params:delta(target_param, d * accel)
            end
        end
    end
end

function ScreenUI.key(G, n, z)
    if z == 1 and G.focus.state == "menu" then
        if not G.focus.module_id or not G.focus.page then return end
        local def = MenuDef[G.focus.module_id][G.focus.page]
        if not def then return end
        
        local target_param = nil
        if n == 2 then target_param = def.k2
        elseif n == 3 then target_param = def.k3 end
        
        if target_param then
            local p_idx = params.lookup[target_param]
            if p_idx then
                local p = params.params[p_idx]
                if p and p.options then
                    local current = params:get(target_param)
                    local next_val = current + 1
                    if next_val > #p.options then next_val = 1 end
                    params:set(target_param, next_val)
                end
            end
        end
    end
end

return ScreenUI
