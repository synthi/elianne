-- lib/screen_ui.lua v0.8
-- CHANGELOG v0.8:
-- 1. UI: Resolución científica absoluta para encoders (Hz y Attenuverters).
-- 2. UI: Ergonomía invertida (E3=Nivel, E2=Pan). Etiquetas abreviadas y separación de brillo.
-- 3. UI: Idle Screen con encoders activos (Master Vol, VCFs, Tape) y telemetría dinámica.
-- 4. UI: Grid Virtual sincronizado con pulsaciones y resaltado de cables.

local ScreenUI = {}

local MenuDef = {[1] = { A = { title = "1004-P (A) MIXER", e1 = {id="m1_mix_sine", name="SINE"}, e2 = {id="m1_mix_tri", name="TRI"}, e3 = {id="m1_mix_saw", name="SAW"}, e4 = {id="m1_mix_pulse", name="PULSE"} }, B = { title = "1004-P (A) CORE", e1 = {id="m1_pwm", name="PWM"}, e2 = {id="m1_tune", name="TUNE"}, e3 = {id="m1_fine", name="FINE"}, k3 = "m1_range" } },
    [2] = { A = { title = "1004-P (B) MIXER", e1 = {id="m2_mix_sine", name="SINE"}, e2 = {id="m2_mix_tri", name="TRI"}, e3 = {id="m2_mix_saw", name="SAW"}, e4 = {id="m2_mix_pulse", name="PULSE"} }, B = { title = "1004-P (B) CORE", e1 = {id="m2_pwm", name="PWM"}, e2 = {id="m2_tune", name="TUNE"}, e3 = {id="m2_fine", name="FINE"}, k3 = "m2_range" } },
    [3] = { A = { title = "1023 - OSC 1", e1 = {id="m3_pwm1", name="PWM"}, e2 = {id="m3_tune1", name="TUNE"}, e3 = {id="m3_morph1", name="MORPH"}, k3 = "m3_range1" }, B = { title = "1023 - OSC 2", e1 = {id="m3_pwm2", name="PWM"}, e2 = {id="m3_tune2", name="TUNE"}, e3 = {id="m3_morph2", name="MORPH"}, k3 = "m3_range2" } },
    [4] = { A = { title = "1016 NOISE", e1 = {id="m4_slow_rate", name="RATE"}, e2 = {id="m4_tilt1", name="TILT 1"}, e3 = {id="m4_tilt2", name="TILT 2"}, k2 = "m4_type1", k3 = "m4_type2" }, B = { title = "1036 S&H", e1 = {id="m4_clk_rate", name="CLOCK"}, e2 = {id="m4_prob_skew", name="SKEW"}, e3 = {id="m4_glide", name="GLIDE"} } },
    [5] = { A = { title = "1005 STATE", e1 = {id="m5_mod_gain", name="MOD"}, e2 = {id="m5_unmod_gain", name="UNMOD"}, e3 = {id="m5_drive", name="DRIVE"}, k2 = "m5_state" }, B = { title = "1005 VCA", e1 = {id="m5_vca_base", name="BASE"}, e2 = {id="m5_vca_resp", name="RESP"}, e3 = {id="m5_xfade", name="XFADE"}, k2 = "m5_state" } },
    [6] = { A = { title = "1047 (A) FILTER", e1 = {id="m6_cutoff", name="FREQ"}, e2 = {id="m6_fine", name="FINE"}, e3 = {id="m6_q", name="RES"}, e4 = {id="m6_jfet", name="DRIVE"} }, B = { title = "1047 (A) NOTCH", e1 = {id="m6_notch", name="OFS"}, e2 = {id="m6_final_q", name="DECAY"}, e3 = {id="m6_out_lvl", name="LEVEL"} } },
    [7] = { A = { title = "1047 (B) FILTER", e1 = {id="m7_cutoff", name="FREQ"}, e2 = {id="m7_fine", name="FINE"}, e3 = {id="m7_q", name="RES"}, e4 = {id="m7_jfet", name="DRIVE"} }, B = { title = "1047 (B) NOTCH", e1 = {id="m7_notch", name="OFS"}, e2 = {id="m7_final_q", name="DECAY"}, e3 = {id="m7_out_lvl", name="LEVEL"} } },
    [8] = { A = { title = "NEXUS MASTER", e1 = {id="m8_cut_l", name="VCF L"}, e2 = {id="m8_cut_r", name="VCF R"}, e3 = {id="m8_res", name="RES"}, e4 = {id="m8_drive", name="DRIVE"}, k2 = "m8_filt_byp", k3 = "m8_adc_mon" }, B = { title = "NEXUS TAPE", e1 = {id="m8_tape_time", name="TIME"}, e2 = {id="m8_tape_fb", name="FDBK"}, e3 = {id="m8_tape_mix", name="MIX"}, e4 = {id="m8_wow", name="WOW"}, k2 = "m8_tape_sat", k3 = "m8_tape_mute" } }
}

local function grid_to_screen(x, y)
    return (x - 1) * 8 + 4, (y - 1) * 8 + 4
end

