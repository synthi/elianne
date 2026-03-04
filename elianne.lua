-- elianne.lua v0.502
-- CHANGELOG v0.502:
-- 1. FIX: Orden de Boot corregido para cargar PSETs completos (Cables y Mapeos) al arrancar.
-- 2. FIX: Faders ahora controlan el audio inmediatamente dentro del Modo Learn.
-- 3. FEATURE: Lag base de 50ms inyectado en SC para eliminar Zipper Noise de MIDI CC.
-- 4. FEATURE: Integración completa de 16n Faderbank con Soft-Takeover y Grid-Learn.

engine.name = 'Elianne'

print("========================================")
print("ELIANNE DEBUG: INICIANDO CARGA DE MÓDULOS")
print("========================================")

local G, GridUI, ScreenUI, Matrix, Params, Storage, Sixteen

local function load_dependencies()
    G = include('lib/globals')
    print("ELIANNE DEBUG: globals.lua cargado.")
    GridUI = include('lib/grid_ui')
    print("ELIANNE DEBUG: grid_ui.lua cargado.")
    ScreenUI = include('lib/screen_ui')
    print("ELIANNE DEBUG: screen_ui.lua cargado.")
    Matrix = include('lib/matrix')
    print("ELIANNE DEBUG: matrix.lua cargado.")
    Params = include('lib/params_setup')
    print("ELIANNE DEBUG: params_setup.lua cargado.")
    Storage = include('lib/storage')
    print("ELIANNE DEBUG: storage.lua cargado.")
    Sixteen = include('lib/16n')
    print("ELIANNE DEBUG: 16n.lua cargado.")
end

-- Carga directa sin pcall. Si falla, crashea en Maiden como exige el protocolo.
load_dependencies()

g = grid.connect()
print("ELIANNE DEBUG: Grid conectado.")

local grid_metro
local screen_metro

osc.event = function(path, args, from)
    if path == '/elianne_levels' then
        if not G.node_levels then G.node_levels = {} end
        for i = 1, 64 do
            G.node_levels[i] = args[i + 2] or 0
        end
        G.screen_dirty = true
    end
end

