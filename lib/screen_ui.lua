-- lib/screen_ui.lua v0.94
-- CHANGELOG v0.94:
-- 1. FORENSIC FIX: Eliminado include('lib/grid_ui') dentro de draw_idle (Bomba de CPU/SD Card).
-- 2. ARCHITECTURE: La pantalla ahora lee G.grid_cache directamente, restaurando la visibilidad de los cuadrados.
-- 3. SAFETY: Protecciones pcall mantenidas para parámetros dinámicos.

local ScreenUI = {}

local MenuDef = {
    [1] = { A = { title = "1004-P (A) MIXER", e1 = {id="m1_mix_sine", name="SINE"}, e2 = {id="m1_mix_tri", name="TRI"}, e3 = {id="m1_mix_saw", name="SAW"}, e4 = {id="m1_mix_pulse", name="PULSE"} }, B = { title = "1004-P (A) CORE", e1 = {id="m1_pwm", name="PWM"}, e2 = {id="m1_tune", name="TUNE"}, e3 = {id="m1_fine", name="FINE"}, k3 = {id="m1_range", name=""} } },
    [2] = { A = { title = "1004-P (B) MIXER", e1 = {id="m2_mix_sine", name="SINE"}, e2 = {id="m2_mix_tri", name="TRI"}, e3 = {id="m2_mix_saw", name="SAW"}, e4 = {id="m2_mix_pulse", name="PULSE"} }, B = { title = "1004-P (B) CORE", e1 = {id="m2_pwm", name="PWM"}, e2 = {id="m2_tune", name="TUNE"}, e3 = {id="m2_fine", name="FINE"}, k3 = {id="m2_range", name=""} } },
    [3] = { A = { title = "1023 - OSC 1", e1 = {id="m3_pwm1", name="PWM"}, e2 = {id="m3_tune1", name="TUNE"}, e3 = {id="m3_morph1", name="MORPH"}, k3 = {id="m3_range1", name=""} }, B = { title = "1023 - OSC 2", e1 = {id="m3_pwm2", name="PWM"}, e2 = {id="m3_tune2", name="TUNE"}, e3 = {id="m3_morph2", name="MORPH"}, k3 = {id="m3_range2", name=""} } },
    [4] = { A = { title = "1016 NOISE", e1 = {id="m4_slow_rate", name="RATE"}, e2 = {id="m4_tilt1", name="TILT 1"}, e3 = {id="m4_tilt2", name="TILT 2"}, k2 = {id="m4_type1", name="N1"}, k3 = {id="m4_type2", name="N2"} }, B = { title = "1036 S&H", e1 = {id="m4_clk_rate", name="CLOCK"}, e2 = {id="m4_prob_skew", name="SKEW"}, e3 = {id="m4_glide", name="GLIDE"} } },
    [5] = { A = { title = "1005 STATE", e1 = {id="m5_drive", name="DRIVE"}, e2 = {id="m5_mod_gain", name="MOD"}, e3 = {id="m5_unmod_gain", name="UNMOD"}, k2 = {id="m5_state", name="ST"} }, B = { title = "1005 VCA", e1 = {id="m5_xfade", name="XFADE"}, e2 = {id="m5_vca_base", name="BASE"}, e3 = {id="m5_vca_resp", name="RESP"}, k2 = {id="m5_state", name="ST"} } },
    [6] = { A = { title = "1047 (A) FILTER", e1 = {id="m6_q", name="RES"}, e2 = {id="m6_cutoff", name="FREQ"}, e3 = {id="m6_fine", name="FINE"}, e4 = {id="m6_jfet", name="DRIVE"} }, B = { title = "1047 (A) NOTCH", e1 = {id="m6_p_shift", name="P.SHIFT"}, e2 = {id="m6_notch", name="NOTCH FRQ"}, e3 = {id="m6_final_q", name="KEY DCY"}, k3 = {id="m6_ping", name="PING"} } },
    [7] = { A = { title = "1047 (B) FILTER", e1 = {id="m7_q", name="RES"}, e2 = {id="m7_cutoff", name="FREQ"}, e3 = {id="m7_fine", name="FINE"}, e4 = {id="m7_jfet", name="DRIVE"} }, B = { title = "1047 (B) NOTCH", e1 = {id="m7_p_shift", name="P.SHIFT"}, e2 = {id="m7_notch", name="NOTCH FRQ"}, e3 = {id="m7_final_q", name="KEY DCY"}, k3 = {id="m7_ping", name="PING"} } },
    [8] = { A = { title = "NEXUS MASTER", e1 = {id="m8_res", name="RES"}, e2 = {id="m8_cut_l", name="VCF L"}, e3 = {id="m8_cut_r", name="VCF R"}, k2 = {id="m8_filt_byp", name="FILT"}, k3 = {id="m8_adc_mon", name="ADC"} }, B = { title = "NEXUS TAPE", e1 = {id="m8_tape_mix", name="MIX"}, e2 = {id="m8_tape_time", name="TIME"}, e3 = {id="m8_tape_fb", name="FDBK"}, e4 = {id="m8_wow", name="W&F"}, k2 = {id="m8_tape_sat", name="SAT"}, k3 = {id="m8_tape_mute", name="MUTE"} } }
}