local function fmt_hz(v) 
    return v >= 1000 and string.format("%.1fkHz", v/1000) or string.format("%.1fHz", v) 
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
                
                -- Sincronización con Grid Físico (Pulsaciones y Conexiones)
                local is_held = (G.focus.node_x == x and G.focus.node_y == y)
                if is_held then 
                    base_bright = 15 
                elseif G.focus.node_x and G.focus.node_y then
                    local focused_node = G.grid_map[G.focus.node_x][G.focus.node_y]
                    if focused_node and node then
                        if focused_node.type == "out" and node.type == "in" and G.patch[focused_node.id][node.id].active then base_bright = 10 end
                        if focused_node.type == "in" and node.type == "out" and G.patch[node.id][focused_node.id].active then base_bright = 10 end
                    end
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
    
    -- Telemetría Dinámica
    local vol = math.floor(params:get("m8_master_vol") * 100)
    local vcf1 = params:get("m8_cut_l")
    local vcf2 = params:get("m8_cut_r")
    
    screen.level(15)
    screen.move(2, 62); screen.text("VOL: " .. vol .. "%")
    screen.move(64, 62); screen.text_center("VCF1: " .. fmt_hz(vcf1))
    screen.move(126, 62); screen.text_right("VCF2: " .. fmt_hz(vcf2))
end

function ScreenUI.draw_node_menu(G)
    if not G.focus.node_x or not G.focus.node_y then return end
    local node = G.grid_map[G.focus.node_x][G.focus.node_y]
    if not node or node.type == "dummy" then return end
    
    local mod_name = G.module_names and G.module_names[node.module] or ("MOD " .. node.module)
    
    screen.level(15)
    screen.move(64, 10)
    screen.text_center(mod_name .. ": " .. node.name)
    
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
    
    screen.level(4)
    screen.move(10, 55)
    screen.text("E3 Level: ")
    screen.level(15)
    screen.text(string.format("%.2f", node.level or 0))
    
    if node.module == 8 and node.type == "in" then
        local pan_str = string.format("%.2f", node.pan or 0)
        local w = screen.text_extents(pan_str)
        screen.level(15)
        screen.move(126, 55)
        screen.text_right(pan_str)
        screen.level(4)
        screen.move(126 - w - 2, 55)
        screen.text_right("E2 Pan: ")
    end
end

function ScreenUI.draw_module_menu(G)
    if not G.focus.module_id or not G.focus.page then return end
    local def = MenuDef[G.focus.module_id][G.focus.page]
    if not def then return end

    screen.level(15)
    screen.move(64, 10)
    screen.text_center(def.title)

    if def.e1 then 
        screen.level(4); screen.move(2, 30); screen.text("E1 " .. def.e1.name .. ": ")
        screen.level(15); screen.text(params:string(def.e1.id)) 
    end
    if def.e2 then 
        screen.level(4); screen.move(2, 45); screen.text("E2 " .. def.e2.name .. ": ")
        screen.level(15); screen.text(params:string(def.e2.id)) 
    end
    if def.e3 then 
        screen.level(4); screen.move(2, 60); screen.text("E3 " .. def.e3.name .. ": ")
        screen.level(15); screen.text(params:string(def.e3.id)) 
    end
    if def.e4 then 
        screen.level(4); screen.move(70, 60); screen.text("E4 " .. def.e4.name .. ": ")
        screen.level(15); screen.text(params:string(def.e4.id)) 
    end

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

    if G.focus.state == "idle" then
        if n == 1 then 
            params:delta("m8_master_vol", d * 0.01)
        elseif n == 2 then 
            local current = params:get("m8_cut_l")
            local step = (accel < 1) and 0.1 or ((accel > 1) and 100.0 or 10.0)
            params:set("m8_cut_l", util.clamp(current + (d * step), 20.0, 20000.0))
        elseif n == 3 then 
            local current = params:get("m8_cut_r")
            local step = (accel < 1) and 0.1 or ((accel > 1) and 100.0 or 10.0)
            params:set("m8_cut_r", util.clamp(current + (d * step), 20.0, 20000.0))
        elseif n == 4 then 
            params:delta("m8_tape_mix", d * 0.01) 
        end
    elseif G.focus.state == "in" or G.focus.state == "out" then
        if not G.focus.node_x or not G.focus.node_y then return end
        local node = G.grid_map[G.focus.node_x][G.focus.node_y]
        if not node or node.type == "dummy" then return end
        
        local Matrix = include('lib/matrix') 
        if n == 3 then
            node.level = util.clamp((node.level or 0) + (d * 0.01), -1.0, 1.0)
            Matrix.update_node_params(node)
        elseif n == 2 and node.module == 8 and node.type == "in" then
            node.pan = util.clamp((node.pan or 0) + (d * 0.01), -1.0, 1.0)
            Matrix.update_node_params(node)
        end
    elseif G.focus.state == "menu" then
        if not G.focus.module_id or not G.focus.page then return end
        local def = MenuDef[G.focus.module_id][G.focus.page]
        if not def then return end
        
        local target_param = nil
        if n == 1 then target_param = def.e1 and def.e1.id
        elseif n == 2 then target_param = def.e2 and def.e2.id
        elseif n == 3 then target_param = def.e3 and def.e3.id
        elseif n == 4 then target_param = def.e4 and def.e4.id end 
        
        if target_param then
            if string.find(target_param, "tune") or string.find(target_param, "cutoff") then
                local current = params:get(target_param)
                local step = (accel < 1) and 0.1 or ((accel > 1) and 10.0 or 1.0)
                params:set(target_param, util.clamp(current + (d * step), 0.01, 20000.0))
            elseif string.find(target_param, "fine") then
                local current = params:get(target_param)
                local step = (accel < 1) and 0.001 or 0.01
                params:set(target_param, util.clamp(current + (d * step), -5.0, 5.0))
            else
                params:delta(target_param, d * ((accel < 1) and 0.1 or 1.0))
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
