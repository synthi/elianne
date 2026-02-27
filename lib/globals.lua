-- lib/globals.lua v0.2
-- CHANGELOG v0.2:
-- 1. FIX FATAL: Añadido 'return G' al final del archivo.
-- 2. TOPOLOGÍA: Añadidos 2 Nodos Fantasma para sellar la matriz matemáticamente en 64x64.

local G = {}

G.screen_dirty = true
G.node_levels = {}
for i = 1, 64 do G.node_levels[i] = 0 end

G.focus = {
    state = "idle",
    module_id = nil,
    page = nil,
    node_x = nil,
    node_y = nil,
    hold_time = 0,
    target_x = nil,
    target_y = nil
}

G.patch = {}
G.nodes = {}
G.grid_map = {}

function G.init_nodes()
    for x = 1, 16 do
        G.grid_map[x] = {}
        for y = 1, 8 do
            G.grid_map[x][y] = nil
        end
    end

    local node_id_counter = 1

    local function add_node(x, y, type, module_idx, name)
        local id = node_id_counter
        local node = {
            id = id, x = x, y = y, type = type, 
            module = module_idx, name = name,
            level = 1.0, pan = 0.0, inverted = false
        }
        G.nodes[id] = node
        G.grid_map[x][y] = node
        node_id_counter = node_id_counter + 1
        return id
    end

    -- MÓDULO 1: 1004-T (A) [IDs 1-8]
    add_node(1, 1, "in", 1, "FM 1 In")
    add_node(2, 1, "in", 1, "FM 2 In")
    add_node(1, 2, "in", 1, "PWM In")
    add_node(2, 2, "in", 1, "V/Oct In")
    add_node(1, 6, "out", 1, "Main Mix Out")
    add_node(2, 6, "out", 1, "Inverted Out")
    add_node(1, 7, "out", 1, "Sine Out")
    add_node(2, 7, "out", 1, "Pulse Out")

    -- MÓDULO 2: 1004-T (B) [IDs 9-16]
    add_node(3, 1, "in", 2, "FM 1 In")
    add_node(4, 1, "in", 2, "FM 2 In")
    add_node(3, 2, "in", 2, "PWM In")
    add_node(4, 2, "in", 2, "V/Oct In")
    add_node(3, 6, "out", 2, "Main Mix Out")
    add_node(4, 6, "out", 2, "Inverted Out")
    add_node(3, 7, "out", 2, "Sine Out")
    add_node(4, 7, "out", 2, "Pulse Out")

    -- MÓDULO 3: 1023 Dual VCO[IDs 17-24]
    add_node(5, 1, "in", 3, "FM 1 In")
    add_node(6, 1, "in", 3, "FM 2 In")
    add_node(5, 2, "in", 3, "PWM/VOct 1 In")
    add_node(6, 2, "in", 3, "PWM/VOct 2 In")
    add_node(5, 6, "out", 3, "Osc 1 Out")
    add_node(6, 6, "out", 3, "Osc 2 Out")
    add_node(5, 7, "out", 3, "Inv 1 Out")
    add_node(6, 7, "out", 3, "Inv 2 Out")

    -- MÓDULO 4: 1016/36 Noise/Random [IDs 25-30]
    add_node(7, 1, "in", 4, "S&H Sig In")
    add_node(8, 1, "in", 4, "Clock In")
    add_node(7, 6, "out", 4, "Noise 1 Out")
    add_node(8, 6, "out", 4, "Noise 2 Out")
    add_node(7, 7, "out", 4, "Slow Rand Out")
    add_node(8, 7, "out", 4, "S&H Step Out")

    -- MÓDULO 5: 1005 ModAmp[IDs 31-38]
    add_node(9, 1, "in", 5, "Carrier In")
    add_node(10, 1, "in", 5, "Modulator In")
    add_node(9, 2, "in", 5, "VCA CV In")
    add_node(10, 2, "in", 5, "State Gate In")
    add_node(9, 6, "out", 5, "Main Out")
    add_node(10, 6, "out", 5, "Inverted Out")
    add_node(9, 7, "out", 5, "Sum (Upper) Out")
    add_node(10, 7, "out", 5, "Diff (Lower) Out")

    -- MÓDULO 6: 1047 (A) [IDs 39-46]
    add_node(11, 1, "in", 6, "Audio In")
    add_node(12, 1, "in", 6, "Freq CV 1 In")
    add_node(11, 2, "in", 6, "Resonance CV In")
    add_node(12, 2, "in", 6, "Freq CV 2 In")
    add_node(11, 6, "out", 6, "Low Pass Out")
    add_node(12, 6, "out", 6, "Band Pass Out")
    add_node(11, 7, "out", 6, "High Pass Out")
    add_node(12, 7, "out", 6, "Notch Out")

    -- MÓDULO 7: 1047 (B) [IDs 47-54]
    add_node(13, 1, "in", 7, "Audio In")
    add_node(14, 1, "in", 7, "Freq CV 1 In")
    add_node(13, 2, "in", 7, "Resonance CV In")
    add_node(14, 2, "in", 7, "Freq CV 2 In")
    add_node(13, 6, "out", 7, "Low Pass Out")
    add_node(14, 6, "out", 7, "Band Pass Out")
    add_node(13, 7, "out", 7, "High Pass Out")
    add_node(14, 7, "out", 7, "Notch Out")

    -- MÓDULO 8: NEXUS [IDs 55-62]
    add_node(15, 1, "in", 8, "Modular In L")
    add_node(16, 1, "in", 8, "Modular In R")
    add_node(15, 2, "in", 8, "ADC In L")
    add_node(16, 2, "in", 8, "ADC In R")
    add_node(15, 6, "out", 8, "Master Out L")
    add_node(16, 6, "out", 8, "Master Out R")
    add_node(15, 7, "out", 8, "Tape Send L")
    add_node(16, 7, "out", 8, "Tape Send R")

    -- NODOS FANTASMA (Para completar 64)[IDs 63-64]
    add_node(16, 8, "dummy", 8, "Dummy 1")
    add_node(16, 8, "dummy", 8, "Dummy 2")

    for src = 1, 64 do
        G.patch[src] = {}
        for dst = 1, 64 do
            G.patch[src][dst] = { active = false, level = 1.0, pan = 0.0 }
        end
    end
end

return G
