-- lib/screen_ui.lua v0.3
-- CHANGELOG v0.3:
-- 1. MENÚS: Implementación del diccionario de menús para los 8 módulos (Páginas A y B).
-- 2. ENCODERS: Aceleración dinámica para parámetros de afinación (Tune).
-- 3. KEYS: Lógica de interruptores (K2/K3) integrada.

local ScreenUI = {}

-- Diccionario de Menús Contextuales
local MenuDef = {
    [1] = { -- 1004-T (A)
        A = { title = "1004-T (A) MIXER", e1 = "m1_mix_sine", e2 = "m1_mix_tri", e3 = "m1_mix_saw" },
        B = { title = "1004-T (A) CORE", e1 = "m1_pwm", e2 = "m1_tune", e3 = "m1_fine", k3 = "m1_range" }
    },
    [2] = { -- 1004-T (B)
        A = { title = "1004-T (B) MIXER", e1 = "m2_mix_sine", e2 = "m2_mix_tri", e3 = "m2_mix_saw" },
        B = { title = "1004-T (B) CORE", e1 = "m2_pwm", e2 = "m2_tune", e3 = "m2_fine", k3 = "m2_range" }
    },[3] = { -- 1023 DUAL VCO
        A = { title = "1023 - OSC 1", e1 = "m3_pwm1", e2 = "m3_tune1", e3 = "m3_morph1", k3 = "m3_range1" },
        B = { title = "1023 - OSC 2", e1 = "m3_pwm2", e2 = "m3_tune2", e3 = "m3_morph2", k3 = "m3_range2" }
    },
    [4] = { -- 1016/36 NOISE
        A = { title = "1016 NOISE", e1 = "m4_slow_rate", e2 = "m4_tilt1", e3 = "m4_tilt2", k2 = "m4_type1", k3 = "m4_type2" },
        B = { title = "1036 S&H", e1 = "m4_clk_rate", e2 = "m4_prob_skew", e3 = "m4_glide" }
    },
    [5] = { -- 1005 MODAMP
        A = { title = "1005 STATE", e1 = "m5_mod_gain", e2 = "m5_unmod_gain", e3 = "m5_drive", k2 = "m5_state" },
        B = { title = "1005 VCA", e1 = "m5_vca_base", e2 = "m5_vca_resp", e3 = "m5_xfade", k2 = "m5_state" }
    },
    [6] = { -- 1047 (A)
        A = { title = "1047 (A) FILTER", e1 = "m6_cutoff", e2 = "m6_fine", e3 = "m6_q" },
        B = { title = "1047 (A) NOTCH", e1 = "m6_notch", e2 = "m6_final_q", e3 = "m6_out_lvl" }
    },
    [7] = { -- 1047 (B)
        A = { title = "1047 (B) FILTER", e1 = "m7_cutoff", e2 = "m7_fine", e3 = "m7_q" },
        B = { title = "1047 (B) NOTCH", e1 = "m7_notch", e2 = "m7_final_q", e3 = "m7_out_lvl" }
    },[8] = { -- NEXUS
        A = { title = "NEXUS MASTER", e1 = "m8_cut_l", e2 = "m8_cut_r", e3 = "m8_res", k2 = "m8_filt_byp", k3 = "m8_adc_mon" },
        B = { title = "NEXUS TAPE", e1 = "m8_tape_time", e2 = "m8_tape_fb", e3 = "m8_tape_mix", k2 = "m8_tape_sat", k3 = "m8_tape_mute" }
    }
}

local function grid_to_screen(x, y)
    return (x - 1) * 8 + 4, (y - 1) * 8 + 4
end

function ScreenUI.draw_idle(G)
    screen.aa(1)
    screen.level(10)
    for src_id, dests in pairs(G.patch) do
        for dst_id, data in pairs(dests) do
            if data.active then
                local src_node = G.nodes[src_id]
                local dst_node = G.nodes[dst_id]
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
    screen.aa(0)
    
    for x = 1, 16 do
        for y = 1, 8 do
            local node = G.grid_map[x][y]
            local is_menu = (y == 4)
            if node or is_menu then
                local px, py = grid_to_screen(x, y)
                local is_even = (math.ceil(x / 2) % 2 == 0)
                screen.level(is_even and 4 or 2)
                screen.rect(px - 2, py - 2, 4, 4)
                screen.fill()
            end
        end
    end
    
    screen.level(15)
    screen.move(2, 62)
    screen.text("ELIANNE")
    screen.move(126, 62)
    screen.text_right("IDLE")
