-- elianne.lua v0.6
-- CHANGELOG v0.6:
-- 1. TELEMETRÍA: Inyección de logs de depuración extremos para rastreo de inicialización.
-- 2. SEGURIDAD: Bloques pcall (protected call) en la inicialización para evitar cuelgues silenciosos.

engine.name = 'Elianne'

print("========================================")
print("ELIANNE DEBUG: INICIANDO CARGA DE MÓDULOS")
print("========================================")

local G, GridUI, ScreenUI, Matrix, Params, Storage

-- Carga protegida de dependencias
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
end

local status, err = pcall(load_dependencies)
if not status then
    print("ELIANNE FATAL ERROR (Dependencias): " .. err)
end

g = grid.connect()
print("ELIANNE DEBUG: Grid conectado.")

local grid_metro
local screen_metro

-- Inicialización segura de la tabla de respiración
G.node_levels = {}
for i = 1, 64 do G.node_levels[i] = 0 end

osc.event = function(path, args, from)
    if path == '/elianne_levels' then
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
    
    print("ELIANNE DEBUG: 1. Inicializando Nodos (G.init_nodes)...")
    local s1, e1 = pcall(G.init_nodes)
    if not s1 then print("ERROR EN NODOS: " .. e1) end
    
    print("ELIANNE DEBUG: 2. Registrando Parámetros (Params.init)...")
    local s2, e2 = pcall(Params.init, G)
    if not s2 then print("ERROR EN PARAMS: " .. e2) end
    
    print("ELIANNE DEBUG: 3. Cargando PSET por defecto (params:default)...")
    params:default()
    
    print("ELIANNE DEBUG: 4. Inicializando Matriz DSP (Matrix.init)...")
    local s3, e3 = pcall(Matrix.init, G)
    if not s3 then print("ERROR EN MATRIZ: " .. e3) end
    
    print("ELIANNE DEBUG: 5. Inicializando UI del Grid (GridUI.init)...")
    local s4, e4 = pcall(GridUI.init, G)
    if not s4 then print("ERROR EN GRID UI: " .. e4) end
    
    print("ELIANNE DEBUG: 6. Configurando interceptores de guardado...")
    params.action_write = function(filename, name, number) Storage.save(G, number) end
    params.action_read = function(filename, silent, number) Storage.load(G, number) end
    
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
    
    print("ELIANNE DEBUG: 8. Sincronizando SC (params:bang)...")
    params:bang()
    
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
