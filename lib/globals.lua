-- lib/globals.lua
-- Gestión de Estado y Topología de Hardware

local G = {}

G.screen_dirty = true

-- Estado de Interacción (Hold-to-Patch / Menús)
G.focus = {
    state = "idle", -- "idle", "menu", "input", "output", "patching"
    module_id = nil,
    page = nil,
    node_x = nil,
    node_y = nil,
    hold_time = 0,
    target_x = nil, -- Para el parcheo bidireccional
    target_y = nil
}

-- Matriz de Parcheo (Cables Virtuales)
-- patch[src_id][dst_id] = { active = boolean, level = float, pan = float }
G.patch = {}

-- Base de datos de Nodos (Entradas y Salidas)
G.nodes = {}
G.grid_map = {} -- Mapeo rápido X,Y -> Nodo

function G.init_nodes()
    for x = 1, 16 do
        G.grid_map[x] = {}
        for y = 1, 8 do
            G.grid_map[x][y] = nil
        end
    end

    local node_id_counter = 1

    -- Función auxiliar para registrar un nodo
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

    -- MÓDULO 1: 1004-T (A) [Cols 1-2]
    add_node(1, 1, "in", 1, "FM 1 In")
    add_node(2, 1, "in", 1, "FM 2 In")
    add_node(1, 2, "in", 1, "PWM In")
    add_node(2, 2, "in", 1, "V/Oct In")
    add_node(1, 6, "out", 1, "Main Mix Out")
    add_node(2, 6, "out", 1, "Inverted Out")
    add_node(1, 7, "out", 1, "Sine Out")
    add_node(2, 7, "out", 1, "Pulse Out")

    -- MÓDULO 2: 1004-T (B) [Cols 3-4]
    add_node(3, 1, "in", 2, "FM 1 In")
    add_node(4, 1, "in", 2, "FM 2 In")
    add_node(3, 2, "in", 2, "PWM In")
    add_node(4, 2, "in", 2, "V/Oct In")
    add_node(3, 6, "out", 2, "Main Mix Out")
    add_node(4, 6, "out", 2, "Inverted Out")
    add_node(3, 7, "out", 2, "Sine Out")
    add_node(4, 7, "out", 2, "Pulse Out")

    -- MÓDULO 3: 1023 Dual VCO [Cols 5-6]
    add_node(5, 1, "in", 3, "FM 1 In")
    add_node(6, 1, "in", 3, "FM 2 In")
    add_node(5, 2, "in", 3, "PWM/VOct 1 In")
    add_node(6, 2, "in", 3, "PWM/VOct 2 In")
    add_node(5, 6, "out", 3, "Osc 1 Out")
    add_node(6, 6, "out", 3, "Osc 2 Out")
    add_node(5, 7, "out", 3, "Inv 1 Out")
    add_node(6, 7, "out", 3, "Inv 2 Out")

    -- MÓDULO 4: 1016/36 Noise/Random [Cols 7-8]
    add_node(7, 1, "in", 4, "S&H Sig In")
    add_node(8, 1, "in", 4, "Clock In")
    add_node(7, 6, "out", 4, "Noise 1 Out")
    add_node(8, 6, "out", 4, "Noise 2 Out")
    add_node(7, 7, "out", 4, "Slow Rand Out")
    add_node(8, 7, "out", 4, "S&H Step Out")

    -- MÓDULO 5: 1005 ModAmp [Cols 9-10]
    add_node(9, 1, "in", 5, "Carrier In")
    add_node(10, 1, "in", 5, "Modulator In")
    add_node(9, 2, "in", 5, "VCA CV In")
    add_node(10, 2, "in", 5, "State Gate In")
    add_node(9, 6, "out", 5, "Main Out")
    add_node(10, 6, "out", 5, "Inverted Out")
    add_node(9, 7, "out", 5, "Sum (Upper) Out")
    add_node(10, 7, "out", 5, "Diff (Lower) Out")

    -- MÓDULO 6: 1047 (A) [Cols 11-12]
    add_node(11, 1, "in", 6, "Audio In")
    add_node(12, 1, "in", 6, "Freq CV 1 In")
    add_node(11, 2, "in", 6, "Resonance CV In")
    add_node(12, 2, "in", 6, "Freq CV 2 In")
    add_node(11, 6, "out", 6, "Low Pass Out")
    add_node(12, 6, "out", 6, "Band Pass Out")
    add_node(11, 7, "out", 6, "High Pass Out")
    add_node(12, 7, "out", 6, "Notch Out")

    -- MÓDULO 7: 1047 (B) [Cols 13-14]
    add_node(13, 1, "in", 7, "Audio In")
    add_node(14, 1, "in", 7, "Freq CV 1 In")
    add_node(13, 2, "in", 7, "Resonance CV In")
    add_node(14, 2, "in", 7, "Freq CV 2 In")
    add_node(13, 6, "out", 7, "Low Pass Out")
    add_node(14, 6, "out", 7, "Band Pass Out")
    add_node(13, 7, "out", 7, "High Pass Out")
    add_node(14, 7, "out", 7, "Notch Out")

    -- MÓDULO 8: NEXUS[Cols 15-16]
    add_node(15, 1, "in", 8, "Modular In L")
    add_node(16, 1, "in", 8, "Modular In R")
    add_node(15, 2, "in", 8, "ADC In L")
    add_node(16, 2, "in", 8, "ADC In R")
    add_node(15, 6, "out", 8, "Master Out L")
    add_node(16, 6, "out", 8, "Master Out R")
    add_node(15, 7, "out", 8, "Tape Send L")
    add_node(16, 7, "out", 8, "Tape Send R")

    -- Inicializar Matriz de Parcheo (Todos con Todos)
    for src = 1, node_id_counter do
        G.patch[src] = {}
        for dst = 1, node_id_counter do
            G.patch[src][dst] = { active = false, level = 1.0, pan = 0.0 }
        end
    end
end

return G
