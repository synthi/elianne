-- lib/params_setup.lua v0.1
-- CHANGELOG v0.1:
-- 1. INIT: Registro de parámetros Set & Forget y variables de estado para Snapshots.

local Params = {}

function Params.init(G)
    params:add_separator("ELIANNE - ARP 2500")

    -- GRUPO 1: FÍSICA Y ENTORNO (Set & Forget)
    params:add_group("PHYSICS & ENVIRONMENT", 5)
    params:add{type = "control", id = "thermal_drift", name = "Thermal Drift", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.1), action = function(x) engine.set_global_physics("thermal", x) end}
    params:add{type = "control", id = "capacitor_droop", name = "1016 Cap Droop", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.05), action = function(x) engine.set_global_physics("droop", x) end}
    params:add{type = "control", id = "carrier_bleed", name = "1005 Carrier Bleed", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.02), action = function(x) engine.set_global_physics("c_bleed", x) end}
    params:add{type = "control", id = "modulator_bleed", name = "1005 Mod Bleed", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.01), action = function(x) engine.set_global_physics("m_bleed", x) end}
    params:add{type = "control", id = "perc_pitch_shift", name = "1047 Perc Pitch Shift", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.15), action = function(x) engine.set_global_physics("p_shift", x) end}

    -- GRUPO 2: NEXUS TAPE ECHO (Set & Forget)
    params:add_group("NEXUS TAPE MECHANICS", 2)
    params:add{type = "control", id = "tape_wow", name = "Wow (Slow)", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.1), action = function(x) engine.set_tape_physics("wow", x) end}
    params:add{type = "control", id = "tape_flutter", name = "Flutter (Fast)", controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.05), action = function(x) engine.set_tape_physics("flutter", x) end}

    -- Nota: En la Fase 3, aquí se registrarán los parámetros de los menús contextuales 
    -- (Tune, PWM, Cutoff, etc.) para que el sistema nativo de Norns los guarde en los .pset.
    
    print("ELIANNE: Parámetros Registrados.")
end

return Params
