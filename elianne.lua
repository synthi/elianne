-- elianne.lua v0.1.2
-- Motor Principal - Proyecto ELIANNE (Grado Científico)
-- Arquitectura: Raspberry Pi 4 / Monome Norns / Grid 128

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

G.node_levels = {}
for i = 1, 64 do G.node_levels[i] = 0 end

osc.event = function(path, args, from)
    if path == '/elianne_levels' then
        -- args[1] y[2] son node_id y synth_id internos de SC. Los datos empiezan en args[3]
        for i = 1, 64 do
            G.node_levels[i] = args[i + 2] or 0
        end
        G.screen_dirty = true -- Forzar actualización visual si es necesario
    end
end

function init()
    -- Inicializar base de datos de nodos
    G.init_nodes()
    Params.init(G)
    Matrix.init(G)
    
    -- Inicializar caché del Grid
    GridUI.init(G)
    
    -- Temporizador del Grid (30 fps para animaciones fluidas y respiración)
    grid_metro = metro.init()
    grid_metro.time = 1/30
    grid_metro.event = function() 
        GridUI.redraw(G, g) 
    end
    grid_metro:start()
    
    -- Temporizador de Pantalla (15 fps, protegido por screen_dirty)
    screen_metro = metro.init()
    screen_metro.time = 1/15
    screen_metro.event = function() 
        if G.screen_dirty then
            redraw()
            G.screen_dirty = false
        end
    end
    screen_metro:start()

    -- Interceptar guardado/carga de Norns
    params.action_write = function(filename, name, number) Storage.save(G, number) end
    params.action_read = function(filename, silent, number) Storage.load(G, number) end

    -- Sincronización inicial obligatoria (Evita desajustes SC/Lua)
    params:default()
    params:bang()
    
    print("ELIANNE: Sistema Forense Iniciado.")
end

function enc(n, d)
    -- Enrutar encoders a la interfaz de pantalla
    ScreenUI.enc(G, n, d)
    G.screen_dirty = true
end

function key(n, z)
    -- Enrutar teclas a la interfaz de pantalla
    ScreenUI.key(G, n, z)
    G.screen_dirty = true
end

g.key = function(x, y, z)
    -- Enrutar eventos del Grid
    GridUI.key(G, g, x, y, z)
end

function redraw()
    screen.clear()
    ScreenUI.draw(G)
    screen.update()
end

function cleanup()
    grid_metro:stop()
    screen_metro:stop()
end