function init()
    print("========================================")
    print("ELIANNE DEBUG: INICIANDO BOOT SEQUENCE")
    print("========================================")
    
    -- CANDADO DE ARRANQUE SEGURO
    G.booting = true
    
    print("ELIANNE DEBUG: 1. Inicializando Nodos (G.init_nodes)...")
    local s1, e1 = pcall(G.init_nodes)
    if not s1 then print("ERROR EN NODOS: " .. e1) end
    
    print("ELIANNE DEBUG: 2. Registrando Parámetros (Params.init)...")
    local s2, e2 = pcall(Params.init, G)
    if not s2 then print("ERROR EN PARAMS: " .. e2) end
    
    -- ANOTACIÓN PARA EL EQUIPO: Interceptores movidos ANTES de params:default() para cargar el PSET completo
    print("ELIANNE DEBUG: 3. Configurando interceptores de guardado...")
    params.action_write = function(filename, name, number) Storage.save(G, number) end
    params.action_read = function(filename, silent, number) Storage.load(G, number) end
    
    print("ELIANNE DEBUG: 4. Cargando PSET por defecto (params:default)...")
    params:default()
    
    print("ELIANNE DEBUG: 5. Inicializando Matriz DSP (Matrix.init)...")
    local s3, e3 = pcall(Matrix.init, G)
    if not s3 then print("ERROR EN MATRIZ: " .. e3) end
    
    print("ELIANNE DEBUG: 6. Inicializando UI del Grid (GridUI.init)...")
    local s4, e4 = pcall(GridUI.init, G)
    if not s4 then print("ERROR EN GRID UI: " .. e4) end
    
    print("ELIANNE DEBUG: 7. Iniciando Metros (Grid y Pantalla)...")
    grid_metro = metro.init()
    grid_metro.time = 1/30
    grid_metro.event = function() GridUI.redraw(G, g) end
    grid_metro:start()
    
    screen_metro = metro.init()
    screen_metro.time = 1/15
    screen_metro.event = function() 
        if G.screen_dirty then
            redraw()
            G.screen_dirty = false
        end
    end
    screen_metro:start()
    
    print("ELIANNE DEBUG: 8. Inicializando 16n Faderbank...")
    Sixteen.init(function(msg)
        if G.booting then return end
        
        -- BLOQUEO CRÍTICO: Si hay Morphing en curso, ignoramos el hardware físicamente.
        if G.morph_percent and G.morph_percent >= 0 and G.morph_percent < 100 then return end

        local slider_id = Sixteen.cc_2_slider_id(msg.cc)
        if not slider_id then return end

        local val = msg.val / 127 -- Normalizado 0.0 a 1.0

        -- Cálculo de Inercia Temporal (Filtro Anti-Jitter Visual)
        local now = util.time()
        if now - (G.fader_last_move[slider_id] or 0) > 0.2 then
            G.fader_move_start[slider_id] = now
        end
        G.fader_last_move[slider_id] = now
        
        local wake_ui = (now - G.fader_move_start[slider_id]) >= 0.05

        -- MODO LEARN: Asignación dinámica desde el Grid
        if G.learn_mode then
            if G.last_touched_param then
                G.fader_map[slider_id] = G.last_touched_param
                local p_name = G.last_touched_param
                local p = params.lookup[G.last_touched_param]
                if p then p_name = params.params[p].name end
                
                if wake_ui then
                    G.ui_text_state.text = "MAPPED: F" .. slider_id .. " -> " .. string.sub(p_name, 1, 10)
                    G.ui_text_state.level = 15
                    G.ui_text_state.timer = util.time() + 1.5
                    G.ui_text_state.is_fader = true
                    G.screen_dirty = true
                end
                
                -- Auto-enganchar al mapear para feedback inmediato
                G.fader_latched[slider_id] = true
            end
            -- ANOTACIÓN PARA EL EQUIPO: No hay 'return' aquí. El código sigue para aplicar el audio inmediatamente.
        end

        -- MODO NORMAL: Soft-Takeover (Catch-up)
        local param_id = G.fader_map[slider_id]
        if param_id and params.lookup[param_id] then
            local current_val = params:get_raw(param_id)
            local p_name = params.params[params.lookup[param_id]].name
            local short_name = string.sub(p_name, 1, 10)

            if not G.fader_latched[slider_id] then
                -- Umbral de enganche (5% de tolerancia)
                if math.abs(val - current_val) < 0.05 then
                    G.fader_latched[slider_id] = true
                else
                    -- Mostrar flechas direccionales compactas
                    if wake_ui then
                        if val < current_val then
                            G.ui_text_state.text = "[F" .. slider_id .. "] " .. short_name .. " >>>"
                        else
                            G.ui_text_state.text = "<<< " .. short_name .. "[F" .. slider_id .. "]"
                        end
                        G.ui_text_state.level = 15
                        G.ui_text_state.timer = util.time() + 1.0
                        G.ui_text_state.is_fader = true
                        G.screen_dirty = true
                    end
                    return
                end
            end

            if G.fader_latched[slider_id] then
                -- Aplicar valor al motor (0 lag)
                params:set_raw(param_id, val)
                
                -- Mostrar valor actual formateado (Solo si no estamos en modo Learn para no pisar el cartel MAPPED)
                if wake_ui and not G.learn_mode then
                    local display_val = params:string(param_id)
                    G.ui_text_state.text = "[F" .. slider_id .. "] " .. short_name .. ": " .. display_val
                    G.ui_text_state.level = 15
                    G.ui_text_state.timer = util.time() + 1.0
                    G.ui_text_state.is_fader = true
                    G.screen_dirty = true
                end
            end
        end
    end)
    
    print("ELIANNE DEBUG: 9. Ejecutando params:bang() protegido...")
    params:bang()
    
    -- ANOTACIÓN PARA EL EQUIPO: Lag base de 50ms inyectado en SC para eliminar Zipper Noise de MIDI
    pcall(function() engine.set_morph_lag(0.05) end)
    
    -- LIBERACIÓN DEL CANDADO
    G.booting = false
    
    print("========================================")
    print("ELIANNE DEBUG: BOOT COMPLETADO EXITOSAMENTE")
    print("========================================")
end

function enc(n, d)
    ScreenUI.enc(G, n, d)
    G.screen_dirty = true
end

function key(n, z)
    ScreenUI.key(G, n, z)
    G.screen_dirty = true
end

g.key = function(x, y, z)
    GridUI.key(G, g, x, y, z)
end

function redraw()
    screen.clear()
    ScreenUI.draw(G)
    screen.update()
end

function cleanup()
    print("ELIANNE DEBUG: Ejecutando Cleanup...")
    if grid_metro then grid_metro:stop() end
    if screen_metro then screen_metro:stop() end
end
