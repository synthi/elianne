-- lib/storage.lua v0.1
-- CHANGELOG v0.1:
-- 1. TOTAL RECALL: Serialización de la matriz G.patch en archivos .data.
-- 2. CASCADE LOAD: Carga escalonada de la matriz hacia SC para evitar Kernel Panics.

local Storage = {}

function Storage.get_filename(pset_number)
    local name = string.format("%02d", pset_number)
    return _path.data .. "elianne/patch_" .. name .. ".data"
end

function Storage.save(G, pset_number)
    if not pset_number then return end
    
    if not util.file_exists(_path.data .. "elianne") then
        util.make_dir(_path.data .. "elianne")
    end
    
    local file = Storage.get_filename(pset_number)
    
    -- Solo necesitamos guardar la matriz de conexiones (G.patch).
    -- Los niveles (Attenuverters) ya se guardan nativamente en el .pset gracias a params_setup.lua
    local data = {
        patch = G.patch
    }
    
    tab.save(data, file)
    print("ELIANNE: Matriz guardada en PSET " .. pset_number)
end

function Storage.load(G, pset_number)
    if not pset_number then return end
    local file = Storage.get_filename(pset_number)
    
    if util.file_exists(file) then
        local data = tab.load(file)
        if data and data.patch then
            -- 1. Restaurar la tabla en Lua
            G.patch = data.patch
            
            -- 2. Carga Escalonada hacia SuperCollider (Cascade Load)
            -- Enviamos las 64 filas con un pequeño retraso para no saturar el bus OSC UDP
            local Matrix = include('lib/matrix')
            
            clock.run(function()
                for dst_id = 1, 64 do
                    Matrix.update_destination(dst_id, G)
                    clock.sleep(0.01) -- 10ms de respiro entre mensajes
                end
                print("ELIANNE: Matriz DSP restaurada (Total Recall).")
                G.screen_dirty = true
            end)
        end
    else
        print("ELIANNE: No se encontró archivo de matriz para este PSET. Iniciando en blanco.")
        -- Limpiar matriz si no hay archivo
        for src = 1, 64 do
            for dst = 1, 64 do
                G.patch[src][dst].active = false
            end
        end
        local Matrix = include('lib/matrix')
        for dst_id = 1, 64 do
            Matrix.update_destination(dst_id, G)
        end
        G.screen_dirty = true
    end
end

return Storage
