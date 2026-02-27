-- lib/params_setup.lua v0.2
-- CHANGELOG v0.2:
-- 1. ESTRUCTURA: Eliminada carpeta genérica. Creadas carpetas por módulo.
-- 2. SNAPSHOTS: Añadidos los 64 Attenuverters como parámetros ocultos para Total Recall.
-- 3. MAPEO: Todos los parámetros enlazados a comandos OSC del Engine.

local Params = {}

function Params.init(G)
    params:add_separator("ELIANNE - ARP 2500")

    -- ==========================================
    -- PARÁMETROS GLOBALES
    -- ==========================================
    params:add_group("GLOBAL PHYSICS", 1)
    params:add{type = "control", id = "thermal_drift", name = "Thermal Drift", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.1), action = function(x) engine.set_global_drift(x) end}

    -- ==========================================
    -- MÓDULO 1: 1004-T (A)
    -- ==========================================
    params:add_group("MOD 1: 1004-T (A)", 8)
    params:add{type = "control", id = "m1_tune", name = "Tune", controlspec = controlspec.new(10.0, 16000.0, 'exp', 0.001, 100.0, "Hz"), action = function(x) engine.m1_tune(x) end}
    params:add{type = "control", id = "m1_fine", name = "Fine Tune", controlspec = controlspec.new(-2.0, 2.0, 'lin', 0.001, 0.0, "Hz"), action = function(x) engine.m1_fine(x) end}
    params:add{type = "control", id = "m1_pwm", name = "PWM Base", controlspec = controlspec.new(0.05, 0.95, 'lin', 0.01, 0.5), action = function(x) engine.m1_pwm(x) end}
    params:add{type = "control", id = "m1_mix_sine", name = "Mix Sine", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 1.0), action = function(x) engine.m1_mix_sine(x) end}
    params:add{type = "control", id = "m1_mix_tri", name = "Mix Tri", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m1_mix_tri(x) end}
    params:add{type = "control", id = "m1_mix_saw", name = "Mix Saw", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m1_mix_saw(x) end}
    params:add{type = "control", id = "m1_mix_pulse", name = "Mix Pulse", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m1_mix_pulse(x) end}
    params:add{type = "option", id = "m1_range", name = "Range", options = {"Audio", "LFO"}, default = 1, action = function(x) engine.m1_range(x) end}

    -- ==========================================
    -- MÓDULO 2: 1004-T (B)
    -- ==========================================
    params:add_group("MOD 2: 1004-T (B)", 8)
    params:add{type = "control", id = "m2_tune", name = "Tune", controlspec = controlspec.new(10.0, 16000.0, 'exp', 0.001, 100.0, "Hz"), action = function(x) engine.m2_tune(x) end}
    params:add{type = "control", id = "m2_fine", name = "Fine Tune", controlspec = controlspec.new(-2.0, 2.0, 'lin', 0.001, 0.0, "Hz"), action = function(x) engine.m2_fine(x) end}
    params:add{type = "control", id = "m2_pwm", name = "PWM Base", controlspec = controlspec.new(0.05, 0.95, 'lin', 0.01, 0.5), action = function(x) engine.m2_pwm(x) end}
    params:add{type = "control", id = "m2_mix_sine", name = "Mix Sine", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 1.0), action = function(x) engine.m2_mix_sine(x) end}
    params:add{type = "control", id = "m2_mix_tri", name = "Mix Tri", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m2_mix_tri(x) end}
    params:add{type = "control", id = "m2_mix_saw", name = "Mix Saw", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m2_mix_saw(x) end}
    params:add{type = "control", id = "m2_mix_pulse", name = "Mix Pulse", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m2_mix_pulse(x) end}
    params:add{type = "option", id = "m2_range", name = "Range", options = {"Audio", "LFO"}, default = 1, action = function(x) engine.m2_range(x) end}

    -- ==========================================
    -- MÓDULO 3: 1023 DUAL VCO
    -- ==========================================
    params:add_group("MOD 3: 1023 DUAL VCO", 8)
    params:add{type = "control", id = "m3_tune1", name = "Osc 1 Tune", controlspec = controlspec.new(0.01, 16000.0, 'exp', 0.001, 100.0, "Hz"), action = function(x) engine.m3_tune1(x) end}
    params:add{type = "control", id = "m3_pwm1", name = "Osc 1 PWM", controlspec = controlspec.new(0.05, 0.95, 'lin', 0.01, 0.5), action = function(x) engine.m3_pwm1(x) end}
    params:add{type = "control", id = "m3_morph1", name = "Osc 1 Morph", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.001, 0.0), action = function(x) engine.m3_morph1(x) end}
    params:add{type = "option", id = "m3_range1", name = "Osc 1 Range", options = {"Audio", "LFO"}, default = 1, action = function(x) engine.m3_range1(x) end}
    params:add{type = "control", id = "m3_tune2", name = "Osc 2 Tune", controlspec = controlspec.new(0.01, 16000.0, 'exp', 0.001, 101.0, "Hz"), action = function(x) engine.m3_tune2(x) end}
    params:add{type = "control", id = "m3_pwm2", name = "Osc 2 PWM", controlspec = controlspec.new(0.05, 0.95, 'lin', 0.01, 0.5), action = function(x) engine.m3_pwm2(x) end}
    params:add{type = "control", id = "m3_morph2", name = "Osc 2 Morph", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.001, 0.0), action = function(x) engine.m3_morph2(x) end}
    params:add{type = "option", id = "m3_range2", name = "Osc 2 Range", options = {"Audio", "LFO"}, default = 1, action = function(x) engine.m3_range2(x) end}

    -- ==========================================
    -- MÓDULO 4: 1016/36 NOISE & RANDOM
    -- ==========================================
    params:add_group("MOD 4: 1016/36 NOISE", 9)
    params:add{type = "control", id = "m4_slow_rate", name = "Slow Rand Rate", controlspec = controlspec.new(0.01, 10.0, 'exp', 0.01, 0.1, "Hz"), action = function(x) engine.m4_slow_rate(x) end}
    params:add{type = "control", id = "m4_tilt1", name = "Noise 1 Tilt", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m4_tilt1(x) end}
    params:add{type = "control", id = "m4_tilt2", name = "Noise 2 Tilt", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m4_tilt2(x) end}
    params:add{type = "option", id = "m4_type1", name = "Noise 1 Type", options = {"Pink", "White", "Crackle", "DigiRain", "Lorenz", "Grit"}, default = 1, action = function(x) engine.m4_type1(x) end}
    params:add{type = "option", id = "m4_type2", name = "Noise 2 Type", options = {"Pink", "White", "Crackle", "DigiRain", "Lorenz", "Grit"}, default = 2, action = function(x) engine.m4_type2(x) end}
    params:add{type = "control", id = "m4_clk_rate", name = "Internal Clock", controlspec = controlspec.new(0.1, 50.0, 'exp', 0.01, 2.0, "Hz"), action = function(x) engine.m4_clk_rate(x) end}
    params:add{type = "control", id = "m4_prob_skew", name = "Probability Skew", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m4_prob_skew(x) end}
    params:add{type = "control", id = "m4_glide", name = "S&H Glide", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m4_glide(x) end}
    params:add{type = "control", id = "m4_cap_droop", name = "Capacitor Droop", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.05), action = function(x) engine.m4_cap_droop(x) end}

    -- ==========================================
    -- MÓDULO 5: 1005 MODAMP
    -- ==========================================
    params:add_group("MOD 5: 1005 MODAMP", 8)
    params:add{type = "control", id = "m5_mod_gain", name = "MOD Gain", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 1.0), action = function(x) engine.m5_mod_gain(x) end}
    params:add{type = "control", id = "m5_unmod_gain", name = "UNMOD Gain", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 1.0), action = function(x) engine.m5_unmod_gain(x) end}
    params:add{type = "control", id = "m5_drive", name = "Transformer Drive", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.2), action = function(x) engine.m5_drive(x) end}
    params:add{type = "control", id = "m5_vca_base", name = "VCA Base Gain", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m5_vca_base(x) end}
    params:add{type = "control", id = "m5_vca_resp", name = "VCA Response", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.5), action = function(x) engine.m5_vca_resp(x) end}
    params:add{type = "control", id = "m5_xfade", name = "State XFade Time", controlspec = controlspec.new(0.0, 10.0, 'lin', 0.01, 0.05, "s"), action = function(x) engine.m5_xfade(x) end}
    params:add{type = "control", id = "m5_c_bleed", name = "Carrier Bleed", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.02), action = function(x) engine.m5_c_bleed(x) end}
    params:add{type = "control", id = "m5_m_bleed", name = "Modulator Bleed", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.01), action = function(x) engine.m5_m_bleed(x) end}

    -- ==========================================
    -- MÓDULO 6: 1047 (A)
    -- ==========================================
    params:add_group("MOD 6: 1047 (A)", 7)
    params:add{type = "control", id = "m6_cutoff", name = "Cutoff", controlspec = controlspec.new(10.0, 18000.0, 'exp', 0.01, 1000.0, "Hz"), action = function(x) engine.m6_cutoff(x) end}
    params:add{type = "control", id = "m6_fine", name = "Cutoff Fine", controlspec = controlspec.new(-5.0, 5.0, 'lin', 0.001, 0.0, "Hz"), action = function(x) engine.m6_fine(x) end}
    params:add{type = "control", id = "m6_q", name = "Resonance (Q)", controlspec = controlspec.new(0.1, 500.0, 'exp', 0.1, 1.0), action = function(x) engine.m6_q(x) end}
    params:add{type = "control", id = "m6_notch", name = "Notch Offset", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m6_notch(x) end}
    params:add{type = "control", id = "m6_final_q", name = "Perc Final Q", controlspec = controlspec.new(0.1, 100.0, 'exp', 0.1, 2.0), action = function(x) engine.m6_final_q(x) end}
    params:add{type = "control", id = "m6_out_lvl", name = "Output Level", controlspec = controlspec.new(0.0, 2.0, 'lin', 0.01, 1.0), action = function(x) engine.m6_out_lvl(x) end}
    params:add{type = "control", id = "m6_p_shift", name = "Perc Pitch Shift", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.1), action = function(x) engine.m6_p_shift(x) end}

    -- ==========================================
    -- MÓDULO 7: 1047 (B)
    -- ==========================================
    params:add_group("MOD 7: 1047 (B)", 7)
    params:add{type = "control", id = "m7_cutoff", name = "Cutoff", controlspec = controlspec.new(10.0, 18000.0, 'exp', 0.01, 1000.0, "Hz"), action = function(x) engine.m7_cutoff(x) end}
    params:add{type = "control", id = "m7_fine", name = "Cutoff Fine", controlspec = controlspec.new(-5.0, 5.0, 'lin', 0.001, 0.0, "Hz"), action = function(x) engine.m7_fine(x) end}
    params:add{type = "control", id = "m7_q", name = "Resonance (Q)", controlspec = controlspec.new(0.1, 500.0, 'exp', 0.1, 1.0), action = function(x) engine.m7_q(x) end}
    params:add{type = "control", id = "m7_notch", name = "Notch Offset", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m7_notch(x) end}
    params:add{type = "control", id = "m7_final_q", name = "Perc Final Q", controlspec = controlspec.new(0.1, 100.0, 'exp', 0.1, 2.0), action = function(x) engine.m7_final_q(x) end}
    params:add{type = "control", id = "m7_out_lvl", name = "Output Level", controlspec = controlspec.new(0.0, 2.0, 'lin', 0.01, 1.0), action = function(x) engine.m7_out_lvl(x) end}
    params:add{type = "control", id = "m7_p_shift", name = "Perc Pitch Shift", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.1), action = function(x) engine.m7_p_shift(x) end}

    -- ==========================================
    -- MÓDULO 8: NEXUS
    -- ==========================================
    params:add_group("MOD 8: NEXUS", 8)
    params:add{type = "control", id = "m8_cut_l", name = "Master Cutoff L", controlspec = controlspec.new(20.0, 20000.0, 'exp', 0.01, 20000.0, "Hz"), action = function(x) engine.m8_cut_l(x) end}
    params:add{type = "control", id = "m8_cut_r", name = "Master Cutoff R", controlspec = controlspec.new(20.0, 20000.0, 'exp', 0.01, 20000.0, "Hz"), action = function(x) engine.m8_cut_r(x) end}
    params:add{type = "control", id = "m8_res", name = "Master Resonance", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.0), action = function(x) engine.m8_res(x) end}
    params:add{type = "control", id = "m8_tape_time", name = "Tape Time", controlspec = controlspec.new(0.01, 2.0, 'lin', 0.01, 0.3, "s"), action = function(x) engine.m8_tape_time(x) end}
    params:add{type = "control", id = "m8_tape_fb", name = "Tape Feedback", controlspec = controlspec.new(0.0, 1.2, 'lin', 0.01, 0.4), action = function(x) engine.m8_tape_fb(x) end}
    params:add{type = "control", id = "m8_tape_mix", name = "Tape Dry/Wet", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.2), action = function(x) engine.m8_tape_mix(x) end}
    params:add{type = "control", id = "m8_wow", name = "Tape Wow", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.1), action = function(x) engine.m8_wow(x) end}
    params:add{type = "control", id = "m8_flutter", name = "Tape Flutter", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.05), action = function(x) engine.m8_flutter(x) end}

    -- ==========================================
    -- ATTENUVERTERS OCULTOS (Para Snapshots)
    -- ==========================================
    -- Registramos los 64 nodos (32 In, 32 Out) para que se guarden en el .pset
    -- Usamos params:hide() para que no saturen el menú visual de Norns.
    for i = 1, 64 do
        local p_id = "node_lvl_" .. i
        params:add{type = "control", id = p_id, name = "Node " .. i .. " Level", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, (i <= 32 and 1.0 or 0.0))}
        params:hide(p_id)
        
        -- Si es un nodo de entrada del Nexus (IDs 29, 30, 31, 32), añadimos Paneo
        if i >= 29 and i <= 32 then
            local pan_id = "node_pan_" .. i
            params:add{type = "control", id = pan_id, name = "Node " .. i .. " Pan", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0)}
            params:hide(pan_id)
        end
    end

    print("ELIANNE: Parámetros Registrados al 100%.")
end

return Params