local function grid_to_screen(x, y)
    return (x - 1) * 8 + 4, (y - 1) * 8 + 4
end

local function fmt_hz(v) 
    if not v then return "0.0Hz" end
    return v >= 1000 and string.format("%.1fkHz", v/1000) or string.format("%.1fHz", v) 
end

local function clean_str(str)
    if not str then return "" end
    return string.gsub(str, " ", "")
end

function ScreenUI.draw_idle(G)
    -- 1. Grid Virtual (Lectura segura desde el enlace global, sin includes destructivos)
    for x = 1, 16 do
        for y = 1, 8 do
            if y == 1 or y == 2 or y == 6 or y == 7 then
                local px, py = grid_to_screen(x, y)
                local b = (G.grid_cache and G.grid_cache[x] and G.grid_cache[x][y]) or 0
                if b == -1 then b = 0 end
                
                screen.level(b)
                screen.rect(px - 2, py - 2, 4, 4)
                screen.fill()
            end
        end
    end

    -- 2. Texto Central y Líneas
    screen.level(1)
    screen.move(0, 26); screen.line(128, 26); screen.stroke()
    screen.move(0, 34); screen.line(128, 34); screen.stroke()
    screen.level(4)
    screen.move(64, 32)
    screen.text_center("ELIANNE 2500")

    -- 3. Cables por encima
    screen.aa(1)
    screen.level(10)
    if G.patch and G.nodes then
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
    
    -- 4. Telemetría Dinámica Limpia
    local vol = 0.0
    local vcf1 = 20000
    local vcf2 = 20000
    
    pcall(function()
        vol = params:get("m8_master_vol") or 0.0
        vcf1 = params:get("m8_cut_l") or 20000
        vcf2 = params:get("m8_cut_r") or 20000
    end)
    
    screen.level(15)
    screen.move(2, 62); screen.text(string.format("%.1fdB", vol))
    screen.move(64, 62); screen.text_center(fmt_hz(vcf1))
    screen.move(126, 62); screen.text_right(fmt_hz(vcf2))
end

function ScreenUI.draw_node_menu(G)
    if not G.focus.node_x or not G.focus.node_y then return end
    local node = G.grid_map[G.focus.node_x] and G.grid_map[G.focus.node_x][G.focus.node_y]
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
    screen.move(126, 55)
    local lvl_str = string.format("%.2f", node.level or 0)
    local w_lvl = screen.text_extents(lvl_str)
    screen.text_right(lvl_str)
    screen.level(15)
    screen.move(126 - w_lvl - 2, 55)
    screen.text_right("E3 Level: ")
    
    if node.module == 8 and node.type == "in" then
        screen.level(4)
        screen.move(10, 55)
        screen.text("E2 Pan: ")
        screen.level(15)
        screen.text(string.format("%.2f", node.pan or 0))
    end
end

