-- lib/storage.lua v0.100
-- CHANGELOG v0.100
-- 1. FIX: Adaptación a la arquitectura de Deltas (patch_set) para carga escalonada.

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
            -- 1. SMART CLEAR: Apagar SOLO los cables que están activos AHORA
            if G.patch then
                for dst_id = 1, 64 do
                    for src_id = 1, 64 do
                        if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
                            engine.patch_set(dst_id, src_id, 0.0)
                        end
                    end
                    -- Pausar todas las filas preventivamente
                    engine.pause_matrix_row(dst_id - 1)
                end
            end
            
            -- 2. Cargar la nueva topología en memoria
            G.patch = data.patch
            
            -- 3. CASCADE LOAD: Encender SOLO los cables del nuevo Pset
            clock.run(function()
                for dst_id = 1, 64 do
                    local has_active = false
                    for src_id = 1, 64 do
                        if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
                            engine.patch_set(dst_id, src_id, 1.0)
                            has_active = true
                            clock.sleep(0.002) -- Micro-respiro anti-flood
                        end
                    end
                    if has_active then
                        engine.resume_matrix_row(dst_id - 1)
                    end
                end
                print("ELIANNE: Pset " .. pset_number .. " cargado (Smart Clear aplicado).")
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
        
        -- Limpiar matriz en SC
        for src_id = 1, 64 do
            for dst_id = 1, 64 do
                engine.patch_set(dst_id, src_id, 0.0)
            end
        end
        G.screen_dirty = true
    end
end

return Storage