end

function ScreenUI.draw_node_menu(G)
    local node = G.grid_map[G.focus.node_x][G.focus.node_y]
    if not node then return end
    
    screen.level(15)
    screen.move(64, 10)
    screen.text_center(node.name)
    
    screen.level(4)
    screen.move(64, 20)
    screen.text_center(node.type == "in" and "INPUT ATTENUVERTER" or "OUTPUT LEVEL")
    
    screen.level(15)
    screen.rect(14, 30, 100, 10)
    screen.stroke()
    
    screen.level(4)
    screen.move(64, 30)
    screen.line(64, 40)
    screen.stroke()
    
    screen.level(15)
    local val_px = node.level * 50
    if node.level > 0 then
        screen.rect(64, 32, val_px, 6)
    else
        screen.rect(64 + val_px, 32, math.abs(val_px), 6)
    end
    screen.fill()
    
    screen.move(10, 55)
    screen.text("E2: " .. string.format("%.2f", node.level))
    
    if node.module == 8 and node.type == "in" then
        screen.move(118, 55)
        screen.text_right("E3 PAN: " .. string.format("%.2f", node.pan))
    end
end

function ScreenUI.draw_module_menu(G)
    local def = MenuDef[G.focus.module_id][G.focus.page]
    if not def then return end

    screen.level(15)
    screen.move(64, 10)
    screen.text_center(def.title)
    screen.line(10, 14, 118, 14)
    screen.stroke()

    -- Dibujar Encoders
    screen.level(4)
    if def.e1 then screen.move(2, 30); screen.text("E1"); screen.level(15); screen.move(20, 30); screen.text(params:string(def.e1)) end
    screen.level(4)
    if def.e2 then screen.move(2, 45); screen.text("E2"); screen.level(15); screen.move(20, 45); screen.text(params:string(def.e2)) end
    screen.level(4)
    if def.e3 then screen.move(2, 60); screen.text("E3"); screen.level(15); screen.move(20, 60); screen.text(params:string(def.e3)) end

    -- Dibujar Keys
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

-- Variables para Aceleración Dinámica
local last_enc_time = 0

function ScreenUI.enc(G, n, d)
    local now = util.time()
    local dt = now - last_enc_time
    last_enc_time = now
    
    -- Multiplicador de Aceleración
    local accel = 1.0
    if dt < 0.05 then accel = 5.0 -- Giro rápido
    elseif dt > 0.15 then accel = 0.1 end -- Giro lento (Microafinación)

    if G.focus.state == "in" or G.focus.state == "out" then
        local node = G.grid_map[G.focus.node_x][G.focus.node_y]
        local Matrix = include('lib/matrix') -- Requerido localmente para evitar dependencias circulares
        if n == 2 then
            node.level = util.clamp(node.level + (d * 0.05 * accel), -1.0, 1.0)
            Matrix.update_node_params(node)
        elseif n == 3 and node.module == 8 and node.type == "in" then
            node.pan = util.clamp(node.pan + (d * 0.05 * accel), -1.0, 1.0)
            Matrix.update_node_params(node)
        end
    elseif G.focus.state == "menu" then
        local def = MenuDef[G.focus.module_id][G.focus.page]
        if not def then return end
        
        local target_param = nil
        if n == 1 then target_param = def.e1
        elseif n == 2 then target_param = def.e2
        elseif n == 3 then target_param = def.e3 end
        
        if target_param then
            -- Si es un parámetro de afinación (Tune), aplicar aceleración
            if string.find(target_param, "tune") then
                params:delta(target_param, d * accel)
            else
                params:delta(target_param, d)
            end
        end
    end
end

function ScreenUI.key(G, n, z)
    if z == 1 and G.focus.state == "menu" then
        local def = MenuDef[G.focus.module_id][G.focus.page]
        if not def then return end
        
        local target_param = nil
        if n == 2 then target_param = def.k2
        elseif n == 3 then target_param = def.k3 end
        
        if target_param then
            local p = params:lookup_param(target_param)
            if p.type == "option" then
                -- Ciclar opciones
                local current = params:get(target_param)
                local next_val = current + 1
                if next_val > #p.options then next_val = 1 end
                params:set(target_param, next_val)
            end
        end
    end
end

return ScreenUI
