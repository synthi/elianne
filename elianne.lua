-- elianne.lua v0.5
-- CHANGELOG v0.5:
-- 1. INIT: Orden de inicialización estricto (Nodos -> Params -> Default -> Matrix -> Bang).
-- 2. OSC: Tabla G.node_levels inicializada de forma segura.

engine.name = 'Elianne'

local G = include('lib/globals')
local GridUI = include('lib/grid_ui')
local ScreenUI = include('lib/screen_ui')
local Matrix = include('lib/matrix')
local Params = include('lib/params_setup')
local Storage = include('lib/storage')

g = grid.connect()

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
    -- 1. Estructuras de Datos
    G.init_nodes()
    
    -- 2. Registro de Parámetros
    Params.init(G)
    
    -- 3. Cargar valores guardados (PSET)
    params:default()
    
    -- 4. Inicializar Matriz y UI (Ahora pueden leer los params cargados)
    Matrix.init(G)
    GridUI.init(G)
    
    -- 5. Interceptar guardado/carga
    params.action_write = function(filename, name, number) Storage.save(G, number) end
    params.action_read = function(filename, silent, number) Storage.load(G, number) end
    
    -- 6. Iniciar Temporizadores
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
    
    -- 7. Sincronizar SuperCollider con los valores actuales
    params:bang()
    
    print("ELIANNE: Sistema Forense Iniciado.")
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
    if grid_metro then grid_metro:stop() end
    if screen_metro then screen_metro:stop() end
end
