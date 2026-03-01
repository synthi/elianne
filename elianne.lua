-- elianne.lua v0.301
-- CHANGELOG v0.300:
-- 1. FEATURE: Voice Allocator (Cerebro Polifónico) para los nodos MIDI.
-- 2. FEATURE: Sincronización de BPM global hacia SuperCollider.

engine.name = 'Elianne'

print("========================================")
print("ELIANNE DEBUG: INICIANDO CARGA DE MÓDULOS")
print("========================================")

local G, GridUI, ScreenUI, Matrix, Params, Storage, Faderbank

local function load_dependencies()
    G = include('lib/globals')
    GridUI = include('lib/grid_ui')
    ScreenUI = include('lib/screen_ui')
    Matrix = include('lib/matrix')
    Params = include('lib/params_setup')
    Storage = include('lib/storage')
    Faderbank = include('lib/16n')
end

local status, err = pcall(load_dependencies)
if not status then
    print("ELIANNE FATAL ERROR: " .. err)
    error(err) -- Forzamos el crash para que Maiden lo muestre
end

g = grid.connect()
local grid_metro, screen_metro

-- =====================================================================
-- VOICE ALLOCATOR (CEREBRO POLIFÓNICO MIDI)
-- =====================================================================
local active_notes = {} -- {note = {voice_idx = 1}}
local voice_pool = {
    {pitch_node = nil, gate_node = nil, active = false, last_note = nil},
    {pitch_node = nil, gate_node = nil, active = false, last_note = nil},
    {pitch_node = nil, gate_node = nil, active = false, last_note = nil},
    {pitch_node = nil, gate_node = nil, active = false, last_note = nil}
}
local last_voice_used = 0

local function build_voice_pool(channel)
    -- Limpiar pool
    for i=1,4 do voice_pool[i].pitch_node = nil; voice_pool[i].gate_node = nil end
    
    local v_idx = 1
    for i=1, 4 do
        local ch = params:get("midi_ch_"..i)
        if ch == 0 or ch == channel then
            local mode = params:get("midi_mode_"..i)
            if mode == 1 then -- PITCH
                voice_pool[v_idx].pitch_node = i
                v_idx = v_idx + 1
            elseif mode == 2 then -- GATE
                -- Buscar si hay un pitch huérfano para emparejarlo, si no, usar nueva voz
                local paired = false
                for j=1, 4 do
                    if voice_pool[j].pitch_node and not voice_pool[j].gate_node then
                        voice_pool[j].gate_node = i
                        paired = true
                        break
                    end
                end
                if not paired then
                    voice_pool[v_idx].gate_node = i
                    v_idx = v_idx + 1
                end
            end
        end
    end
end

local function allocate_voice()
    local mode = params:get("midi_poly_mode")
    if mode == 1 then -- ROTATE
        for i=1, 4 do
            last_voice_used = (last_voice_used % 4) + 1
            if (voice_pool[last_voice_used].pitch_node or voice_pool[last_voice_used].gate_node) and not voice_pool[last_voice_used].active then
                return last_voice_used
            end
        end
    else -- RESET
        for i=1, 4 do
            if (voice_pool[i].pitch_node or voice_pool[i].gate_node) and not voice_pool[i].active then
                return i
            end
        end
    end
    return nil -- No hay voces libres
end

local function midi_event(data)
    local msg = midi.to_msg(data)
    local target_dev = params:get("midi_device")
    local target_ch = params:get("midi_ch_1") -- Simplificación: asume que el canal base dicta el pool
    
    if msg.ch ~= target_ch and target_ch ~= 0 then return end
    
    build_voice_pool(msg.ch)

    if msg.type == "note_on" then
        local v_idx = allocate_voice()
        if v_idx then
            voice_pool[v_idx].active = true
            voice_pool[v_idx].last_note = msg.note
            active_notes[msg.note] = {voice_idx = v_idx}
            
            if voice_pool[v_idx].pitch_node then
                local oct_offset = params:get("midi_oct_"..voice_pool[v_idx].pitch_node)
                local volt = ((msg.note - 60) / 12.0) + oct_offset
                engine.set_midi_val(voice_pool[v_idx].pitch_node, volt)
            end
            if voice_pool[v_idx].gate_node then
                engine.set_midi_val(voice_pool[v_idx].gate_node, 1.0)
            end
        end
    elseif msg.type == "note_off" then
        if active_notes[msg.note] then
            local v_idx = active_notes[msg.note].voice_idx
            voice_pool[v_idx].active = false
            active_notes[msg.note] = nil
            
            -- PITCH HOLD: No reseteamos el pitch_node
            if voice_pool[v_idx].gate_node then
                engine.set_midi_val(voice_pool[v_idx].gate_node, 0.0)
            end
        end
    elseif msg.type == "cc" then
        -- Ruteo directo de CCs
        for i=1, 4 do
            local ch = params:get("midi_ch_"..i)
            if (ch == 0 or ch == msg.ch) and params:get("midi_mode_"..i) == 3 then
                if params:get("midi_cc_"..i) == msg.cc then
                    local val = msg.val / 127.0
                    if params:get("midi_pol_"..i) == 2 then val = (val * 2.0) - 1.0 end -- Bipolar
                    engine.set_midi_val(i, val)
                end
            end
        end
    end
end

-- Conectar todos los dispositivos MIDI
for i = 1, 4 do
    local m = midi.connect(i)
    m.event = midi_event
end

-- Sincronización de Reloj Global
clock.tempo_change_handler = function(bpm)
    engine.set_clock_bpm(bpm)
end

-- =====================================================================

osc.event = function(path, args, from)
    if path == '/elianne_levels' then
        if not G.node_levels then G.node_levels = {} end
        for i = 1, 69 do G.node_levels[i] = args[i + 2] or 0 end
        G.screen_dirty = true
    end
end

function init()
    pcall(G.init_nodes)
    pcall(Params.init, G)
    params:default()
    pcall(Matrix.init, G)
    pcall(GridUI.init, G)
    
    params.action_write = function(filename, name, number) Storage.save(G, number) end
    params.action_read = function(filename, silent, number) Storage.load(G, number) end
    
    engine.set_clock_bpm(clock.get_tempo())
    
    grid_metro = metro.init()
    grid_metro.time = 1/30
    grid_metro.event = function() GridUI.redraw(G, g) end
    grid_metro:start()
    
    screen_metro = metro.init()
    screen_metro.time = 1/15
    screen_metro.event = function() 
        if G.screen_dirty then redraw(); G.screen_dirty = false end
    end
    screen_metro:start()
end

function enc(n, d) ScreenUI.enc(G, n, d); G.screen_dirty = true end
function key(n, z) ScreenUI.key(G, n, z); G.screen_dirty = true end
g.key = function(x, y, z) GridUI.key(G, g, x, y, z) end
function redraw() screen.clear(); ScreenUI.draw(G); screen.update() end
function cleanup() if grid_metro then grid_metro:stop() end; if screen_metro then screen_metro:stop() end end
