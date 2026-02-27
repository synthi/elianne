-- lib/storage.lua v0.2
-- CHANGELOG v0.2:
-- 1. SEGURIDAD: Inicialización segura de la matriz 64x64 en caso de archivo inexistente.

local Storage = {}

function Storage.get_filename(pset_number)
    local name = string.format("%02d", pset_number)
    return _path.data .. "elianne/patch_" .. name .. ".data"
end

function Storage.save(G, pset_number)
    if not pset_number then return end
    
    if not util.file_exists(_path.data .. "elianne") then
        os.execute("mkdir -p " .. _path.data .. "elianne/")
    end
    
    local file = Storage.get_filename(pset_number)
    
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
            G.patch = data.patch
            
            local Matrix = include('lib/matrix')
            
            clock.run(function()
                for dst_id = 1, 64 do
                    Matrix.update_destination(dst_id, G)
                    clock.sleep(0.01)
                end
                print("ELIANNE: Matriz DSP restaurada (Total Recall).")
                G.screen_dirty = true
            end)
        end
    else
        print("ELIANNE: No se encontró archivo de matriz para este PSET. Iniciando en blanco.")
        if not G.patch then G.patch = {} end
        for src = 1, 64 do
            if not G.patch[src] then G.patch[src] = {} end
            for dst = 1, 64 do
                if not G.patch[src][dst] then G.patch[src][dst] = { active = false, level = 1.0, pan = 0.0 } end
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
