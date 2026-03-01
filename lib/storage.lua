-- lib/storage.lua v0.205
-- CHANGELOG v0.205:
-- 1. FIX FATAL: Destrucción segura de la corrutina (Storage.morph_coroutine = nil) al cancelar.
-- 2. FIX: Implementado 'current_gain' en G.patch para evitar saltos de audio al interrumpir un Morph.

local Storage = {}

Storage.morph_coroutine = nil

local param_blacklist = {
    ["morph_time"] = true,["m8_master_vol"] = true
}

function Storage.get_filename(pset_number)
    local name = string.format("%02d", pset_number)
    return _path.data .. "elianne/state_" .. name .. ".data"
end

-- =====================================================================
-- GESTIÓN DE PSETS (PERSISTENCIA TOTAL)
-- =====================================================================
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
            if data.snapshots then G.snapshots = data.snapshots end
            G.active_snap = data.active_snap
            
            if data.patch then
                G.patch = data.patch
                
                clock.run(function()
                    for dst_id = 1, 64 do
                        local has_active = false
                        local row_vals = {}
                        
                        for src_id = 1, 64 do
                            local is_active = G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active
                            G.patch[src_id][dst_id].current_gain = is_active and 1.0 or 0.0
                            row_vals[src_id] = is_active and 1.0 or 0.0
                            if is_active then has_active = true end
                        end
                        
                        engine.patch_row_set(dst_id, table.concat(row_vals, ","))
                        if has_active then engine.resume_matrix_row(dst_id - 1) else engine.pause_matrix_row(dst_id - 1) end
                        
                        clock.sleep(0.002)
                    end
                    print("ELIANNE: Pset " .. pset_number .. " cargado (Array Batching).")
                    G.screen_dirty = true
                end)
            end
        end
    else
        print("ELIANNE: No se encontró archivo de estado para este PSET.")
    end
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
    
    -- FIX FATAL: Destrucción segura del puntero al interrumpir
    if Storage.morph_coroutine then 
        clock.cancel(Storage.morph_coroutine) 
        Storage.morph_coroutine = nil
    end
    
    local morph_time = params:get("morph_time")
    G.active_snap = snap_id
    
    if morph_time <= 0.05 then
        -- CARGA INSTANTÁNEA
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
            local row_vals = {}
            for src_id = 1, 64 do
                local is_active = target.patch[src_id][dst_id].active
                G.patch[src_id][dst_id].active = is_active
                G.patch[src_id][dst_id].current_gain = is_active and 1.0 or 0.0
                row_vals[src_id] = is_active and 1.0 or 0.0
                if is_active then has_active = true end
            end
            engine.patch_row_set(dst_id, table.concat(row_vals, ","))
            if has_active then engine.resume_matrix_row(dst_id - 1) else engine.pause_matrix_row(dst_id - 1) end
        end
        print("ELIANNE: Snapshot " .. snap_id .. " cargado instantáneamente.")
        G.screen_dirty = true
    else
        -- MOTOR DE MORPHING (Con State Tracking)
        local start_params = {}
        for p_id, _ in pairs(target.params) do start_params[p_id] = params:get(p_id) end
        
        local start_patch = {}
        for src_id = 1, 64 do
            start_patch[src_id] = {}
            for dst_id = 1, 64 do
                -- Si se interrumpió un morph, usamos el volumen exacto en el que se quedó
                local current = G.patch[src_id][dst_id].current_gain
                if not current then current = G.patch[src_id][dst_id].active and 1.0 or 0.0 end
                start_patch[src_id][dst_id] = current
            end
        end
        
        local start_time = util.time()
        
        for dst_id = 1, 64 do
            local needs_row = false
            for src_id = 1, 64 do
                if start_patch[src_id][dst_id] > 0 or target.patch[src_id][dst_id].active then needs_row = true end
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
                        for src_id = 1, 64 do
                            local is_active = target.patch[src_id][dst_id].active
                            G.patch[src_id][dst_id].active = is_active
                            G.patch[src_id][dst_id].current_gain = is_active and 1.0 or 0.0
                            engine.patch_set(dst_id, src_id, is_active and 1.0 or 0.0)
                            if is_active then has_active = true end
                        end
                        if not has_active then engine.pause_matrix_row(dst_id - 1) end
                    end
                    G.screen_dirty = true
                    print("ELIANNE: Morph completado.")
                    Storage.morph_coroutine = nil
                    break
                end
                
                -- INTERPOLACIÓN DE PARÁMETROS
                for p_id, end_val in pairs(target.params) do
                    local start_val = start_params[p_id]
                    if start_val ~= end_val then
                        local p_idx = params.lookup[p_id]
                        if p_idx then
                            local p_obj = params.params[p_idx]
                            if p_obj and p_obj.controlspec then
                                local current_val
                                if string.find(p_id, "tune") or string.find(p_id, "cutoff") then
                                    current_val = start_val * math.pow(end_val / start_val, progress)
                                else
                                    current_val = start_val + ((end_val - start_val) * progress)
                                end
                                params:set(p_id, current_val)
                                
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
                
                -- CROSSFADE DE MATRIZ (Interpolación Continua sin saltos)
                for dst_id = 1, 64 do
                    for src_id = 1, 64 do
                        local start_val = start_patch[src_id][dst_id]
                        local end_val = target.patch[src_id][dst_id].active and 1.0 or 0.0
                        
                        if start_val ~= end_val then
                            local current_val = start_val + ((end_val - start_val) * progress)
                            G.patch[src_id][dst_id].current_gain = current_val
                            engine.patch_set(dst_id, src_id, current_val)
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