local function draw_param(def_e, x, y, label)
    if not def_e then return end
    screen.level(4); screen.move(x, y); screen.text(label .. " " .. def_e.name .. ": ")
    screen.level(15)
    
    local val = nil
    pcall(function() val = params:get(def_e.id) end)
    
    if val then
        if string.find(def_e.id, "cut") or string.find(def_e.id, "tune") then
            screen.text(fmt_hz(val))
        else
            local str_val = ""
            pcall(function() str_val = params:string(def_e.id) end)
            screen.text(clean_str(str_val))
        end
    else
        screen.text("---")
    end
end

function ScreenUI.draw_module_menu(G)
    if not G.focus.module_id or not G.focus.page then return end
    local def = MenuDef[G.focus.module_id][G.focus.page]
    if not def then return end

    screen.level(15)
    screen.move(64, 10)
    screen.text_center(def.title)

    draw_param(def.e1, 2, 30, "E1")
    draw_param(def.e2, 2, 45, "E2")
    draw_param(def.e3, 2, 60, "E3")
    draw_param(def.e4, 70, 60, "E4")

    screen.level(4)
    if def.k2 then 
        local k2_id = type(def.k2) == "table" and def.k2.id or def.k2
        local k2_name = type(def.k2) == "table" and def.k2.name or "K2"
        local k2_val = ""
        pcall(function() k2_val = clean_str(params:string(k2_id)) end)
        screen.move(126, 30); screen.text_right("K2 " .. k2_name .. (k2_name ~= "" and ": " or "") .. k2_val) 
    end
    if def.k3 then 
        local k3_id = type(def.k3) == "table" and def.k3.id or def.k3
        local k3_name = type(def.k3) == "table" and def.k3.name or "K3"
        local k3_val = ""
        pcall(function() k3_val = clean_str(params:string(k3_id)) end)
        screen.move(126, 45); screen.text_right("K3 " .. k3_name .. (k3_name ~= "" and ": " or "") .. k3_val) 
    end
end

function ScreenUI.draw(G)
    if not G or not G.grid_map or not G.nodes then return end

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
            pcall(function() params:delta("m8_master_vol", d * ((accel < 1) and 0.1 or 1.0)) end)
        elseif n == 2 then 
            pcall(function()
                local current = params:get("m8_cut_l")
                local step = (accel < 1) and 0.1 or ((accel > 1) and 100.0 or 10.0)
                params:set("m8_cut_l", util.clamp(current + (d * step), 20.0, 20000.0))
            end)
        elseif n == 3 then 
            pcall(function()
                local current = params:get("m8_cut_r")
                local step = (accel < 1) and 0.1 or ((accel > 1) and 100.0 or 10.0)
                params:set("m8_cut_r", util.clamp(current + (d * step), 20.0, 20000.0))
            end)
        elseif n == 4 then 
            pcall(function() params:delta("m8_tape_mix", d * ((accel < 1) and 0.1 or 1.0)) end)
        end
    elseif G.focus.state == "in" or G.focus.state == "out" then
        if not G.focus.node_x or not G.focus.node_y then return end
        local node = G.grid_map[G.focus.node_x] and G.grid_map[G.focus.node_x][G.focus.node_y]
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
            pcall(function()
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
            end)
        end
    end
end

function ScreenUI.key(G, n, z)
    if z == 1 and G.focus.state == "menu" then
        if not G.focus.module_id or not G.focus.page then return end
        local def = MenuDef[G.focus.module_id][G.focus.page]
        if not def then return end
        
        local target_param = nil
        if n == 2 and def.k2 then target_param = type(def.k2) == "table" and def.k2.id or def.k2 end
        if n == 3 and def.k3 then target_param = type(def.k3) == "table" and def.k3.id or def.k3 end
        
        if target_param then
            pcall(function()
                local p_idx = params.lookup[target_param]
                if p_idx then
                    local p = params.params[p_idx]
                    if p.type == "trigger" then
                        params:set(target_param, 1)
                    elseif p.options then
                        local current = params:get(target_param)
                        local next_val = current + 1
                        if next_val > #p.options then next_val = 1 end
                        params:set(target_param, next_val)
                    end
                end
            end)
        end
    end
end

return ScreenUI
