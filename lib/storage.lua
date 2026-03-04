-- lib/storage.lua v0.500
-- CHANGELOG v0.500:
-- 1. FEATURE: Persistencia de fader_map en PSETs con retrocompatibilidad.
-- 2. FIX: Desenganche automático de faders al cargar Snapshots (Morphing).
-- CHANGELOG v0.415:
-- 1. FIX FATAL: Corrutina anclada a G.morph_coroutine para evitar "lucha" de parámetros por includes dinámicos.
-- 2. FEATURE: True Crossfade Lineal (0% a 100% simultáneo para cables nuevos y viejos).
-- 3. FIX: Escudo params.lookup mantenido para evitar crasheos con PSETs antiguos.

local Storage = {}
local Matrix = include('lib/matrix')

local param_blacklist = {["morph_time"] = true, ["m8_master_vol"] = true}

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
        active_snap = G.active_snap,
        fader_map = G.fader_map -- ANOTACIÓN PARA EL EQUIPO: Guardamos el mapeo del 16n
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
            
            -- ANOTACIÓN PARA EL EQUIPO: Retrocompatibilidad segura para PSETs antiguos
            G.fader_map = data.fader_map or {}
            for i = 1, 16 do G.fader_latched[i] = false end
            
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
                    
                    for i = 1, 64 do
                        local node = G.nodes[i]
                        if node then
                            node.level = params:get("node_lvl_" .. i)
                            if node.module == 8 and i >= 55 and i <= 58 then
                                node.pan = params:get("node_pan_" .. i)
                            end
                            Matrix.update_node_params(node)
                        end
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
    
    -- FIX FATAL: Usamos G.morph_coroutine para que sobreviva a los includes dinámicos
    if G.morph_coroutine then 
        clock.cancel(G.morph_coroutine) 
        G.morph_coroutine = nil
    end
    
    -- ANOTACIÓN PARA EL EQUIPO: Desenganchar faders antes del Morphing
    for i = 1, 16 do G.fader_latched[i] = false end
    
    local morph_time = params:get("morph_time")
    G.active_snap = snap_id
    
    if morph_time <= 0.05 then
        -- CARGA INSTANTÁNEA
        for p_id, val in pairs(target.params) do 
            if params.lookup[p_id] then 
                params:set(p_id, val) 
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
        G.screen_dirty = true
    else
        -- MOTOR DE MORPHING (TRUE CROSSFADE LINEAL)
        local start_params = {}
        for p_id, _ in pairs(target.params) do 
            if params.lookup[p_id] then 
                start_params[p_id] = params:get(p_id) 
            end
        end
        
        local start_patch = {}
        for src_id = 1, 64 do
            start_patch[src_id] = {}
            for dst_id = 1, 64 do
                local current = G.patch[src_id][dst_id].current_gain
                if not current then current = G.patch[src_id][dst_id].active and 1.0 or 0.0 end
                start_patch[src_id][dst_id] = current
                
                -- TRUE CROSSFADE: Encender visualmente los cables nuevos al instante 0%
                if target.patch[src_id][dst_id].active then
                    G.patch[src_id][dst_id].active = true
                end
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
        
        -- Activar Lag Condicional en SC (Protegido por pcall)
        pcall(function() engine.set_morph_lag(0.1) end)
        
        G.morph_coroutine = clock.run(function()
            while true do
                local now = util.time()
                local progress = (now - start_time) / morph_time
                
                G.morph_percent = progress * 100 
                
                if progress >= 1.0 then
                    -- FINALIZAR MORPH
                    for p_id, val in pairs(target.params) do 
                        if params.lookup[p_id] then params:set(p_id, val) end
                    end
                    
                    for dst_id = 1, 64 do
                        local has_active = false
                        local row_vals = {}
                        for src_id = 1, 64 do
                            local is_active = target.patch[src_id][dst_id].active
                            
                            -- TRUE CROSSFADE: Apagar visualmente los cables muertos al 100%
                            G.patch[src_id][dst_id].active = is_active
                            G.patch[src_id][dst_id].current_gain = is_active and 1.0 or 0.0
                            row_vals[src_id] = is_active and 1.0 or 0.0
                            if is_active then has_active = true end
                        end
                        engine.patch_row_set(dst_id, table.concat(row_vals, ","))
                        if not has_active then engine.pause_matrix_row(dst_id - 1) end
                    end
                    
                    pcall(function() engine.set_morph_lag(0.0) end) 
                    
                    G.morph_percent = 100
                    G.morph_text_timer = util.time() + 1.0 
                    G.screen_dirty = true
                    G.morph_coroutine = nil
                    break
                end
                
                -- INTERPOLACIÓN DE PARÁMETROS
                for p_id, end_val in pairs(target.params) do
                    local start_val = start_params[p_id]
                    if start_val and start_val ~= end_val then
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
                            end
                        end
                    end
                end
                
                -- CROSSFADE DE MATRIZ (Interpolación Lineal Simultánea Pura)
                for dst_id = 1, 64 do
                    local row_changed = false
                    local row_vals = {}
                    
                    for src_id = 1, 64 do
                        local start_val = start_patch[src_id][dst_id]
                        local end_active = target.patch[src_id][dst_id].active
                        local end_val = end_active and 1.0 or 0.0
                        local current_val = start_val
                        
                        if start_val ~= end_val then
                            current_val = start_val + ((end_val - start_val) * progress)
                            if G.patch[src_id][dst_id].current_gain ~= current_val then
                                G.patch[src_id][dst_id].current_gain = current_val
                                row_changed = true
                            end
                        end
                        row_vals[src_id] = G.patch[src_id][dst_id].current_gain
                    end
                    
                    if row_changed then
                        engine.patch_row_set(dst_id, table.concat(row_vals, ","))
                    end
                end
                
                G.screen_dirty = true
                clock.sleep(1/30)
            end
        end)
    end
end

return Storage
