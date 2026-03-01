-- lib/matrix.lua v0.103
-- CHANGELOG v0.103:
-- 1. OPTIMIZACIÓN: Implementado Array Batching (patch_row_set) en Matrix.init para evitar UDP Flood.

local Matrix = {}

local function evaluate_row_pause(dst_id, G)
    local active_count = 0
    for src_id = 1, 64 do
        if G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active then
            active_count = active_count + 1
        end
    end
    
    if active_count == 0 then
        engine.pause_matrix_row(dst_id - 1)
    else
        engine.resume_matrix_row(dst_id - 1)
    end
end

function Matrix.connect(src_id, dst_id, G)
    G.patch[src_id][dst_id].active = true
    engine.resume_matrix_row(dst_id - 1)
    engine.patch_set(dst_id, src_id, 1.0)
end

function Matrix.disconnect(src_id, dst_id, G)
    G.patch[src_id][dst_id].active = false
    engine.patch_set(dst_id, src_id, 0.0)
    evaluate_row_pause(dst_id, G)
end

function Matrix.init(G)
    -- 1. Enviar conexiones usando Array Batching (64 mensajes en lugar de 4096)
    for dst_id = 1, 64 do
        local has_active = false
        local row_vals = {}
        
        for src_id = 1, 64 do
            local is_active = G.patch[src_id] and G.patch[src_id][dst_id] and G.patch[src_id][dst_id].active
            row_vals[src_id] = is_active and 1.0 or 0.0
            if is_active then has_active = true end
        end
        
        -- Empaquetar y enviar la fila completa
        local row_str = table.concat(row_vals, ",")
        engine.patch_row_set(dst_id, row_str)
        
        if has_active then
            engine.resume_matrix_row(dst_id - 1)
        else
            engine.pause_matrix_row(dst_id - 1)
        end
    end
    
    -- 2. Inicializar niveles y paneos
    for i = 1, 64 do
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
    
    print("ELIANNE: Matriz DSP (Array Batching + Pausing) Inicializada al 100%.")
end

function Matrix.update_node_params(node)
    if node.type == "out" then
        engine.set_out_level(node.id, node.level)
    elseif node.type == "in" then
        engine.set_in_level(node.id, node.level)
        
        if node.module == 8 and node.id >= 55 and node.id <= 58 then
            engine.set_in_pan(node.id, node.pan)
            params:set("node_pan_" .. node.id, node.pan)
        end
    end
    
    params:set("node_lvl_" .. node.id, node.level)
end

return Matrix
