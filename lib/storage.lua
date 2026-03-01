-- lib/storage.lua v0.203
-- CHANGELOG v0.201:
-- 1. FIX FATAL: Añadida Blacklist para evitar que morph_time y master_vol se sobreescriban.
-- 2. FEATURE: Morphing de cables en 2 fases (Fade Out 0-50%, Fade In 50-100%).
-- 3. UI FIX: Sincronización de G.nodes durante el morph para feedback visual en tiempo real.

local Storage = {}

Storage.morph_coroutine = nil

local param_blacklist = {
    ["morph_time"] = true,["m8_master_vol"] = true
}

function Storage.get_filename(pset_number)
    local name = string.format("%02d", pset_number)
    return _path.data .. "elianne/state_" .. name .. ".data"
end

-- FIX: Función de migración para Psets antiguos (64 -> 69)
local function migrate_patch(patch)
    if not patch then return end
    for src = 1, 69 do
        if not patch[src] then
            patch[src] = {}
            for dst = 1, 64 do
                patch[src][dst] = { active = false, level = 1.0, pan = 0.0 }
            end
        end
    end
end

function Storage.save(G, pset_number)
    if not pset_number then return end
    if not util.file_exists(_path.data .. "elianne") then os.execute("mkdir -p " .. _path.data .. "elianne/") end
    
    local file = Storage.get_filename(pset_number)
    local data = {
        patch = G.patch,
        snapshots = G.snapshots,
        active_snap = G.active_snap
    }
    tab.save(data, file)
    print("ELIANNE: Estado Total guardado en PSET " .. pset_number)
end

function Storage.load(G, pset_number)
    if not pset_number then return end
    local file = Storage.get_filename(pset_number)
    
    if util.file_exists(file) then
        local data = tab.load(file)
        if data then
            G.pset_loaded = true -- FIX: Bandera para evitar Race Condition en Matrix.init
            
            if data.snapshots then 
                G.snapshots = data.snapshots 
                for i=1, 6 do
                    if G.snapshots[i].has_data then migrate_patch(G.snapshots[i].patch) end
                end
            end
            G.active_snap = data.active_snap
            
            if data.patch then
                migrate_patch(data.patch) -- FIX: Migrar matriz principal
                
                if G.patch then
                    for dst_id = 1, 64 do
                        for src_id = 1, 69 do
                            if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
                                engine.patch_set(dst_id, src_id, 0.0)
                            end
                        end
                        engine.pause_matrix_row(dst_id - 1)
                    end
                end
                
                G.patch = data.patch
                
                clock.run(function()
                    for dst_id = 1, 64 do
                        local has_active = false
                        for src_id = 1, 69 do
                            if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
                                engine.patch_set(dst_id, src_id, 1.0)
                                has_active = true
                                clock.sleep(0.002)
                            end
                        end
                        if has_active then engine.resume_matrix_row(dst_id - 1) end
                    end
                    print("ELIANNE: Pset " .. pset_number .. " cargado.")
                    G.screen_dirty = true
                end)
            end
        end
    else
        print("ELIANNE: No se encontró archivo de estado para este PSET.")
    end
end

#### 3. Prevención de Carrera en `lib/matrix.lua`
Abre `lib/matrix.lua`. Busca la función `Matrix.init(G)` y **sustitúyela completamente** por esta:

```lua
function Matrix.init(G)
    -- FIX: Si Storage.load ya está enviando los cables, Matrix.init se salta este paso para evitar Race Condition
    if not G.pset_loaded then
        for dst_id = 1, 64 do
            local has_active = false
            for src_id = 1, 69 do
                if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
                    engine.patch_set(dst_id, src_id, 1.0)
                    has_active = true
                end
            end
            if has_active then engine.resume_matrix_row(dst_id - 1) else engine.pause_matrix_row(dst_id - 1) end
        end
    end
    
    for i = 1, 69 do
        local lvl = params:get("node_lvl_" .. i)
        local node = G.nodes[i]
        if node then
            node.level = lvl
            if node.type == "out" then
                engine.set_out_level(i, lvl)
            elseif node.type == "in" then
                engine.set_in_level(i, lvl)
                if node.module == 8 and i >= 55 and i <= 58 then
                    local pan = params:get("node_pan_" .. i)
                    node.pan = pan
                    engine.set_in_pan(i, pan)
                end
            end
        end
    end
    print("ELIANNE: Matriz DSP (69x64) Inicializada.")
end

-- =====================================================================
-- GESTIÓN DE SNAPSHOTS (RAM)
-- =====================================================================
local function copy_table(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do res[copy_table(k)] = copy_table(v) end
    return res
end

function Storage.save_snapshot(G, snap_id)
    local snap = G.snapshots[snap_id]
    snap.patch = copy_table(G.patch)
    
    snap.params = {}
    for _, p in pairs(params.params) do
        if p.save and not param_blacklist[p.id] then
            snap.params[p.id] = params:get(p.id)
        end
    end
    
    snap.has_data = true
    G.active_snap = snap_id
    print("ELIANNE: Snapshot " .. snap_id .. " guardado.")
end

function Storage.load_snapshot(G, snap_id)
    local target = G.snapshots[snap_id]
    if not target or not target.has_data then return end
    
    if Storage.morph_coroutine then clock.cancel(Storage.morph_coroutine) end
    
    local morph_time = params:get("morph_time")
    G.active_snap = snap_id
    
    if morph_time <= 0.05 then
        -- CARGA INSTANTÁNEA
        for p_id, val in pairs(target.params) do 
            params:set(p_id, val) 
            -- Sincronizar UI de Attenuverters
            if string.find(p_id, "node_lvl_") then
                local n_id = tonumber(string.sub(p_id, 10))
                if G.nodes[n_id] then G.nodes[n_id].level = val end
            elseif string.find(p_id, "node_pan_") then
                local n_id = tonumber(string.sub(p_id, 10))
                if G.nodes[n_id] then G.nodes[n_id].pan = val end
            end
        end
        
        for dst_id = 1, 64 do
            local has_active = false
            for src_id = 1, 69 do -- FIX: 69
                local is_active = target.patch[src_id][dst_id].active
                G.patch[src_id][dst_id].active = is_active
                engine.patch_set(dst_id, src_id, is_active and 1.0 or 0.0)
                if is_active then has_active = true end
            end
            if has_active then engine.resume_matrix_row(dst_id - 1) else engine.pause_matrix_row(dst_id - 1) end
        end
        print("ELIANNE: Snapshot " .. snap_id .. " cargado instantáneamente.")
        G.screen_dirty = true
    else
        -- MOTOR DE MORPHING
        local start_params = {}
        for p_id, _ in pairs(target.params) do start_params[p_id] = params:get(p_id) end
        
        local start_patch = copy_table(G.patch)
        local start_time = util.time()
        
        for dst_id = 1, 64 do
            local needs_row = false
            for src_id = 1, 69 do --fix 69 josu
                if start_patch[src_id][dst_id].active or target.patch[src_id][dst_id].active then needs_row = true end
            end
            if needs_row then engine.resume_matrix_row(dst_id - 1) end
        end
        
        Storage.morph_coroutine = clock.run(function()
            print("ELIANNE: Iniciando Morph hacia Snapshot " .. snap_id .. " (" .. morph_time .. "s)")
            while true do
                local now = util.time()
                local progress = (now - start_time) / morph_time
                
                if progress >= 1.0 then
                    -- FINALIZAR MORPH
                    for p_id, val in pairs(target.params) do 
                        params:set(p_id, val) 
                        if string.find(p_id, "node_lvl_") then
                            local n_id = tonumber(string.sub(p_id, 10))
                            if G.nodes[n_id] then G.nodes[n_id].level = val end
                        elseif string.find(p_id, "node_pan_") then
                            local n_id = tonumber(string.sub(p_id, 10))
                            if G.nodes[n_id] then G.nodes[n_id].pan = val end
                        end
                    end
                    for dst_id = 1, 64 do
                        local has_active = false
                        for src_id = 1, 69 do --fix 69 josu
                            local is_active = target.patch[src_id][dst_id].active
                            G.patch[src_id][dst_id].active = is_active
                            engine.patch_set(dst_id, src_id, is_active and 1.0 or 0.0)
                            if is_active then has_active = true end
                        end
                        if not has_active then engine.pause_matrix_row(dst_id - 1) end
                    end
                    G.screen_dirty = true
                    print("ELIANNE: Morph completado.")
                    break
                end
                
                -- INTERPOLACIÓN DE PARÁMETROS
                for p_id, end_val in pairs(target.params) do
                    local start_val = start_params[p_id]
                    if start_val ~= end_val then
                        local p_idx = params.lookup[p_id]
                        if p_idx then
                            local p_obj = params.params[p_idx]
                            -- FIX: La API de Norns no usa .type en el objeto instanciado. 
                            -- Usamos .controlspec para saber si es un valor continuo interpolable.
                            if p_obj and p_obj.controlspec then
                                local current_val
                                if string.find(p_id, "tune") or string.find(p_id, "cutoff") then
                                    -- Interpolación Exponencial para Frecuencias
                                    current_val = start_val * math.pow(end_val / start_val, progress)
                                else
                                    -- Interpolación Lineal
                                    current_val = start_val + ((end_val - start_val) * progress)
                                end
                                params:set(p_id, current_val)
                                
                                -- Sincronizar UI en tiempo real
                                if string.find(p_id, "node_lvl_") then
                                    local n_id = tonumber(string.sub(p_id, 10))
                                    if G.nodes[n_id] then G.nodes[n_id].level = current_val end
                                elseif string.find(p_id, "node_pan_") then
                                    local n_id = tonumber(string.sub(p_id, 10))
                                    if G.nodes[n_id] then G.nodes[n_id].pan = current_val end
                                end
                            end
                        end
                    end
                end
                
                -- CROSSFADE DE MATRIZ (Simultáneo 0-100%)
                for dst_id = 1, 64 do
                    for src_id = 1, 69 do -- FIX: 69
                        local start_active = start_patch[src_id][dst_id].active
                        local end_active = target.patch[src_id][dst_id].active
                        
                        if start_active and not end_active then
                            engine.patch_set(dst_id, src_id, 1.0 - progress)
                        elseif not start_active and end_active then
                            engine.patch_set(dst_id, src_id, progress)
                        end
                    end
                end
                
                G.screen_dirty = true
                clock.sleep(1/30)
            end
        end)
    end
end

return Storage
